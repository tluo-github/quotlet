import AppKit
import Charts
import SwiftUI

// MARK: - 窗口

/// 「用量历史」窗口：面板里点「历史」打开。用 AppKit 窗口承载 SwiftUI（状态栏 app 的 SwiftUI Window 场景在
/// macOS 14 上可能启动时自己弹出来），工具栏通过 sceneBridgingOptions 交给 SwiftUI 的 .toolbar。
/// 窗口开着时 app 出现在程序坞和 ⌘Tab 里，关掉后回到只有状态栏图标。
@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    static let shared = HistoryWindowController()
    private var window: NSWindow?

    func show(store: Store) {
        if window == nil {
            let host = NSHostingController(rootView: HistoryView().environmentObject(store))
            host.sceneBridgingOptions = [.toolbars, .title]
            let w = NSWindow(contentViewController: host)
            w.title = L("用量历史", "Usage History", ja: "使用量の履歴", ko: "사용량 기록")
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.setContentSize(NSSize(width: 1120, height: 820))
            w.contentMinSize = NSSize(width: 820, height: 560)
            w.center()
            w.setFrameAutosaveName("QuotletHistory")
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - 筛选

enum HistoryRange: String, CaseIterable, Identifiable {
    case today, yesterday, d7, d30, d90, year, all
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return L("今天", "Today", ja: "今日", ko: "오늘")
        case .yesterday: return L("昨天", "Yesterday", ja: "昨日", ko: "어제")
        case .d7: return L("7 天", "7 days", ja: "7 日", ko: "7일")
        case .d30: return L("30 天", "30 days", ja: "30 日", ko: "30일")
        case .d90: return L("90 天", "90 days", ja: "90 日", ko: "90일")
        case .year: return L("今年", "This year", ja: "今年", ko: "올해")
        case .all: return L("全部", "All", ja: "すべて", ko: "전체")
        }
    }

    var hourly: Bool { self == .today || self == .yesterday }

    /// [开始, 结束)，按本地日历的整天
    func interval(now: Date, earliest: Date?) -> (start: Date, end: Date) {
        let cal = Fmt.calendar
        let today = cal.startOfDay(for: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        func back(_ n: Int) -> Date { cal.date(byAdding: .day, value: -(n - 1), to: today)! }
        switch self {
        case .today: return (today, tomorrow)
        case .yesterday: return (cal.date(byAdding: .day, value: -1, to: today)!, today)
        case .d7: return (back(7), tomorrow)
        case .d30: return (back(30), tomorrow)
        case .d90: return (back(90), tomorrow)
        case .year: return (cal.date(from: cal.dateComponents([.year], from: now))!, tomorrow)
        case .all: return (min(cal.startOfDay(for: earliest ?? back(30)), back(7)), tomorrow)
        }
    }
}

enum SourceFilter: String, CaseIterable, Identifiable {
    case all, claude, codex
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return L("全部来源", "All sources", ja: "すべてのソース", ko: "모든 소스")
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }
    func includes(_ s: Source) -> Bool { self == .all || s.rawValue == rawValue }
    func includes(_ s: String) -> Bool { self == .all || s == rawValue }
}

enum ChartMetric: String, CaseIterable, Identifiable {
    case output, cost
    var id: String { rawValue }
    var title: String {
        switch self {
        case .output: return L("每日输出", "Output", ja: "出力", ko: "출력")
        case .cost: return L("费用", "Cost", ja: "費用", ko: "비용")
        }
    }
}

// MARK: - 数据

/// 图上的一根柱子（一小时 / 一天 / 一周）
struct HistoryBucket: Identifiable {
    var id: Date { start }
    let start: Date
    var claude = UsageStats()
    var codex = UsageStats()
    var total: UsageStats {
        var t = claude
        t.tokens += codex.tokens
        t.requests += codex.requests
        t.cost += codex.cost
        t.unpricedRequests += codex.unpricedRequests
        t.timedOutput += codex.timedOutput
        t.timedSeconds += codex.timedSeconds
        return t
    }
}

extension UsageStats {
    mutating func add(row r: HistoryStore.DayRow) {
        tokens += r.tokens
        requests += r.requests
        cost += r.cost
        unpricedRequests += r.unpriced
        timedOutput += r.timedOutput
        timedSeconds += r.timedSeconds
    }

    static func + (a: UsageStats, b: UsageStats) -> UsageStats {
        var t = a
        t.tokens += b.tokens
        t.requests += b.requests
        t.cost += b.cost
        t.unpricedRequests += b.unpricedRequests
        t.timedOutput += b.timedOutput
        t.timedSeconds += b.timedSeconds
        return t
    }
}

struct HistoryData {
    let range: HistoryRange
    let start: Date
    let end: Date
    let unit: Calendar.Component       // .hour / .day / .weekOfYear
    let buckets: [HistoryBucket]
    let total: UsageStats
    let previous: UsageStats           // 上一段同样长的时间，用来比较
    let projects: [(name: String, tokens: Int)]
    let projectUsage: [String: [Date: [Source: TokenCount]]]
    let models: [(name: String, source: String, output: Int, speed: Double?)]
    let activeDays: Int

