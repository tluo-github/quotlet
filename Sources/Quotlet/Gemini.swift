import Foundation
import SQLite3

// 读 Antigravity（Gemini）写在本机的状态与日志：
// 1. 额度与套餐：通过本地语言服务器（language_server）暴露的 ConnectRPC 接口查询，
//    守护配置保存在 ~/.gemini/antigravity/daemon/hub_*.json。
// 2. 会话与 Token：读取 ~/.gemini/antigravity/brain/<id>/.system_generated/logs/transcript.jsonl
//    结合 ~/.gemini/antigravity/conversation_summaries.db 提取标题与工作区项目名。

// MARK: - 数据模型

struct GeminiLimits {
    struct Bucket: Hashable {
        let id: String
        let groupName: String
        let groupDescription: String?
        let displayName: String
        let window: String
        let remainingFraction: Double
        let resetTime: Date?

        init(id: String, groupName: String, groupDescription: String? = nil,
             displayName: String, window: String, remainingFraction: Double, resetTime: Date?) {
            self.id = id
            self.groupName = groupName
            self.groupDescription = groupDescription
            self.displayName = displayName
            self.window = window
            self.remainingFraction = remainingFraction
            self.resetTime = resetTime
        }
    }

    let plan: String?
    let buckets: [Bucket]
    let observedAt: Date

    /// 转换为统一的 LimitItem。
    /// Antigravity 返回的是 remainingFraction（剩余比例 0.0~1.0），
    /// Quotlet 界面展示的是已用百分比（0%~100%）。
    func limitItems(now: Date) -> [LimitItem] {
        let ordered = buckets.sorted { a, b in
            let ga = Self.groupOrder(a)
            let gb = Self.groupOrder(b)
            if ga != gb { return ga < gb }
            let wa = Self.windowOrder(a.window)
            let wb = Self.windowOrder(b.window)
            if wa != wb { return wa < wb }
            return a.id < b.id
        }
        return ordered.map { b in
            let rawUsed = max(0, min(100, (1.0 - b.remainingFraction) * 100.0))
            // 四舍五入到 1 位小数，避免 0.9999 显示成 0.0%
            let usedPercent = (rawUsed * 10).rounded() / 10
            let expired = b.resetTime.map { $0 <= now } ?? false
            let win = b.window.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let primary = Self.isPrimaryGemini(b)
            let scope = primary ? nil : Self.scopeName(for: b)
            let kind = Self.limitKind(window: win, isPrimary: primary)
            let title = Self.limitTitle(window: win, scope: scope, fallback: b.displayName)
            return LimitItem(
                id: "gemini-\(b.id)",
                kind: kind,
                title: title,
                percent: expired ? 0 : usedPercent,
                severity: nil,
                resetsAt: expired ? nil : b.resetTime,
                scope: scope,
                detail: Self.localizedDetail(b.groupDescription)
            )
        }
    }

    private static func localizedDetail(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let prefix = "Models within this group: "
        if raw.hasPrefix(prefix) {
            let models = String(raw.dropFirst(prefix.count))
            return L("包含模型：\(models)", "Models: \(models)", ja: "対象モデル：\(models)", ko: "포함 모델: \(models)")
        }
        if raw.localizedCaseInsensitiveContains("Argon quota is separate") {
            return L("包含模型：Gemini 4 Argon、Orchestrator (Argon)（Pro 套餐独立计周额度）", raw,
                     ja: "対象モデル：Gemini 4 Argon, Orchestrator (Argon)（Pro プランでは独立した週間枠）",
                     ko: "포함 모델: Gemini 4 Argon, Orchestrator (Argon) (Pro 요금제 별도 주간 한도)")
        }
        return raw
    }

    var planTitle: String? {
        guard let p = plan, !p.isEmpty else { return nil }
        return p
    }

    private static func isPrimaryGemini(_ b: Bucket) -> Bool {
        if b.groupName.lowercased() == "gemini models" { return true }
        return b.id == "gemini-5h" || b.id == "gemini-weekly" || b.id == "gemini-daily"
    }

