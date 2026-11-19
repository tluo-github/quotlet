import AppKit
import Charts
import SwiftUI

struct SessionsTab: View {
    @EnvironmentObject var store: Store
    let now: Date
    @AppStorage("sessionRange") private var range: Range = .day

    enum Range: String, CaseIterable {
        case day, week, month

        var title: String {
            switch self {
            case .day: return L("24 小时", "24 hours", ja: "24 時間", ko: "24시간")
            case .week: return L("7 天", "7 days", ja: "7 日", ko: "7일")
            case .month: return L("30 天", "30 days", ja: "30 日", ko: "30일")
            }
        }
        var seconds: TimeInterval {
            switch self {
            case .day: return 86400
            case .week: return 7 * 86400
            case .month: return 30 * 86400
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChipPicker(options: Range.allCases.map { ($0, $0.title) }, selection: $range)

            if let l = store.local {
                let list = l.sessions(since: now.addingTimeInterval(-range.seconds))
                let total = list.reduce(0) { $0 + $1.tokens.total }
                let active = list.filter { $0.isActive(now: now) }.count
                let maxTokens = list.map(\.tokens.total).max() ?? 1
                let mainModel = Dictionary(grouping: list, by: \.mainModel).max { $0.value.count < $1.value.count }?.key

                Text(summary(count: list.count, tokens: total, active: active))
                    .font(Theme.caption)

                if list.isEmpty {
                    LoadingState(text: L("这段时间没有本机会话", "No local sessions in this period", ja: "この期間のローカルセッションはありません", ko: "이 기간에는 로컬 세션이 없습니다"), spinner: false)
                }

                ForEach(groupByDay(list), id: \.day) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(Fmt.dayLabel(group.day, now: now)).font(Theme.label)
                            Spacer()
                            Text(Fmt.tokens(group.items.reduce(0) { $0 + $1.tokens.total }))
                                .font(Theme.caption).monospacedDigit()
                        }
                        .padding(.horizontal, 6).padding(.bottom, 2)
                        ForEach(group.items) {
                            SessionRow(session: $0, now: now, maxTokens: maxTokens, mainModel: mainModel)
                        }
                    }
                    .padding(.horizontal, -6)
                }

                if !list.isEmpty {
                    Text(L("右键会话可以复制恢复命令", "Right-click a session to copy its resume command", ja: "セッションを右クリックすると再開コマンドをコピーできます", ko: "세션을 오른쪽 클릭하면 재개 명령을 복사할 수 있습니다")).font(Theme.caption)
                }
            } else {
                LoadingState(text: L("正在读取本机会话日志…", "Reading local session logs…", ja: "ローカルのセッションログを読み込み中…", ko: "로컬 세션 로그를 읽는 중…"))
            }
        }
        .foregroundStyle(Theme.text)
    }

    private func summary(count: Int, tokens: Int, active: Int) -> String {
        var t = L("\(count) 个会话 · \(Fmt.tokens(tokens)) token", "\(count) sessions · \(Fmt.tokens(tokens)) tokens",
                  ja: "\(count) セッション · \(Fmt.tokens(tokens)) トークン", ko: "세션 \(count)개 · 토큰 \(Fmt.tokens(tokens))")
        if active > 0 { t += L(" · \(active) 个进行中", " · \(active) active", ja: " · 進行中 \(active)", ko: " · 진행 중 \(active)") }
        return t
    }

    private func groupByDay(_ list: [SessionSummary]) -> [(day: Date, items: [SessionSummary])] {
        var order: [Date] = []
        var map: [Date: [SessionSummary]] = [:]
        for s in list {
            let d = Fmt.calendar.startOfDay(for: s.end)
            if map[d] == nil { order.append(d) }
            map[d, default: []].append(s)
        }
        return order.map { ($0, map[$0]!) }
    }
}

private struct SessionRow: View {
    let session: SessionSummary
    let now: Date
    var maxTokens: Int = 1
    var mainModel: String? = nil
    @State private var hovering = false

    var body: some View {
        let s = session
        let active = s.isActive(now: now)
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    if active {
                        Circle().fill(Theme.live).frame(width: 6, height: 6)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 0.5 }
                            .padding(.trailing, 6)
                    }
                    Text(s.title).font(Theme.bodyMedium).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Fmt.tokens(s.tokens.total)).font(Theme.number)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(meta).font(Theme.caption).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Fmt.compactDuration(s.end.timeIntervalSince(s.start)))
                        .font(Theme.caption).monospacedDigit()
                }
                UsageBar(fraction: Double(s.tokens.total) / Double(max(1, maxTokens)), marker: nil,
                         color: s.source == .codex ? Theme.codex : Theme.data, height: 2)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? Theme.hover : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(Self.tokenDetail(s))
        .sessionActions(s)
    }

    private var meta: String {
        let s = session
        var parts = [s.source.title, s.project, "\(Fmt.sessionTime(s.start, now: s.end))–\(Fmt.time(s.end))"]
        if let mainModel, s.mainModel != mainModel { parts.append(Fmt.modelName(s.mainModel)) }
        return parts.joined(separator: " · ")
    }

    static func tokenDetail(_ s: SessionSummary) -> String {
        var text = Fmt.modelName(s.mainModel) + " · " + tokenBreakdown(s.tokens)
        if s.subagentTokens > 0 { text += "\n" + L("其中子代理 ", "Subagents: ", ja: "うちサブエージェント ", ko: "하위 에이전트: ") + Fmt.tokens(s.subagentTokens) }
        return text
    }

}