    static func build(range: HistoryRange, source: SourceFilter, rows: [HistoryStore.DayRow],
                      messages: [MessageUsage], now: Date) -> HistoryData {
        let cal = Fmt.calendar
        let earliest = rows.first.flatMap { HistoryStore.date(ofDay: $0.day) }
        let (start, end) = range.interval(now: now, earliest: earliest)
        let days = cal.dateComponents([.day], from: start, to: end).day ?? 1
        let unit: Calendar.Component = range.hourly ? .hour : (days > 120 ? .weekOfYear : .day)

        func bucketStart(_ d: Date) -> Date {
            switch unit {
            case .hour: return cal.dateInterval(of: .hour, for: d)!.start
            case .weekOfYear: return cal.dateInterval(of: .weekOfYear, for: d)!.start
            default: return cal.startOfDay(for: d)
            }
        }
        var buckets: [Date: HistoryBucket] = [:]
        var t = bucketStart(start)
        while t < end {
            buckets[t] = HistoryBucket(start: t)
            t = cal.date(byAdding: unit, value: 1, to: t)!
        }

        var total = UsageStats()
        var previous = UsageStats()
        var projects: [String: Int] = [:]
        var projectUsage: [String: [Date: [Source: TokenCount]]] = [:]
        func addProject(_ name: String, _ date: Date, _ source: Source, _ tokens: TokenCount) {
            projects[name, default: 0] += tokens.total
            projectUsage[name, default: [:]][date, default: [:]][source, default: TokenCount()] += tokens
        }
        var models: [String: (source: String, output: Int, timedOut: Int, secs: Double)] = [:]
        var active = Set<String>()
        let prevStart = cal.date(byAdding: .day, value: -max(1, days), to: start)!

        if range.hourly {
            // 今天 / 昨天：直接用本机日志，按小时
            for m in messages where source.includes(m.source) {
                if m.ts >= prevStart && m.ts < start { previous.add(m) }
                guard m.ts >= start && m.ts < end else { continue }
                let k = bucketStart(m.ts)
                if m.source == .claude { buckets[k]?.claude.add(m) } else { buckets[k]?.codex.add(m) }
                total.add(m)
                addProject(m.project, k, m.source, m.tokens)
                var e = models[m.model] ?? (m.source.rawValue, 0, 0, 0)
                e.output += m.tokens.output
                if let (out, d) = m.timed { e.timedOut += out; e.secs += d }
                models[m.model] = e
            }
            if total.requests > 0 { active.insert(HistoryStore.dayKey(start)) }
        } else {
            // 更长的时间：用每日汇总存档
            for r in rows where source.includes(r.source) {
                guard let d = HistoryStore.date(ofDay: r.day) else { continue }
                if d >= prevStart && d < start { previous.add(row: r) }
                guard d >= start && d < end else { continue }
                let k = bucketStart(d)
                if r.source == Source.claude.rawValue { buckets[k]?.claude.add(row: r) } else { buckets[k]?.codex.add(row: r) }
                total.add(row: r)
                if let provider = Source(rawValue: r.source) { addProject(r.project, k, provider, r.tokens) }
                var e = models[r.model] ?? (r.source, 0, 0, 0)
                e.output += r.output
                e.timedOut += r.timedOutput
                e.secs += r.timedSeconds
                models[r.model] = e
                if r.requests > 0 { active.insert(r.day) }
            }
            // 峰值速度只在本机日志里有（每日汇总不存单条回复）
            for m in messages where source.includes(m.source) && m.ts >= start && m.ts < end {
                if let d = m.duration, m.tokens.output >= 200, d >= 2 {
                    let s = Double(m.tokens.output) / d
                    if s > total.peakSpeed { total.peakSpeed = s; total.peakAt = m.ts }
                }
            }
        }

        return HistoryData(
            range: range, start: start, end: end, unit: unit,
            buckets: buckets.values.sorted { $0.start < $1.start },
            total: total, previous: previous,
            projects: projects.map { ($0.key, $0.value) }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 },
            projectUsage: projectUsage,
            models: models.map { (Fmt.modelName($0.key), $0.value.source, $0.value.output,
                                  $0.value.secs > 0 ? Double($0.value.timedOut) / $0.value.secs : nil) }
                .filter { $0.2 > 0 }.sorted { $0.2 > $1.2 }.prefix(6).map { $0 },
            activeDays: active.count)
    }
}

// MARK: - 界面