    private static func scopeName(for b: Bucket) -> String {
        let lowerGroup = b.groupName.lowercased()
        if b.id.hasPrefix("3p-") || (lowerGroup.contains("claude") && lowerGroup.contains("gpt")) {
            return "Claude / GPT"
        }
        if !b.groupName.isEmpty {
            return b.groupName
                .replacingOccurrences(of: " models", with: "", options: [.caseInsensitive, .anchored, .backwards])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if b.id.contains("argon") { return "Gemini 4 Argon" }
        return b.displayName
    }

    private static func groupOrder(_ b: Bucket) -> Int {
        if isPrimaryGemini(b) { return 0 }
        if b.id.hasPrefix("gemini-") || b.groupName.lowercased().hasPrefix("gemini") { return 1 }
        if b.id.hasPrefix("3p-") || b.groupName.lowercased().contains("claude") { return 2 }
        return 3
    }

    private static func windowOrder(_ window: String) -> Int {
        switch window.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "5h": return 0
        case "daily": return 1
        case "weekly": return 2
        default: return 3
        }
    }

    private static func limitKind(window: String, isPrimary: Bool) -> String {
        switch window {
        case "5h": return isPrimary ? "session" : "session_scoped"
        case "daily": return isPrimary ? "daily_all" : "daily_scoped"
        case "weekly": return isPrimary ? "weekly_all" : "weekly_scoped"
        default: return isPrimary ? "window_\(window)" : "window_scoped"
        }
    }

    private static func limitTitle(window: String, scope: String?, fallback: String) -> String {
        let prefix = scope ?? "Gemini"
        switch window {
        case "5h":
            return L("\(prefix) · 5 小时", "\(prefix) · 5 hours", ja: "\(prefix) · 5 時間", ko: "\(prefix) · 5시간")
        case "daily":
            return L("\(prefix) · 今日", "\(prefix) · daily", ja: "\(prefix) · 本日", ko: "\(prefix) · 일간")
        case "weekly":
            return L("\(prefix) · 本周", "\(prefix) · this week", ja: "\(prefix) · 今週", ko: "\(prefix) · 이번 주")
        default:
            return "\(prefix) · \(fallback)"
        }
    }

    /// 推断老缓存缺失的 groupName，保持向后兼容。
    static func inferredGroupName(bucketId: String) -> String {
        if bucketId == "gemini-5h" || bucketId == "gemini-weekly" || bucketId == "gemini-daily" {
            return "Gemini Models"
        }
        if bucketId.hasPrefix("3p-") { return "Claude and GPT models" }
        if bucketId.contains("argon") { return "Gemini 4 Argon" }
        return ""
    }

    /// 解析 GetLoadCodeAssist 返回的套餐名，输出与 Claude Pro / Codex Plus 一致的简洁标签。
    static func parsePlan(fromLoadCodeAssist root: [String: Any]) -> String? {
        guard let res = root["response"] as? [String: Any] else { return nil }
        if let paid = res["paidTier"] as? [String: Any] {
            let id = (paid["id"] as? String ?? "").lowercased()
            let name = paid["name"] as? String ?? ""
            if id.contains("ultra") || name.localizedCaseInsensitiveContains("ultra") { return "Ultra" }
            if id.contains("pro") || name.localizedCaseInsensitiveContains("pro") { return "Pro" }
            if !name.isEmpty { return name }
        }
        if let cur = res["currentTier"] as? [String: Any] {
            let id = (cur["id"] as? String ?? "").lowercased()
            let name = cur["name"] as? String ?? ""
            if id.contains("free") { return "Free" }
            if id.contains("standard") { return "Standard" }
            if !name.isEmpty { return name }
        }
        return nil
    }
}

// MARK: - 本地缓存

