import Combine
import Foundation

// 登录后把额度、会话、每日 token 上报到 Quotlet Cloud（docs/cloud-design.md 第 5 节）。
//
// - 只发有变化的：记住每样东西上次成功发出去的“签名”，签名没变就不发
// - 发失败不更新签名，下一轮（Store 每分钟扫描一次）自动重试
// - 什么都没变时每 2 分钟发一次心跳，网站据此判断这台 Mac 在线
// - 没开 hooks 时会话状态按日志时间估算：3 分钟内有新回复算“执行中”，否则“已完成”

@MainActor
final class CloudSync: ObservableObject {
    static let shared = CloudSync()

    enum Key {
        static let enabled = "cloudSyncEnabled"
        static let titles = "cloudUploadTitles"
    }

    /// 上报开关：登录后默认开
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Key.enabled)
            resetSent()
            lastError = nil
            kick()
        }
    }
    /// 关掉后网站和手机上只显示项目名
    @Published var uploadTitles: Bool {
        didSet {
            UserDefaults.standard.set(uploadTitles, forKey: Key.titles)
            sentSessions = [:]   // 所有会话按新设置重发一遍
            kick()
        }
    }
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var lastError: String?

    private var usage: (snapshot: UsageSnapshot, at: Date)?
    private var local: LocalSnapshot?

    private var sentUsage: String?
    private var sentSessions: [String: String] = [:]
    /// nil = 还没做过全量同步（app 刚启动 / 刚登录）
    private var sentDaily: [String: String]?
    private var heartbeatSent = false
    private var lastRequestAt = Date.distantPast

    private var running = false
    private var pendingKick = false
    private var userWatch: AnyCancellable?

    private static let heartbeatInterval: TimeInterval = 120

    private init() {
        UserDefaults.standard.register(defaults: [Key.enabled: true, Key.titles: true])
        enabled = UserDefaults.standard.bool(forKey: Key.enabled)
        uploadTitles = UserDefaults.standard.bool(forKey: Key.titles)
        // 登录 / 退出 / 换账号：清空记录，登录后立即全量同步
        userWatch = Cloud.shared.$user
            .map { $0?.id }
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.resetSent()
                    self?.lastSyncAt = nil
                    self?.lastError = nil
                    self?.kick()
                }
            }
    }

    /// 截图、演示模式不上报（演示模式下会话名是假的）
    var isActive: Bool {
        enabled && Cloud.shared.isSignedIn && !Cloud.isPreview && !Demo.enabled
            && !UserDefaults.standard.bool(forKey: "offline")
    }

    // MARK: Store 调用

    func usageUpdated(_ u: UsageSnapshot, at: Date) {
        usage = (u, at)
        kick()
    }

    func localUpdated(_ l: LocalSnapshot) {
        local = l
        kick()
    }

    // MARK: 同步

    private func resetSent() {
        sentUsage = nil
        sentSessions = [:]
        sentDaily = nil
        heartbeatSent = false
    }

    /// 同一时间只跑一轮；跑的过程中又有新数据，跑完再来一轮
    private func kick() {
        guard isActive else { return }
        if running { pendingKick = true; return }
        running = true
        Task {
            await syncOnce()
            running = false
            if pendingKick { pendingKick = false; kick() }
        }
    }

    private func syncOnce() async {
        guard let token = Cloud.shared.token else { return }
        do {
            var sent = false
            if !heartbeatSent {
                try await send("POST", "/api/ingest/heartbeat", ["app_version": Self.appVersion], token: token)
                heartbeatSent = true
                sent = true
            }
            if let (u, at) = usage {
                let (payload, sig) = Self.usagePayload(u, at: at)
                if sig != sentUsage {
                    try await send("PUT", "/api/ingest/usage", payload, token: token)
                    sentUsage = sig
                    sent = true
                }
            }
            if let l = local {
                if try await syncSessions(l, token: token) { sent = true }
                if try await syncDaily(l, token: token) { sent = true }
            }
            if !sent && Date().timeIntervalSince(lastRequestAt) >= Self.heartbeatInterval - 5 {
                try await send("POST", "/api/ingest/heartbeat", ["app_version": Self.appVersion], token: token)
            }
            lastError = nil
        } catch SyncError.unauthorized {
            Cloud.shared.handleUnauthorized()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func syncSessions(_ l: LocalSnapshot, token: String) async throws -> Bool {
        let now = Date()
        var changed: [(id: String, sig: String, payload: [String: Any])] = []
        for s in l.sessions {
            let p = sessionPayload(s, now: now)
            let sig = Self.signature(p, excluding: ["status_at"])
            if sentSessions[s.id] != sig { changed.append((s.id, sig, p)) }
        }
        // 第一次同步可能有几百个会话：每批 100 个，最近的先发
        for start in stride(from: 0, to: changed.count, by: 100) {
            let batch = changed[start..<min(start + 100, changed.count)]
            try await send("POST", "/api/ingest/sessions", ["sessions": batch.map(\.payload)], token: token)
            for c in batch { sentSessions[c.id] = c.sig }
        }
        return !changed.isEmpty
    }

    private func syncDaily(_ l: LocalSnapshot, token: String) async throws -> Bool {
        let rows = Self.dailyRows(l)
        let full = sentDaily == nil
        let changed = full ? rows : rows.filter { sentDaily?[$0.key] != $0.sig }
        guard full || !changed.isEmpty else { return false }
        // 全量时第一批带 full，服务端先清掉这台 Mac 的旧数据
        var first = true
        for start in stride(from: 0, to: max(changed.count, 1), by: 1000) {
            let batch = changed[start..<min(start + 1000, changed.count)]
            try await send("PUT", "/api/ingest/daily", ["full": full && first, "rows": batch.map(\.payload)], token: token)
            first = false
        }
        var next = full ? [:] : (sentDaily ?? [:])
        for r in changed { next[r.key] = r.sig }
        sentDaily = next
        return true
    }

    private enum SyncError: Error { case unauthorized }

    private func send(_ method: String, _ path: String, _ body: [String: Any], token: String) async throws {
        let (_, status) = try await Cloud.request(method, path, json: body, token: token)
        if status == 401 { throw SyncError.unauthorized }
        guard (200..<300).contains(status) else { throw CloudError.http(status) }
        lastRequestAt = Date()
        lastSyncAt = lastRequestAt
    }

    // MARK: 数据格式

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private static func ms(_ d: Date) -> Int64 { Int64((d.timeIntervalSince1970 * 1000).rounded()) }

    /// 字段排好序的 JSON，用来判断有没有变化
    private static func signature(_ p: [String: Any], excluding: Set<String> = []) -> String {
        let filtered = p.filter { !excluding.contains($0.key) }
        guard let d = try? JSONSerialization.data(withJSONObject: filtered, options: [.sortedKeys]) else { return UUID().uuidString }
        return String(decoding: d, as: UTF8.self)
    }

    private static func usagePayload(_ u: UsageSnapshot, at: Date) -> ([String: Any], String) {
        let limits: [[String: Any]] = u.limits.map { l in
            var d: [String: Any] = ["kind": l.kind, "title": l.title, "percent": l.percent]
            if let s = l.scope { d["scope"] = s }
            if let s = l.severity { d["severity"] = s }
            if let r = l.resetsAt { d["resets_at"] = ms(r) }
            return d
        }
        var payload: [String: Any] = ["limits": limits, "fetched_at": ms(at)]
        if let plan = u.plan { payload["plan"] = plan }
        // 签名不含 fetched_at 和标题（标题跟着界面语言变）：只有额度本身变了才发
        let sigLimits = limits.map { $0.filter { $0.key != "title" } }
        let sig = signature(["plan": u.plan ?? "", "limits": sigLimits])
        return (payload, sig)
    }

    /// 扫描器在没有标题时填的占位文字，不上传
    private static let untitled: Set<String> = ["（无标题）", "(untitled)", "（無題）", "(제목 없음)"]

    private func sessionPayload(_ s: SessionSummary, now: Date) -> [String: Any] {
        let active = s.isActive(now: now)
        var p: [String: Any] = [
            "id": s.id,
            "project": s.project,
            "model": s.mainModel,
            "status": active ? "running" : "done",
            "status_at": Self.ms(active ? now : s.end),
            "started_at": Self.ms(s.start),
            "last_activity_at": Self.ms(s.end),
            "tokens_in": s.tokens.input,
            "tokens_out": s.tokens.output,
            "tokens_cache_read": s.tokens.cacheRead,
            "tokens_cache_write": s.tokens.cacheWrite,
            "requests": s.requests,
        ]
        if uploadTitles && !Self.untitled.contains(s.title) { p["title"] = s.title }
        return p
    }

    private static func dailyRows(_ l: LocalSnapshot) -> [(key: String, sig: String, payload: [String: Any])] {
        struct Agg { var t = TokenCount(); var n = 0 }
        var by: [String: (day: String, project: String, model: String, agg: Agg)] = [:]
        let cal = Fmt.calendar
        for m in l.messages {
            let c = cal.dateComponents([.year, .month, .day], from: m.ts)
            let day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            let key = "\(day)|\(m.project)|\(m.model)"
            var e = by[key] ?? (day, m.project, m.model, Agg())
            e.agg.t += m.tokens
            e.agg.n += 1
            by[key] = e
        }
        return by.map { key, e in
            let t = e.agg.t
            return (key, "\(t.input)|\(t.output)|\(t.cacheRead)|\(t.cacheWrite)|\(e.agg.n)", [
                "day": e.day, "project": e.project, "model": e.model,
                "tokens_in": t.input, "tokens_out": t.output,
                "tokens_cache_read": t.cacheRead, "tokens_cache_write": t.cacheWrite,
                "requests": e.agg.n,
            ])
        }
    }
}