struct HistoryView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var history = HistoryStore.shared
    @AppStorage("historyRange") private var range: HistoryRange = .d30
    @AppStorage("historySource") private var source: SourceFilter = .all
    @AppStorage("historyMetric") private var metric: ChartMetric = .output
    @State private var search = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let data = HistoryData.build(range: range, source: source, rows: history.rows,
                                         messages: store.local?.messages ?? [], now: ctx.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("用量历史", "Usage History", ja: "使用量の履歴", ko: "사용량 기록"))
                            .font(.system(size: 24, weight: .bold))
                        Text(subtitle(data)).font(.system(size: 13)).foregroundStyle(Theme.text2)
                    }
                    KPIRow(data: data)
                    UsageChartCard(data: data, metric: $metric)
                    ProjectTrendCard(data: data, now: ctx.date)
                    HStack(alignment: .top, spacing: 16) {
                        QuotaHistoryCard(readings: history.quota, now: ctx.date)
                            .frame(maxWidth: .infinity)
                        BreakdownCard(data: data)
                            .frame(width: 320)
                    }
                    SessionsCard(sessions: sessions(data), now: ctx.date, search: $search)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .frame(maxWidth: 1400, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.surface)
            .safeAreaInset(edge: .bottom, spacing: 0) { statusBar(data) }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker(L("来源", "Source", ja: "ソース", ko: "소스"), selection: $source) {
                    ForEach(SourceFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
            ToolbarItem(placement: .principal) {
                Picker(L("时间段", "Range", ja: "期間", ko: "기간"), selection: $range) {
                    ForEach(HistoryRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            ToolbarItem(placement: .primaryAction) {
                Button(L("导出 CSV…", "Export CSV…", ja: "CSV を書き出す…", ko: "CSV 내보내기…")) { exportCSV() }
            }
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    private func subtitle(_ d: HistoryData) -> String {
        let cal = Fmt.calendar
        let last = cal.date(byAdding: .day, value: -1, to: d.end)!
        let f = DateFormatter()
        f.timeZone = Fmt.tz
        f.dateFormat = "yyyy/M/d"
        if d.range.hourly { return f.string(from: d.start) + " · " + d.range.title }
        let days = cal.dateComponents([.day], from: d.start, to: d.end).day ?? 0
        f.dateFormat = "yyyy/M/d"
        let g = DateFormatter()
        g.timeZone = Fmt.tz
        g.dateFormat = cal.component(.year, from: d.start) == cal.component(.year, from: last) ? "M/d" : "yyyy/M/d"
        return "\(f.string(from: d.start)) – \(g.string(from: last)) · " + L("\(days) 天", "\(days) days", ja: "\(days) 日", ko: "\(days)일")
    }

    private func sessions(_ d: HistoryData) -> [SessionSummary] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return (store.local?.sessions ?? []).filter { s in
            source.includes(s.source) && s.end >= d.start && s.start < d.end
                && (q.isEmpty || s.title.lowercased().contains(q) || s.project.lowercased().contains(q))
        }
    }

    private func statusBar(_ d: HistoryData) -> some View {
        HStack(spacing: 16) {
            if let t = store.lastUpdated {
                HStack(spacing: 4) {
                    Text(L("\(Fmt.time(t)) 更新", "Updated \(Fmt.time(t))", ja: "\(Fmt.time(t)) 更新", ko: "\(Fmt.time(t)) 업데이트"))
                    if store.isLoading || store.isScanning {
                        ProgressView().controlSize(.mini).frame(width: 18, height: 18)
                    } else {
                        IconButton(symbol: "arrow.clockwise", help: L("刷新", "Refresh", ja: "更新", ko: "새로 고침")) { store.refreshAll() }
                    }
                }
            }
            if d.total.unpricedRequests > 0 {
                Label(L("\(Fmt.count(d.total.unpricedRequests)) 次请求的模型价格未知，没算进费用",
                        "\(Fmt.count(d.total.unpricedRequests)) requests use models with unknown prices and aren't in the cost",
                        ja: "\(Fmt.count(d.total.unpricedRequests)) 件は価格不明のモデルのため費用に含まれていません",
                        ko: "가격을 알 수 없는 모델의 요청 \(Fmt.count(d.total.unpricedRequests))건은 비용에 포함되지 않음"),
                      systemImage: "info.circle")
            }
            Spacer()
            Label(L("只读本机日志，只保存每天的汇总数字，不含对话内容",
                    "Reads local logs only; keeps daily totals, never conversation content",
                    ja: "ローカルのログを読むだけ。日ごとの合計のみ保存し、会話内容は含みません",
                    ko: "로컬 로그만 읽고 일별 합계만 저장하며 대화 내용은 포함하지 않습니다"),
                  systemImage: "lock.shield")
        }
        .font(.system(size: 11.5))
        .foregroundStyle(Theme.text2)
        .lineLimit(1)
        .padding(.horizontal, 18).padding(.vertical, 7)
        .background(.bar)
        .overlay(alignment: .top) { Hairline() }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "quotlet-usage.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = HistoryData.build(range: range, source: source, rows: history.rows, messages: store.local?.messages ?? [], now: Date())
        let startKey = HistoryStore.dayKey(data.start), endKey = HistoryStore.dayKey(data.end)
        func esc(_ s: String) -> String { s.contains(where: { ",\"\n".contains($0) }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s }
        var lines = ["date,source,model,project,input_tokens,output_tokens,cache_read_tokens,cache_write_tokens,requests,avg_speed_tok_s,cost_usd_api_equivalent"]
        for r in history.rows where r.day >= startKey && r.day < endKey && source.includes(r.source) {
            let speed = r.timedSeconds > 0 ? String(format: "%.1f", Double(r.timedOutput) / r.timedSeconds) : ""
            lines.append([r.day, r.source, esc(r.model), esc(r.project), "\(r.input)", "\(r.output)", "\(r.cacheRead)", "\(r.cacheWrite)",
                          "\(r.requests)", speed, String(format: "%.4f", r.cost)].joined(separator: ","))
        }
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: 卡片

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.group))
    }
}

private struct KPIRow: View {
    let data: HistoryData

    var body: some View {
        let t = data.total, p = data.previous
        let peakBucket = data.buckets.max { $0.total.tokens.inputAllCount < $1.total.tokens.inputAllCount }
        HStack(spacing: 12) {
            KPICard(label: L("输出 token", "Output tokens", ja: "出力トークン", ko: "출력 토큰"),
                    value: Fmt.tokens(t.tokens.output), series: data.buckets.map { Double($0.total.tokens.output) },
                    foot: compare(Double(t.tokens.output), Double(p.tokens.output)))
            KPICard(label: L("输入 token（含缓存）", "Input tokens (incl. cache)", ja: "入力トークン（キャッシュ含む）", ko: "입력 토큰(캐시 포함)"),
                    value: Fmt.tokens(t.inputAll), series: data.buckets.map { Double($0.total.inputAll) },
                    foot: peakBucket.flatMap { b in b.total.inputAll > 0 ? (L("最高 ", "Peak ", ja: "最高 ", ko: "최고 ") + label(b.start), nil) : nil } ?? ("—", nil))
            KPICard(label: L("请求", "Requests", ja: "リクエスト", ko: "요청"),
                    value: Fmt.tokens(t.requests), series: data.buckets.map { Double($0.total.requests) },
                    foot: (L("活跃 \(data.activeDays) 天", "Active \(data.activeDays) days", ja: "稼働 \(data.activeDays) 日", ko: "활동 \(data.activeDays)일"), nil))
            KPICard(label: L("平均速度", "Avg speed", ja: "平均速度", ko: "평균 속도"),
                    value: t.avgSpeed.map { Fmt.speed($0) } ?? "—", unit: t.avgSpeed == nil ? nil : "tok/s",
                    series: data.buckets.map { $0.total.avgSpeed ?? 0 },
                    foot: t.peakSpeed > 0 ? (L("峰值 ", "Peak ", ja: "ピーク ", ko: "최고 ") + Fmt.speed(t.peakSpeed) + " tok/s", nil)
                                          : compare(t.avgSpeed ?? 0, p.avgSpeed ?? 0))
            KPICard(label: L("费用（API 等值）", "Cost (API equiv.)", ja: "費用（API 換算）", ko: "비용(API 환산)"),
                    value: (t.unpricedRequests > 0 ? "≥" : "") + Fmt.money(t.cost), series: data.buckets.map { $0.total.cost },
                    foot: (perBucket(t.cost), nil))
        }
    }

    private func label(_ d: Date) -> String {
        data.unit == .hour ? Fmt.time(d) : Fmt.shortDay(d)
    }

    private func perBucket(_ cost: Double) -> String {
        let n = max(1, data.unit == .hour ? 1 : data.buckets.count)
        if data.unit == .hour { return L("今天到现在", "So far", ja: "これまで", ko: "지금까지") }
        let unit = data.unit == .weekOfYear ? L("周均 ", "Weekly avg ", ja: "週平均 ", ko: "주 평균 ") : L("日均 ", "Daily avg ", ja: "日平均 ", ko: "일 평균 ")
        return unit + Fmt.money(cost / Double(n))
    }

    /// 「比上一段时间 +31%」
    private func compare(_ now: Double, _ before: Double) -> (String, String?) {
        let text = L("比上一段时间 ", "vs previous ", ja: "前の期間比 ", ko: "이전 기간 대비 ")
        guard before > 0 else { return (text + "—", nil) }
        let pct = Int(((now - before) / before * 100).rounded())
        return (text, (pct >= 0 ? "+" : "") + "\(pct)%")
    }
}

private extension TokenCount {
    var inputAllCount: Int { input + cacheRead + cacheWrite }
}

private struct KPICard: View {
    let label: String
    let value: String
    var unit: String? = nil
    let series: [Double]
    let foot: (String, String?)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 24, weight: .bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
                if let unit { Text(unit).font(.system(size: 12)).foregroundStyle(Theme.text2) }
            }
            Sparkline(values: series).frame(height: 28)
            HStack(spacing: 0) {
                Text(foot.0)
                if let d = foot.1 { Text(d).fontWeight(.semibold).foregroundStyle(d.hasPrefix("-") ? Theme.critical : Theme.live) }
            }
            .font(.system(size: 11.5)).foregroundStyle(Theme.text2).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.group))
    }
}