struct StatsTab: View {
    @EnvironmentObject var store: Store
    let now: Date
    @AppStorage("statsDays") private var days: Int = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ChipPicker(options: [(1, L("今天", "Today", ja: "今日", ko: "오늘")), (7, L("7 天", "7 days", ja: "7 日", ko: "7일")), (30, L("30 天", "30 days", ja: "30 日", ko: "30일"))], selection: $days)

            if let l = store.local {
                if days == 1 { TodayBlock(local: l, now: now) }
                else { content(l) }
            } else {
                LoadingState(text: L("正在读取本机会话日志…", "Reading local session logs…", ja: "ローカルのセッションログを読み込み中…", ko: "로컬 세션 로그를 읽는 중…"))
            }
        }
        .foregroundStyle(Theme.text)
    }

    @ViewBuilder
    private func content(_ l: LocalSnapshot) -> some View {
        let cal = Fmt.calendar
        let since = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: now))!
        let sessions = l.sessions(since: since)
        let daily = l.daily(days: days, now: now)
        let models = l.models(since: since).filter { $0.tokens.total > 0 }
        let projects = Array(l.projects(since: since).filter { $0.tokens > 0 }.prefix(5))
        let total = models.reduce(0) { $0 + $1.tokens.total }
        let activeDays = daily.filter { $0.tokens.total > 0 }.count
        let longest = sessions.map { $0.end.timeIntervalSince($0.start) }.max() ?? 0
        let notableModels = models.filter { total > 0 && Double($0.tokens.total) / Double(total) >= 0.01 }

        VStack(alignment: .leading, spacing: 3) {
            Text(L("总 token", "Total tokens", ja: "合計トークン", ko: "총 토큰")).font(Theme.label)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Fmt.tokens(total)).font(Theme.hero)
                Text("token").font(Theme.caption)
            }
            Text(statsLine(sessions: sessions.count, activeDays: activeDays, longest: longest,
                           model: notableModels.count == 1 ? notableModels.first.map { Fmt.modelName($0.model) } : nil))
                .font(Theme.caption)
        }

        DailyChart(daily: daily, now: now)

        if !projects.isEmpty {
            SectionBlock(title: L("按项目", "By project", ja: "プロジェクト別", ko: "프로젝트별")) {
                let top = projects.first?.tokens ?? 1
                ForEach(projects) { p in
                    ShareRow(name: p.project, value: Fmt.tokens(p.tokens), fraction: Double(p.tokens) / Double(max(1, top)))
                }
            }
        }

        if notableModels.count > 1 {
            SectionBlock(title: L("按模型", "By model", ja: "モデル別", ko: "모델별")) {
                ForEach(notableModels) { m in
                    let pct = Double(m.tokens.total) / Double(max(1, total)) * 100
                    ShareRow(name: Fmt.modelName(m.model), value: String(format: "%.0f%%", pct), fraction: pct / 100)
                }
            }
        }

        Text(L("来自本机日志，同一条回复只算一次。", "From local logs; each reply is counted once.", ja: "ローカルログから集計。同じ返信は 1 回だけ数えます。", ko: "로컬 로그 기준이며 같은 응답은 한 번만 셉니다."))
            .font(Theme.caption)
    }

    private func statsLine(sessions: Int, activeDays: Int, longest: TimeInterval, model: String?) -> String {
        var parts = [
            L("\(sessions) 个会话", "\(sessions) sessions", ja: "\(sessions) セッション", ko: "세션 \(sessions)개"),
            L("活跃 \(activeDays)/\(days) 天", "active \(activeDays)/\(days) days", ja: "稼働 \(activeDays)/\(days) 日", ko: "활동 \(activeDays)/\(days)일"),
        ]
        if longest > 0 { parts.append(L("最长 ", "longest ", ja: "最長 ", ko: "최장 ") + Fmt.compactDuration(longest)) }
        if let model { parts.append(model) }
        return parts.map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }.joined(separator: " · ")
    }
}

private struct ShareRow: View {
    let name: String
    let value: String
    let fraction: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(name).font(Theme.body).lineLimit(1).frame(width: 96, alignment: .leading)
            UsageBar(fraction: fraction, marker: nil, color: Theme.data, height: 4)
            Text(value).font(Theme.number).frame(width: 56, alignment: .trailing)
        }
    }
}

private struct DailyChart: View {
    let daily: [(day: Date, tokens: TokenCount)]
    let now: Date
    @State private var selected: Date?

    var body: some View {
        let cal = Fmt.calendar
        let picked = selected.flatMap { s in daily.first { cal.isDate($0.day, inSameDayAs: s) } }
        let focus = picked ?? daily.last

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(L("每天 token", "Tokens per day", ja: "1 日あたりのトークン", ko: "일별 토큰")).font(Theme.label)
                Spacer()
                Text(focus.map { Fmt.dayLabel($0.day, now: now) } ?? "")
                    .font(Theme.caption)
                Text(focus.map { Fmt.tokens($0.tokens.total) } ?? "—").font(Theme.number)
            }

            Chart(daily, id: \.day) { d in
                BarMark(x: .value("day", d.day, unit: .day),
                        y: .value("token", d.tokens.total),
                        width: .ratio(0.6))
                    .cornerRadius(2)
                    .foregroundStyle(focus.map { cal.isDate($0.day, inSameDayAs: d.day) } == true
                                     ? Theme.dataStrong : Theme.data)
            }
            .chartXSelection(value: $selected)
            .chartYAxis {
                AxisMarks(values: [0]) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.divider)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: daily.count <= 7 ? 1 : 5)) { v in
                    AxisValueLabel {
                        if let d = v.as(Date.self) {
                            Text(Fmt.shortDay(d)).font(.system(size: 11)).foregroundStyle(Theme.text)
                        }
                    }
                }
            }
            .environment(\.timeZone, Fmt.tz)
            .frame(height: 110)
        }
    }
}