enum GeminiCache {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Quotabar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("gemini-usage.json")
    }

    static func save(_ limits: GeminiLimits) {
        var bucketsData: [[String: Any]] = []
        for b in limits.buckets {
            var item: [String: Any] = [
                "id": b.id,
                "groupName": b.groupName,
                "displayName": b.displayName,
                "window": b.window,
                "remainingFraction": b.remainingFraction
            ]
            if let desc = b.groupDescription { item["groupDescription"] = desc }
            if let r = b.resetTime {
                item["resetTime"] = SessionScanner.isoFrac.string(from: r)
            }
            bucketsData.append(item)
        }
        var dict: [String: Any] = [
            "observedAt": limits.observedAt.timeIntervalSince1970,
            "buckets": bucketsData
        ]
        if let plan = limits.plan { dict["plan"] = plan }
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            try? data.write(to: url)
        }
    }

    static func load() -> (GeminiLimits, Date)? {
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bucketsRaw = dict["buckets"] as? [[String: Any]] else { return nil }
        var buckets: [GeminiLimits.Bucket] = []
        for r in bucketsRaw {
            guard let id = r["id"] as? String,
                  let name = r["displayName"] as? String,
                  let window = r["window"] as? String,
                  let fraction = (r["remainingFraction"] as? NSNumber)?.doubleValue else { continue }
            let groupName = (r["groupName"] as? String) ?? GeminiLimits.inferredGroupName(bucketId: id)
            let groupDesc = r["groupDescription"] as? String
            let reset = (r["resetTime"] as? String).flatMap { Fmt.parseISO($0) }
            buckets.append(.init(id: id, groupName: groupName, groupDescription: groupDesc,
                                 displayName: name, window: window,
                                 remainingFraction: fraction, resetTime: reset))
        }
        let plan = (dict["plan"] as? String).flatMap { $0.isEmpty || $0 == "Google" ? nil : $0 }
        let ts = (dict["observedAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } ?? Date()
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? ts
        return (GeminiLimits(plan: plan, buckets: buckets, observedAt: ts), mtime)
    }
}

// MARK: - 本地语言服务器连接与 RPC

final class LocalInsecureSessionDelegate: NSObject, URLSessionDelegate {
    static let shared = LocalInsecureSessionDelegate()
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

enum GeminiAPI {
    struct HubInfo {
        let pid: Int
        let httpsPort: Int
        let httpPort: Int
        let csrfToken: String
        let lsVersion: String
    }

    private static let lock = NSLock()
    private static var lastFetchAt = Date.distantPast
    private static var lastFetchedLimits: GeminiLimits?
    private static let minFetchInterval: TimeInterval = 15

    static func activeHub() -> HubInfo? {
        let daemonDir = GeminiLogs.home.appendingPathComponent("antigravity/daemon")
        guard let files = try? FileManager.default.contentsOfDirectory(at: daemonDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        let jsonFiles = files.filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("hub_") }
        let sorted = jsonFiles.sorted {
            let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            return d1 > d2
        }
        for file in sorted {
            guard let data = try? Data(contentsOf: file),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = root["pid"] as? Int,
                  let httpsPort = root["httpsPort"] as? Int,
                  let csrfToken = root["csrfToken"] as? String else { continue }
            if kill(pid_t(pid), 0) == 0 {
                return HubInfo(pid: pid, httpsPort: httpsPort,
                               httpPort: root["httpPort"] as? Int ?? httpsPort,
                               csrfToken: csrfToken,
                               lsVersion: root["lsVersion"] as? String ?? "")
            }
        }
        return nil
    }

    private static func callRPC(hub: HubInfo, method: String, body: String = "{}") async -> [String: Any]? {
        guard let url = URL(string: "https://127.0.0.1:\(hub.httpsPort)/exa.language_server_pb.LanguageServerService/\(method)") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(hub.csrfToken, forHTTPHeaderField: "x-codeium-csrf-token")
        req.httpBody = Data(body.utf8)
        req.timeoutInterval = 4

        let session = URLSession(configuration: .ephemeral, delegate: LocalInsecureSessionDelegate.shared, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, resp) = try await session.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    /// 解析 RetrieveUserQuotaSummary 返回的 JSON 为 bucket 列表。
    static func parseQuotaBuckets(from root: [String: Any]) -> [GeminiLimits.Bucket] {
        guard let res = root["response"] as? [String: Any],
              let groups = res["groups"] as? [[String: Any]] else { return [] }
        var buckets: [GeminiLimits.Bucket] = []
        for g in groups {
            let groupName = g["displayName"] as? String ?? ""
            let groupDesc = (g["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            guard let bList = g["buckets"] as? [[String: Any]] else { continue }
            for b in bList {
                guard let bId = b["bucketId"] as? String else { continue }
                let name = b["displayName"] as? String ?? bId
                let win = b["window"] as? String ?? "weekly"
                let fraction = (b["remainingFraction"] as? NSNumber)?.doubleValue ?? 1.0
                let reset = Fmt.parseISO(b["resetTime"] as? String)
                buckets.append(.init(id: bId, groupName: groupName, groupDescription: groupDesc,
                                     displayName: name, window: win,
                                     remainingFraction: fraction, resetTime: reset))
            }
        }
        return buckets
    }

    /// 向本地 language_server 查询配额快照和套餐信息（节流，避免高频日志写入时反复请求）。
    static func fetchQuota(force: Bool = false) async -> GeminiLimits? {
        if !force {
            let recent: GeminiLimits? = lock.withLock {
                guard let cached = lastFetchedLimits,
                      Date().timeIntervalSince(lastFetchAt) < minFetchInterval else { return nil }
                return cached
            }
            if let recent { return recent }
        }
        guard let hub = activeHub() else {
            return GeminiCache.load()?.0
        }

        async let quotaRoot = callRPC(hub: hub, method: "RetrieveUserQuotaSummary")
        async let tierRoot = callRPC(hub: hub, method: "GetLoadCodeAssist")
        let (quota, tier) = await (quotaRoot, tierRoot)

        if let quota {
            let buckets = parseQuotaBuckets(from: quota)
            if !buckets.isEmpty {
                let plan = tier.flatMap { GeminiLimits.parsePlan(fromLoadCodeAssist: $0) }
                    ?? GeminiCache.load()?.0.plan
                let limits = GeminiLimits(plan: plan, buckets: buckets, observedAt: Date())
                GeminiCache.save(limits)
                lock.withLock {
                    lastFetchedLimits = limits
                    lastFetchAt = limits.observedAt
                }
                return limits
            }
        }
        return GeminiCache.load()?.0
    }
}

// MARK: - 日志与会话扫描

struct GeminiFile {
    var id = ""
    var cwd: String?
    var start: Date?
    var model: String?
    var firstPrompt: String?
    var messages: [MessageUsage] = []
}

enum GeminiLogs {
    static var home: URL {
        if let h = ProcessInfo.processInfo.environment["GEMINI_HOME"], !h.isEmpty { return URL(fileURLWithPath: h) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini")
    }

    static var brainDir: URL { home.appendingPathComponent("antigravity/brain") }
    static var dbPath: URL { home.appendingPathComponent("antigravity/conversation_summaries.db") }

    /// 读取 conversation_summaries.db 获取会话的标题和工作区路径
    static func conversationMetas() -> [String: (title: String, project: String, cwd: String?)] {
        guard FileManager.default.fileExists(atPath: dbPath.path) else { return [:] }
        var db: OpaquePointer?
        let uri = "file:\(dbPath.path)?immutable=1"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = "SELECT conversation_id, title, workspace_uris FROM conversation_summaries"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }

        var out: [String: (title: String, project: String, cwd: String?)] = [:]
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cIdText = sqlite3_column_text(stmt, 0) else { continue }
            let cid = String(cString: cIdText)
            let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            var project = "Antigravity"
            var cwd: String?

            if let wsText = sqlite3_column_text(stmt, 2) {
                let wsRaw = String(cString: wsText)
                if let data = wsRaw.data(using: .utf8),
                   let uris = try? JSONSerialization.jsonObject(with: data) as? [String],
                   let first = uris.first {
                    let cleaned = first.hasPrefix("file://") ? String(first.dropFirst(7)) : first
                    let path = cleaned.removingPercentEncoding ?? cleaned
                    cwd = path
                    if path == home {
                        project = "~"
                    } else if !path.isEmpty {
                        project = (path as NSString).lastPathComponent
                    }
                }
            }
            out[cid] = (title: title, project: project, cwd: cwd)
        }
        return out
    }

    /// 查找在 cutoff 之后修改过的 transcript.jsonl
    static func files(modifiedAfter cutoff: Date) -> [(url: URL, mtime: Date, size: Int, id: String)] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]
        guard let convDirs = try? fm.contentsOfDirectory(at: brainDir, includingPropertiesForKeys: keys) else { return [] }

        var out: [(URL, Date, Int, String)] = []
        for dir in convDirs {
            let logFile = dir.appendingPathComponent(".system_generated/logs/transcript.jsonl")
            guard let v = try? logFile.resourceValues(forKeys: Set(keys)),
                  let m = v.contentModificationDate, m >= cutoff else { continue }
            out.append((logFile, m, v.fileSize ?? 0, dir.lastPathComponent))
        }
        return out
    }

    private static func needle(_ s: String) -> [UInt8] { Array(s.utf8) }
    private static let nPlanner = needle(#""type":"PLANNER_RESPONSE""#)
    private static let nUserInput = needle(#""type":"USER_INPUT""#)
    private static let nCreatedAt = needle(#""created_at":""#)

    private static func quickCreatedAt(_ p: UnsafeRawPointer, _ len: Int) -> Date? {
        guard let hit = nCreatedAt.withUnsafeBytes({ n in memmem(p, len, n.baseAddress, n.count) }) else { return nil }
        let start = UnsafeRawPointer(hit) + nCreatedAt.count
        let remain = len - (start - p)
        guard remain > 0 else { return nil }
        var n = 0
        while n < min(remain, 40), start.load(fromByteOffset: n, as: UInt8.self) != 0x22 { n += 1 }
        guard let str = String(bytes: UnsafeRawBufferPointer(start: start, count: n), encoding: .utf8) else { return nil }
        return SessionScanner.isoFrac.date(from: str) ?? SessionScanner.isoPlain.date(from: str)
    }

    /// 解析单个 transcript.jsonl 文件。
    /// transcript.jsonl 中 PLANNER_RESPONSE 的 created_at 为模型开始生成的时间；
    /// 当它触发工具调用（tool_calls）时，紧接着的下一条非 USER_INPUT 步骤（如 GENERIC）的 created_at
    /// 即为本次模型生成完成的时间，差值即为真实回复耗时。
    static func parse(url: URL, id: String) -> GeminiFile {
        var f = GeminiFile(id: id)
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return f }

        // 上一条等待结算完成时间的 PLANNER_RESPONSE（下标, 开始时间, 是否含 tool_calls）
        var pendingPlanner: (index: Int, start: Date, hasToolCalls: Bool)?

        func contains(_ p: UnsafeRawPointer, _ len: Int, _ n: [UInt8]) -> Bool {
            n.withUnsafeBytes { memmem(p, len, $0.baseAddress, $0.count) != nil }
        }
        func json(_ p: UnsafeRawPointer, _ len: Int) -> [String: Any]? {
            try? JSONSerialization.jsonObject(with: Data(bytes: p, count: len)) as? [String: Any]
        }

        func handle(_ p: UnsafeRawPointer, _ len: Int) {
            if contains(p, len, nPlanner) {
                guard let d = json(p, len),
                      let ts = SessionScanner.date(d["created_at"]) else { return }
                // 若上条是带工具调用的 PLANNER_RESPONSE，此处可能跳过中间步骤直接进入下一轮
                if let prev = pendingPlanner, prev.hasToolCalls {
                    if let dur = SessionScanner.sane(ts.timeIntervalSince(prev.start)) {
                        f.messages[prev.index].ts = ts
                        f.messages[prev.index].duration = dur
                    }
                }
                pendingPlanner = nil
                if f.start == nil { f.start = ts }
                let model = d["model"] as? String ?? f.model ?? "gemini"
                f.model = model
                func int(_ k: String) -> Int { (d[k] as? NSNumber)?.intValue ?? 0 }
                let input = int("input_tokens")
                let output = int("output_tokens")
                let cacheRead = int("cache_read_tokens")
                if input + output > 0 {
                    let tokens = TokenCount(input: input, output: output, cacheRead: cacheRead, cacheWrite: 0)
                    let idx = f.messages.count
                    f.messages.append(MessageUsage(ts: ts, model: model, tokens: tokens, source: .gemini, duration: nil))
                    let hasTools = (d["tool_calls"] as? [Any])?.isEmpty == false
                    pendingPlanner = (idx, ts, hasTools)
                }
            } else if contains(p, len, nUserInput) {
                // 用户输入前的等待包含人工阅读时间，不计入上一条回复的生成耗时
                pendingPlanner = nil
                if f.firstPrompt == nil, let d = json(p, len), let msg = d["content"] as? String, !msg.isEmpty {
                    f.firstPrompt = msg
                }
            } else {
                // GENERIC（工具执行）/ ERROR_MESSAGE / SYSTEM_MESSAGE 等步骤的 created_at 可结算上一条 PLANNER_RESPONSE 的结束时间
                if let prev = pendingPlanner, prev.hasToolCalls, let ts = quickCreatedAt(p, len) {
                    if let dur = SessionScanner.sane(ts.timeIntervalSince(prev.start)) {
                        f.messages[prev.index].ts = ts
                        f.messages[prev.index].duration = dur
                    }
                    pendingPlanner = nil
                }
            }
        }

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            let n = raw.count
            var off = 0
            while off < n {
                let p = base + off
                let rem = n - off
                let len: Int
                if let nl = memchr(p, 0x0A, rem) { len = UnsafeRawPointer(nl) - p } else { len = rem }
                if len > 0 { handle(p, len) }
                off += len + 1
            }
        }
        return f
    }

    static func build(_ files: [GeminiFile], metas: [String: (title: String, project: String, cwd: String?)], cutoff: Date, limits: GeminiLimits?)
        -> (sessions: [SessionSummary], messages: [MessageUsage], limits: GeminiLimits?) {
        var sessions: [SessionSummary] = []
        var messages: [MessageUsage] = []

        for f in files {
            let msgs = f.messages.filter { $0.ts >= cutoff }
            guard !msgs.isEmpty else { continue }
            let meta = metas[f.id]
            let project = meta?.project ?? "Antigravity"
            var tokens = TokenCount()
            var byModel: [String: Int] = [:]
            for m in msgs {
                tokens += m.tokens
                byModel[m.model, default: 0] += m.tokens.output + m.tokens.input
            }
            messages.append(contentsOf: msgs.map { var m = $0; m.project = project; return m })

            var title = (meta?.title.isEmpty == false ? meta?.title : nil) ?? f.firstPrompt ?? L("（无标题）", "(untitled)", ja: "（無題）", ko: "(제목 없음)")
            title = title.replacingOccurrences(of: "\n", with: " ")
            if title.count > 60 { title = String(title.prefix(60)) + "…" }

            let mainModel = byModel.max { $0.value < $1.value }?.key ?? f.model ?? "gemini"
            sessions.append(SessionSummary(
                id: "gemini-" + f.id,
                project: project,
                cwd: meta?.cwd ?? f.cwd,
                title: title,
                start: f.start ?? msgs.first!.ts,
                end: msgs.last!.ts,
                tokens: tokens,
                subagentTokens: 0,
                requests: msgs.count,
                mainModel: mainModel,
                source: .gemini
            ))
        }
        return (sessions, messages, limits)
    }
}