private struct Sparkline: View {
    let values: [Double]
    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { i, v in
            AreaMark(x: .value("i", i), y: .value("v", v))
                .foregroundStyle(LinearGradient(colors: [Theme.codex.opacity(0.22), Theme.codex.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("i", i), y: .value("v", v))
                .foregroundStyle(Theme.codex)
                .lineStyle(StrokeStyle(lineWidth: 1.4))
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

/// 每日输出 / 费用的堆叠柱状图（Claude Code + Codex），叠一条平均速度曲线（右侧刻度）
private struct UsageChartCard: View {
    let data: HistoryData
    @Binding var metric: ChartMetric

    private struct Point: Identifiable {
        let id: String
        let start: Date
        let source: String
        let value: Double
    }

    var body: some View {
        let points = data.buckets.flatMap { b -> [Point] in
            [Point(id: "c\(b.start.timeIntervalSince1970)", start: b.start, source: "Claude Code", value: value(b.claude)),
             Point(id: "x\(b.start.timeIntervalSince1970)", start: b.start, source: "Codex", value: value(b.codex))]
        }
        let stacked = data.buckets.map { value($0.claude) + value($0.codex) }
        let yMax = niceMax(stacked.max() ?? 0)
        let speeds = data.buckets.map { $0.total.avgSpeed }
        let speedMax = niceMax((speeds.compactMap { $0 }.max() ?? 0) * 1.1, minimum: 50)
        let speedPoints = zip(data.buckets, speeds).compactMap { b, s in s.map { (b.start, $0) } }

        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    Picker("", selection: $metric) {
                        ForEach(ChartMetric.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    legend("Claude Code", Theme.data)
                    legend("Codex", Theme.codex)
                    Spacer()
                    HStack(spacing: 6) {
                        Rectangle().fill(Color.primary).frame(width: 16, height: 2)
                        Text(L("平均速度 (tok/s)", "Avg speed (tok/s)", ja: "平均速度 (tok/s)", ko: "평균 속도 (tok/s)"))
                    }
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
                Chart {
                    ForEach(points) { p in
                        BarMark(x: .value("t", p.start, unit: data.unit), y: .value("v", p.value), width: .ratio(0.62))
                            .foregroundStyle(by: .value("source", p.source))
                            .cornerRadius(2)
                    }
                    ForEach(speedPoints, id: \.0) { t, s in
                        LineMark(x: .value("t", t, unit: data.unit), y: .value("speed", yMax * s / speedMax), series: .value("s", "speed"))
                            .foregroundStyle(Color.primary.opacity(0.85))
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                            .interpolationMethod(.monotone)
                        if speedPoints.count <= 31 {
                            PointMark(x: .value("t", t, unit: data.unit), y: .value("speed", yMax * s / speedMax))
                                .foregroundStyle(Color.primary.opacity(0.85))
                                .symbolSize(18)
                        }
                    }
                }
                .chartForegroundStyleScale(["Claude Code": Theme.data, "Codex": Theme.codex])
                .chartLegend(.hidden)
                .chartYScale(domain: 0...yMax)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, yMax / 2, yMax]) { v in
                        AxisGridLine().foregroundStyle(Theme.divider)
                        AxisValueLabel {
                            if let d = v.as(Double.self) { Text(axisLabel(d)).font(.system(size: 11)) }
                        }
                    }
                    AxisMarks(position: .trailing, values: [0, yMax / 2, yMax]) { v in
                        AxisValueLabel {
                            if let d = v.as(Double.self) { Text(Fmt.speed(d / yMax * speedMax)).font(.system(size: 11)) }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: data.unit, count: xStride)) { v in
                        AxisValueLabel {
                            if let d = v.as(Date.self) {
                                Text(data.unit == .hour ? "\(Fmt.calendar.component(.hour, from: d)):00" : Fmt.shortDay(d)).font(.system(size: 11))
                            }
                        }
                    }
                }
                .environment(\.timeZone, Fmt.tz)
                .frame(height: 260)
            }
        }
    }

    private var xStride: Int {
        let n = data.buckets.count
        if data.unit == .hour { return 3 }
        if n <= 8 { return 1 }
        if n <= 31 { return 2 }
        if n <= 62 { return 7 }
        return max(1, n / 10)
    }

    private func value(_ s: UsageStats) -> Double {
        metric == .output ? Double(s.tokens.output) : s.cost
    }

    private func axisLabel(_ v: Double) -> String {
        metric == .output ? (v == 0 ? "0" : Fmt.tokens(Int(v))) : (v == 0 ? "0" : String(format: "$%.0f", v))
    }

    private func legend(_ name: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(name).font(.system(size: 12)).foregroundStyle(Theme.text2)
        }
    }
}

