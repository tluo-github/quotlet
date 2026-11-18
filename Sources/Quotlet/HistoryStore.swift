import Foundation

/// 用量历史存在本机：~/Library/Application Support/Quotlet/
/// - daily-v1.json：每天按 来源 × 模型 × 项目 汇总的数字（Claude Code 默认只留 30 天日志，存下来才能看更久的历史）
/// - quota-v1.json：额度读数（每次刷新记一笔，变了才记），画额度历史，保留 120 天
/// 只有数字，不含任何对话内容。
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    struct DayRow: Codable, Hashable {
        var day: String          // yyyy-MM-dd（按 Fmt.calendar 的时区）
        var source: String
        var model: String
        var project: String
        var input = 0
        var output = 0
        var cacheRead = 0
        var cacheWrite = 0
        var requests = 0
        var timedOutput = 0
        var timedSeconds = 0.0
        var cost = 0.0
        var unpriced = 0

        var key: String { "\(day)|\(source)|\(model)|\(project)" }
        var total: Int { input + output + cacheRead + cacheWrite }
        var tokens: TokenCount { TokenCount(input: input, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite) }
    }

    struct QuotaReading: Codable {
        let ts: Date
        let provider: String     // claude / codex
        let kind: String         // session / weekly_all / weekly_scoped:<名字>
        let percent: Double
    }

    @Published private(set) var rows: [DayRow] = []
    @Published private(set) var quota: [QuotaReading] = []

    private let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Quotlet", isDirectory: true)
    }()
    private var dailyURL: URL { dir.appendingPathComponent("daily-v1.json") }
    private var quotaURL: URL { dir.appendingPathComponent("quota-v1.json") }
    /// 截图 / 演示模式不写盘（演示模式的项目名是假的，不能混进真实历史）
    private var readOnly: Bool { Snapshot.directory != nil || Demo.enabled }

    private init() {
        if Snapshot.directory != nil || Demo.enabled { return }   // 截图 / 演示不读真实历史
        if let d = try? Data(contentsOf: dailyURL), let r = try? JSONDecoder().decode([DayRow].self, from: d) { rows = r }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        if let d = try? Data(contentsOf: quotaURL), let q = try? dec.decode([QuotaReading].self, from: d) { quota = q }
    }

    nonisolated static func dayKey(_ d: Date) -> String {
        let c = Fmt.calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    nonisolated static func date(ofDay key: String) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Fmt.calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    /// 本地日志扫描完以后调用：把日志里还在的这些天重新汇总，合并进存档。
    /// 日志被工具清理掉一部分的那天，重新算出来会变少，这时保留存档里原来的数字。
    func merge(_ snap: LocalSnapshot, scannedDays: Int) {
        // 扫描窗口最早那天的日志可能不完整，跳过
        let firstFullDay = Fmt.calendar.startOfDay(for: Date().addingTimeInterval(-Double(scannedDays - 1) * 86400))
        var fresh: [String: DayRow] = [:]
        for m in snap.messages where m.ts >= firstFullDay {
            let day = Self.dayKey(m.ts)
            var r = fresh["\(day)|\(m.source.rawValue)|\(m.model)|\(m.project)"]
                ?? DayRow(day: day, source: m.source.rawValue, model: m.model, project: m.project)
            r.input += m.tokens.input
            r.output += m.tokens.output
            r.cacheRead += m.tokens.cacheRead
            r.cacheWrite += m.tokens.cacheWrite
            r.requests += 1
            if let (out, d) = m.timed { r.timedOutput += out; r.timedSeconds += d }
            if let c = Pricing.cost(model: m.model, tokens: m.tokens) { r.cost += c } else { r.unpriced += 1 }
            fresh[r.key] = r
        }
        // 按天比较：某天重新算出来的总量不少于存档，就用新的（同一天的所有行一起换）
        var freshByDay: [String: [DayRow]] = [:]
        for r in fresh.values { freshByDay[r.day, default: []].append(r) }
        var storedByDay: [String: [DayRow]] = [:]
        for r in rows { storedByDay[r.day, default: []].append(r) }
        var changed = false
        for (day, newRows) in freshByDay {
            let newTotal = newRows.reduce(0) { $0 + $1.total }
            let oldRows = storedByDay[day] ?? []
            let oldTotal = oldRows.reduce(0) { $0 + $1.total }
            if newTotal >= oldTotal, Set(newRows) != Set(oldRows) {
                storedByDay[day] = newRows
                changed = true
            }
        }
        guard changed else { return }
        rows = storedByDay.values.flatMap { $0 }.sorted { $0.day < $1.day }
        save(rows, to: dailyURL, dates: false)
    }

    /// 记一笔额度读数（和同一条额度的上一笔一样、且不到 30 分钟就不记）
    func record(provider: String, items: [LimitItem], at ts: Date = Date()) {
        guard !items.isEmpty else { return }
        var changed = false
        for it in items {
            let kind = it.kind == "weekly_scoped" ? "weekly_scoped:\(it.scope ?? "")" : it.kind
            let last = quota.last { $0.provider == provider && $0.kind == kind }
            if let last, abs(last.percent - it.percent) < 0.5, ts.timeIntervalSince(last.ts) < 1800 { continue }
            quota.append(QuotaReading(ts: ts, provider: provider, kind: kind, percent: it.percent))
            changed = true
        }
        guard changed else { return }
        let cutoff = ts.addingTimeInterval(-120 * 86400)
        quota.removeAll { $0.ts < cutoff }
        save(quota, to: quotaURL, dates: true)
    }

    private func save<T: Encodable>(_ value: T, to url: URL, dates: Bool) {
        guard !readOnly else { return }   // 截图 / 演示：只在内存里汇总，不写盘
        let enc = JSONEncoder()
        if dates { enc.dateEncodingStrategy = .secondsSince1970 }
        guard let data = try? enc.encode(value) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