/// 坐标轴上限取个整数：1 / 2 / 2.5 / 5 × 10^n
private func niceMax(_ v: Double, minimum: Double = 1) -> Double {
    let x = max(v, minimum)
    let p = pow(10, floor(log10(x)))
    for m in [1, 2, 2.5, 5, 10] where m * p >= x { return m * p }
    return 10 * p
}

/// 每周额度的已用比例走势：Claude 每周、Codex 每周（来自每次刷新记下的读数）
private struct QuotaHistoryCard: View {
    let readings: [HistoryStore.QuotaReading]
    let now: Date

    var body: some View {
        let start = now.addingTimeInterval(-14 * 86400)
        let claude = readings.filter { $0.provider == "claude" && $0.kind == "weekly_all" && $0.ts >= start }
        let codex = readings.filter { $0.provider == "codex" && $0.kind == "weekly_all" && $0.ts >= start }
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    Text(L("额度历史 · 每周额度", "Quota history · weekly", ja: "上限の推移 · 週間", ko: "한도 기록 · 주간")).font(.system(size: 14, weight: .semibold))
                    legend(L("Claude 本周", "Claude weekly", ja: "Claude 週間", ko: "Claude 주간"), Theme.data)
                    if !codex.isEmpty { legend(L("Codex 本周", "Codex weekly", ja: "Codex 週間", ko: "Codex 주간"), Theme.codex) }
                    Spacer()
                    Text(L("近 14 天", "Last 14 days", ja: "直近 14 日", ko: "최근 14일")).font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
                if claude.count + codex.count < 2 {
                    Text(L("从现在开始记录：每次刷新记一笔额度读数，过几天就能看到走势。",
                           "Recording starts now: each refresh saves a reading, so the trend fills in over the next few days.",
                           ja: "今から記録を始めます。更新のたびに読み取り値を保存し、数日で推移が見えるようになります。",
                           ko: "지금부터 기록합니다. 새로 고칠 때마다 값을 저장하므로 며칠 뒤 추이를 볼 수 있습니다."))
                        .font(.system(size: 12)).foregroundStyle(Theme.text2)
                        .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
                } else {
                    Chart {
                        RuleMark(y: .value("limit", 100))
                            .foregroundStyle(Theme.critical.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        ForEach(claude, id: \.ts) { r in
                            LineMark(x: .value("t", r.ts), y: .value("p", r.percent), series: .value("s", "claude"))
                                .foregroundStyle(Theme.data)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                        ForEach(codex, id: \.ts) { r in
                            LineMark(x: .value("t", r.ts), y: .value("p", r.percent), series: .value("s", "codex"))
                                .foregroundStyle(Theme.codex)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                    .chartXScale(domain: start...now)
                    .chartYScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: [0, 50, 100]) { v in
                            AxisGridLine().foregroundStyle(Theme.divider)
                            AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d))%").font(.system(size: 11)) } }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 2)) { v in
                            AxisValueLabel { if let d = v.as(Date.self) { Text(Fmt.shortDay(d)).font(.system(size: 11)) } }
                        }
                    }
                    .environment(\.timeZone, Fmt.tz)
                    .frame(height: 170)
                }
            }
        }
    }

    private func legend(_ name: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(color).frame(width: 14, height: 2)
            Text(name).font(.system(size: 12)).foregroundStyle(Theme.text2)
        }
    }
}

private struct ProjectTrendCard: View {
    let data: HistoryData
    let now: Date
    @State private var hiddenProjects: Set<String> = []
    @State private var outputOnly = false
    @State private var cursor: Date? = Snapshot.projectCursor

    private struct Series: Identifiable {
        let id: String
        let color: Color
        let dash: [CGFloat]
        let points: [Date: Int]
        var total: Int { points.values.reduce(0, +) }
    }

    var body: some View {
        let series = data.projects.enumerated().map { index, project in
            let colors: [Color] = [Theme.data, Theme.codex, Theme.live, .purple, .pink, .teal, .indigo, .brown]
            let dashes: [[CGFloat]] = [[], [5, 3], [2, 3], [6, 3, 2, 3]]
            return Series(id: project.name, color: colors[index % colors.count],
                          dash: dashes[(index / colors.count) % dashes.count],
                          points: data.projectUsage[project.name, default: [:]].mapValues { bucket in
                              bucket.values.reduce(0) { $0 + (outputOnly ? $1.output : $1.total) }
                          })
        }
        let visible = series.filter { !hiddenProjects.contains($0.id) }
        let dates = data.buckets.map(\.start).filter { $0 <= now }
        let picked = cursor.flatMap { target -> Date? in
            return dates.min { abs($0.timeIntervalSince(target)) < abs($1.timeIntervalSince(target)) }
        }

        return Card {
            if !series.isEmpty {
                HStack(alignment: .top, spacing: 20) {
                    trend(visible, dates: dates, picked: picked)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    projectPicker(series, picked: picked)
                        .frame(width: 245, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    title
                    Text(L("这段时间没有项目用量", "No project usage in this period", ja: "この期間のプロジェクト使用量はありません", ko: "이 기간에는 프로젝트 사용량이 없습니다"))
                        .font(Theme.caption).foregroundStyle(Theme.text2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: data.start) { cursor = nil }
        .onChange(of: data.end) { cursor = nil }
    }

    private var title: some View {
        Text(L("项目用量趋势", "Project usage trend", ja: "プロジェクト使用量の推移", ko: "프로젝트 사용량 추이"))
            .font(.system(size: 14, weight: .semibold))
    }

    private func projectPicker(_ series: [Series], picked: Date?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("按项目", "By project", ja: "プロジェクト別", ko: "프로젝트별"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(L("全选", "Select all", ja: "すべて選択", ko: "모두 선택")) { hiddenProjects.removeAll() }
                    .disabled(!series.contains { hiddenProjects.contains($0.id) })
                Button(L("清空", "Clear", ja: "選択解除", ko: "선택 해제")) { hiddenProjects.formUnion(series.map(\.id)) }
                    .disabled(series.allSatisfy { hiddenProjects.contains($0.id) })
            }
            .buttonStyle(.borderless)
            .font(Theme.caption)
            Text(picked.map(dateLabel) ?? L("所选时间内用量", "Usage in this period", ja: "選択期間の使用量", ko: "선택 기간의 사용량"))
                .font(Theme.caption).foregroundStyle(Theme.text2)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(series) { item in
                        let selected = !hiddenProjects.contains(item.id)
                        let value = picked.map { item.points[$0, default: 0] } ?? item.total
                        Button {
                            if selected { hiddenProjects.insert(item.id) }
                            else { hiddenProjects.remove(item.id) }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: selected ? "checkmark.square.fill" : "square").foregroundStyle(selected ? item.color : Theme.text2)
                                Text(projectName(item.id)).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 4)
                                Text(Fmt.tokens(value)).monospacedDigit().fixedSize()
                            }
                            .font(Theme.caption)
                            .foregroundStyle(selected ? Color.primary : Theme.text2)
                            .padding(5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .help(projectName(item.id))
                    }
                }
            }
            .frame(height: 185)
        }
    }

    private func trend(_ series: [Series], dates: [Date], picked: Date?) -> some View {
        let labelStep = max(1, (dates.count + 6) / 7)
        let axisDates = dates.enumerated().filter {
            $0.offset.isMultiple(of: labelStep) || $0.offset == dates.count - 1
        }.map(\.element)
        let maximum = series.compactMap { $0.points.values.max() }.max() ?? 0
        let limit = Int(niceMax(Double(maximum), minimum: 2))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                title
                Spacer()
                Picker(L("用量口径", "Token metric", ja: "トークン指標", ko: "토큰 지표"), selection: $outputOnly) {
                    Text(L("总 token", "Total tokens", ja: "合計トークン", ko: "총 토큰")).tag(false)
                    Text(L("输出", "Output", ja: "出力", ko: "출력")).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Text(L("已选 \(series.count) 个项目", "\(series.count) projects selected", ja: "\(series.count) 件を選択中", ko: "프로젝트 \(series.count)개 선택"))
                .font(Theme.caption).foregroundStyle(Theme.text2)
            Chart {
                ForEach(series) { item in
                    ForEach(dates, id: \.self) { date in
                        let count = item.points[date, default: 0]
                        LineMark(x: .value("Date", date), y: .value("Tokens", count), series: .value("Project", item.id))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: item.dash))
                            .foregroundStyle(item.color)
                        if picked == date || dates.count == 1 {
                            PointMark(x: .value("Date", date), y: .value("Tokens", count))
                                .foregroundStyle(item.color)
                        }
                    }
                }
                if let picked, !series.isEmpty {
                    RuleMark(x: .value("Date", picked))
                        .foregroundStyle(Theme.marker.opacity(0.5))
                        .annotation(position: .top, alignment: .leading, spacing: 8,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            hoverDetails(series, at: picked)
                        }
                }
            }
            .chartLegend(.hidden)
            .chartXSelection(value: $cursor)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Color.clear.contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                if let anchor = proxy.plotFrame {
                                    let plot = geometry[anchor]
                                    cursor = plot.contains(location) ? proxy.value(atX: location.x - plot.minX, as: Date.self) : nil
                                } else { cursor = nil }
                            case .ended: cursor = nil
                            }
                        }
                }
            }
            .chartXScale(range: .plotDimension(startPadding: 18, endPadding: 22))
            .chartYScale(domain: 0...limit)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, limit / 2, limit]) { tick in
                    AxisGridLine().foregroundStyle(Theme.divider)
                    AxisValueLabel { if let count = tick.as(Int.self) { Text(Fmt.tokens(count)) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: axisDates) { tick in
                    AxisValueLabel { if let date = tick.as(Date.self) { Text(dateLabel(date)) } }
                }
            }
            .environment(\.timeZone, Fmt.tz)
            .frame(height: 185)
            .overlay {
                if series.isEmpty {
                    Text(L("选择项目后显示趋势", "Select projects to show trends", ja: "プロジェクトを選択すると推移を表示します", ko: "프로젝트를 선택하면 추이가 표시됩니다"))
                        .font(Theme.caption).foregroundStyle(Theme.text2)
                }
            }
        }
    }

    private func hoverDetails(_ series: [Series], at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dateLabel(date)).fontWeight(.semibold)
            ForEach(series) { item in
                HStack(spacing: 7) {
                    Circle().fill(item.color).frame(width: 7, height: 7)
                    Text(projectName(item.id)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 12)
                    Text(Fmt.tokens(item.points[date, default: 0])).monospacedDigit()
                }
            }
        }
        .font(Theme.caption)
        .foregroundStyle(Color.primary)
        .padding(10)
        .frame(width: 220)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.divider))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .allowsHitTesting(false)
    }

    private func dateLabel(_ date: Date) -> String { data.unit == .hour ? Fmt.time(date) : Fmt.shortDay(date) }
    private func projectName(_ name: String) -> String {
        name.isEmpty ? L("未知项目", "Unknown project", ja: "不明なプロジェクト", ko: "알 수 없는 프로젝트") : name
    }
}

private struct BreakdownCard: View {
    let data: HistoryData

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("按模型 · 输出和速度", "By model · output & speed", ja: "モデル別 · 出力と速度", ko: "모델별 · 출력과 속도")).font(.system(size: 14, weight: .semibold))
                    if data.models.isEmpty { empty }
                    let top = data.models.first?.output ?? 1
                    ForEach(data.models, id: \.name) { m in
                        BarRow(name: m.name, value: Fmt.tokens(m.output) + (m.speed.map { " · \(Fmt.speed($0)) tok/s" } ?? ""),
                               fraction: Double(m.output) / Double(max(1, top)),
                               color: m.source == Source.codex.rawValue ? Theme.codex : Theme.data, valueWidth: 120)
                    }
                }
            }
        }
    }

    private var empty: some View {
        Text(L("这段时间没有用量", "No usage in this period", ja: "この期間の使用はありません", ko: "이 기간에는 사용량이 없습니다"))
            .font(.system(size: 12)).foregroundStyle(Theme.text2)
    }
}

private struct BarRow: View {
    let name: String
    let value: String
    let fraction: Double
    let color: Color
    var valueWidth: CGFloat = 64

    var body: some View {
        HStack(spacing: 10) {
            Text(name).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle).frame(width: 96, alignment: .leading)
            UsageBar(fraction: fraction, marker: nil, color: color, height: 4)
            Text(value).font(.system(size: 12).monospacedDigit()).lineLimit(1).frame(width: valueWidth, alignment: .trailing)
        }
    }
}

/// 会话表共享列宽：标题、项目和用量进度条按比例分配剩余空间。
private struct SessionColumns {
    let width: CGFloat
    static let spacing: CGFloat = 10
    static let rowHeight: CGFloat = 32
    let status: CGFloat = 62
    let source: CGFloat = 86
    let model: CGFloat = 100
    let start: CGFloat = 54
    let duration: CGFloat = 64
    let input: CGFloat = 60
    let output: CGFloat = 60
    let cache: CGFloat = 68
    let total: CGFloat = 74

    init(availableWidth: CGFloat) { width = max(1180, availableWidth) }
    private var flexible: CGFloat {
        width - status - source - model - start - duration - input - output - cache - total - Self.spacing * 11 - 12
    }
    var title: CGFloat { flexible * 0.42 }
    var project: CGFloat { flexible * 0.23 }
    var progress: CGFloat { flexible * 0.35 }
}

private struct SessionsCard: View {
    let sessions: [SessionSummary]
    let now: Date
    @Binding var search: String
    @State private var availableWidth: CGFloat = 1180

    var body: some View {
        let shown = Array(sessions.prefix(200))
        let top = sessions.map { $0.tokens.total }.max() ?? 1
        let columns = SessionColumns(availableWidth: availableWidth)
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(L("会话", "Sessions", ja: "セッション", ko: "세션")).font(.system(size: 14, weight: .semibold))
                    let active = sessions.filter { $0.isActive(now: now) }.count
                    Text(L("\(sessions.count) 个 · \(active) 个进行中", "\(sessions.count) · \(active) active", ja: "\(sessions.count) 件 · 実行中 \(active)", ko: "\(sessions.count)개 · 진행 중 \(active)"))
                        .font(.system(size: 12)).foregroundStyle(Theme.text2)
                    Spacer()
                    TextField(L("搜索标题或项目", "Search title or project", ja: "タイトルやプロジェクトを検索", ko: "제목 또는 프로젝트 검색"), text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
                if shown.isEmpty {
                    Text(L("这段时间没有会话（会话列表只看最近 31 天的本机日志）", "No sessions in this period (the list covers the last 31 days of local logs)",
                           ja: "この期間のセッションはありません（直近 31 日のローカルログが対象）", ko: "이 기간에 세션이 없습니다(최근 31일 로컬 로그 기준)"))
                        .font(.system(size: 12)).foregroundStyle(Theme.text2)
                        .padding(.vertical, 12)
                } else {
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 8) {
                            header(columns)
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(shown) { s in
                                    SessionTableRow(session: s, now: now, top: top, columns: columns)
                                }
                            }
                        }
                        .frame(width: columns.width, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: true)
                    }
                    .frame(height: 32 + CGFloat(shown.count) * SessionColumns.rowHeight)
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { availableWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, width in availableWidth = width }
                }
            }
        }
    }

    private func header(_ c: SessionColumns) -> some View {
        HStack(spacing: SessionColumns.spacing) {
            Text(L("状态", "Status", ja: "状態", ko: "상태")).frame(width: c.status, alignment: .leading)
            Text(L("会话", "Session", ja: "セッション", ko: "세션")).frame(width: c.title, alignment: .leading)
            Text(L("项目", "Project", ja: "プロジェクト", ko: "프로젝트")).frame(width: c.project, alignment: .leading)
            Text(L("来源", "Source", ja: "ソース", ko: "소스")).frame(width: c.source, alignment: .leading)
            Text(L("模型", "Model", ja: "モデル", ko: "모델")).frame(width: c.model, alignment: .leading)
            Text(L("开始", "Started", ja: "開始", ko: "시작")).frame(width: c.start, alignment: .leading)
            Text(L("时长", "Duration", ja: "時間", ko: "시간")).frame(width: c.duration, alignment: .leading)
            Text(L("用量对比", "Usage comparison", ja: "使用量の比較", ko: "사용량 비교")).frame(width: c.progress, alignment: .leading)
            Text(L("输入", "Input", ja: "入力", ko: "입력")).frame(width: c.input, alignment: .trailing)
                .help(L("输入 token，不含缓存", "Input tokens, excluding cache", ja: "キャッシュを除く入力トークン", ko: "캐시를 제외한 입력 토큰"))
            Text(L("输出", "Output", ja: "出力", ko: "출력")).frame(width: c.output, alignment: .trailing)
            Text(L("缓存", "Cache", ja: "キャッシュ", ko: "캐시")).frame(width: c.cache, alignment: .trailing)
                .help(L("缓存读取 + 缓存写入 token", "Cache read + cache write tokens", ja: "キャッシュ読み取り + 書き込みトークン", ko: "캐시 읽기 + 쓰기 토큰"))
            Text(L("总 token", "Total tokens", ja: "合計トークン", ko: "총 토큰")).frame(width: c.total, alignment: .trailing)
        }
        .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
        .lineLimit(1)
        .padding(.horizontal, 6)
        .frame(width: c.width, height: 24, alignment: .leading)
    }
}

private struct SessionTableRow: View {
    let session: SessionSummary
    let now: Date
    let top: Int
    let columns: SessionColumns
    @State private var hovering = false

    var body: some View {
        let s = session
        let c = columns
        let active = s.isActive(now: now)
        HStack(spacing: SessionColumns.spacing) {
            HStack(spacing: 5) {
                Circle().fill(active ? Theme.live : Theme.inkSoft).frame(width: 7, height: 7)
                Text(active ? L("进行中", "Active", ja: "実行中", ko: "진행 중") : L("已结束", "Ended", ja: "終了", ko: "종료"))
                    .foregroundStyle(active ? Theme.live : Theme.text2)
            }
            .font(.system(size: 12, weight: .medium))
            .frame(width: c.status, alignment: .leading)
            Text(s.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                .frame(width: c.title, alignment: .leading).help(s.title)
            Text(s.project).lineLimit(1).truncationMode(.middle)
                .frame(width: c.project, alignment: .leading).help(s.project)
            HStack(spacing: 5) {
                Circle().fill(s.source == .codex ? Theme.codex : Theme.data).frame(width: 7, height: 7)
                Text(s.source.title).lineLimit(1)
            }
            .frame(width: c.source, alignment: .leading)
            Text(Fmt.modelName(s.mainModel)).lineLimit(1).frame(width: c.model, alignment: .leading).help(Fmt.modelName(s.mainModel))
            Text(Fmt.sessionTime(s.start, now: now)).lineLimit(1).frame(width: c.start, alignment: .leading)
            Text(Fmt.compactDuration(s.end.timeIntervalSince(s.start))).lineLimit(1).frame(width: c.duration, alignment: .leading)
            UsageBar(fraction: Double(s.tokens.total) / Double(max(1, top)), marker: nil,
                     color: s.source == .codex ? Theme.codex : Theme.data, height: 4)
                .frame(width: c.progress)
                .help(L("相对当前列表中最大会话的总 token 用量", "Total tokens relative to the largest session in this list", ja: "この一覧の最大セッションに対する合計トークン", ko: "현재 목록의 최대 세션 대비 총 토큰 사용량"))
            tokenCell(s.tokens.input, width: c.input)
            tokenCell(s.tokens.output, width: c.output)
            tokenCell(s.tokens.cacheRead + s.tokens.cacheWrite, width: c.cache)
                .help(L("读取 \(Fmt.count(s.tokens.cacheRead)) · 写入 \(Fmt.count(s.tokens.cacheWrite))", "Read \(Fmt.count(s.tokens.cacheRead)) · write \(Fmt.count(s.tokens.cacheWrite))",
                        ja: "読み取り \(Fmt.count(s.tokens.cacheRead)) · 書き込み \(Fmt.count(s.tokens.cacheWrite))", ko: "읽기 \(Fmt.count(s.tokens.cacheRead)) · 쓰기 \(Fmt.count(s.tokens.cacheWrite))"))
            tokenCell(s.tokens.total, width: c.total)
                .fontWeight(.medium)
        }
        .font(.system(size: 12).monospacedDigit())
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 6)
        .frame(width: c.width, height: SessionColumns.rowHeight, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Theme.hover : .clear))
        .overlay(alignment: .top) { Hairline() }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .sessionActions(s)
    }

    private func tokenCell(_ count: Int, width: CGFloat) -> some View {
        Text(Fmt.tokens(count)).lineLimit(1)
            .frame(width: width, alignment: .trailing)
            .help(Fmt.count(count))
    }
}

extension View {
    func sessionActions(_ s: SessionSummary) -> some View {
        contextMenu {
            Button(L("复制恢复命令", "Copy resume command", ja: "再開コマンドをコピー", ko: "재개 명령 복사")) { copy(resumeCommand(s)) }
            Button(L("复制会话 ID", "Copy session ID", ja: "セッション ID をコピー", ko: "세션 ID 복사")) { copy(rawID(s)) }
            if let cwd = s.cwd {
                Button(L("在访达中打开项目目录", "Open project folder in Finder", ja: "プロジェクトフォルダを Finder で開く", ko: "Finder에서 프로젝트 폴더 열기")) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
                }
            }
        }
    }

    private func rawID(_ s: SessionSummary) -> String {
        s.source == .codex && s.id.hasPrefix("codex-") ? String(s.id.dropFirst(6)) : s.id
    }

    private func resumeCommand(_ s: SessionSummary) -> String {
        let cmd = s.source == .codex ? "codex resume \(rawID(s))" : "claude --resume \(rawID(s))"
        return s.cwd.map { "cd '" + $0.replacingOccurrences(of: "'", with: "'\\''") + "' && " + cmd } ?? cmd
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
