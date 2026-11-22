import Foundation

// 读 Codex（CLI / 桌面版 / IDE 插件）写在本机的日志：~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
// 和 ~/.codex/archived_sessions。只读，不改任何文件。
//
// 每次模型回复结束后有一条 event_msg / token_count：
//   info.last_token_usage  这次回复的 input（含缓存）/ cached_input / output（含推理）token
//   info.total_token_usage 整个会话累计，用来去掉重复的记录
//   rate_limits.primary    5 小时额度（window_minutes 300）的 used_percent、resets_at（Unix 秒）
//   rate_limits.secondary  每周额度（window_minutes 10080）
//   rate_limits.plan_type  套餐（plus / pro …）
// 回复耗时：从上一次工具结果 / 用户消息 / 任务开始，到这次回复的 token_usage_record（没有就用 token_count 本身）。
//
// 注意：Codex 桌面版会把 Claude Code 的会话「导入」进自己的 sessions 目录，
// 记录在 ~/.codex/external_agent_session_imports.json。这些不是 Codex 的用量，统计时按 id 排除。

struct CodexLimits {
    struct Window {
        let percent: Double
        let minutes: Int
        let resetsAt: Date?
    }
    let plan: String?
    let primary: Window?
    let secondary: Window?
    let observedAt: Date

    /// 换成和 Claude 一样的额度条目。过了重置时间、又还没有新记录时按 0% 显示。
    func limitItems(now: Date) -> [LimitItem] {
        var out: [LimitItem] = []
        func add(_ w: Window?, kind: String, title: String) {
            guard let w else { return }
            let reset = w.resetsAt
            let expired = reset.map { $0 <= now } ?? false
            out.append(LimitItem(id: "codex-\(kind)", kind: kind, title: title,
                                 percent: expired ? 0 : w.percent, severity: nil,
                                 resetsAt: expired ? nil : reset))
        }
        add(primary, kind: Self.kind(minutes: primary?.minutes), title: L("Codex · 5 小时", "Codex · 5 hours", ja: "Codex · 5 時間", ko: "Codex · 5시간"))
        add(secondary, kind: Self.kind(minutes: secondary?.minutes), title: L("Codex · 本周", "Codex · this week", ja: "Codex · 今週", ko: "Codex · 이번 주"))
        return out
    }

    private static func kind(minutes: Int?) -> String {
        switch minutes {
        case 300: return "session"
        case 10080: return "weekly_all"
        default: return "window_\(minutes ?? 0)"
        }
    }

    var planTitle: String? {
        guard let p = plan, !p.isEmpty else { return nil }
        return p.prefix(1).uppercased() + p.dropFirst()
    }
}

/// 一个 Codex 日志文件解析出来的东西
struct CodexFile {
    var id = ""
    var cwd: String?
    var start: Date?
    var model: String?
    var firstPrompt: String?
    var messages: [MessageUsage] = []
    var limits: CodexLimits?
    var activity: LiveActivity?
}

enum CodexLogs {
    static var home: URL {
        if let h = ProcessInfo.processInfo.environment["CODEX_HOME"], !h.isEmpty { return URL(fileURLWithPath: h) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    static func files(modifiedAfter cutoff: Date) -> [(url: URL, mtime: Date, size: Int)] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        var out: [(URL, Date, Int)] = []
        for dir in ["sessions", "archived_sessions"] {
            guard let e = FileManager.default.enumerator(at: home.appendingPathComponent(dir), includingPropertiesForKeys: keys) else { continue }
            for case let url as URL in e where url.pathExtension == "jsonl" {
                guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                      let m = v.contentModificationDate, m >= cutoff else { continue }
                out.append((url, m, v.fileSize ?? 0))
            }
        }
        return out
    }

    /// Codex 桌面版从别的工具（Claude Code）导入的会话 id
    static func importedThreadIDs() -> Set<String> {
        let url = home.appendingPathComponent("external_agent_session_imports.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = root["records"] as? [[String: Any]] else { return [] }
        return Set(records.compactMap { $0["imported_thread_id"] as? String })
    }

    /// session_index.jsonl：会话 id → 标题
    static func threadNames() -> [String: String] {
        let url = home.appendingPathComponent("session_index.jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let d = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = d["id"] as? String, let name = d["thread_name"] as? String, !name.isEmpty else { continue }
            out[id] = name
        }
        return out
    }

    // MARK: 解析

    private static func needle(_ s: String) -> [UInt8] { Array(s.utf8) }
    private static let nTokenCount = needle(#""type":"token_count""#)
    private static let nUsageRecord = needle(#""type":"token_usage_record""#)
    private static let nSessionMeta = needle(#""type":"session_meta""#)
    private static let nTurnContext = needle(#""type":"turn_context""#)
    private static let nTaskStarted = needle(#""type":"task_started""#)
    private static let nUserMessage = needle(#""type":"user_message""#)
    private static let nTaskComplete = needle(#""type":"task_complete""#)
    private static let nTaskAborted = needle(#""type":"turn_aborted""#)
    private static let nFunctionCall = needle(#""type":"function_call""#)
    private static let nCustomCall = needle(#""type":"custom_tool_call""#)
    private static let nCallOutput = needle(#"_call_output""#)

    static func parse(url: URL) -> CodexFile {
        var f = CodexFile()
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return f }
        var boundary: Date?        // 这次请求从什么时候开始
        var pendingEnd: Date?      // token_usage_record 记下的回复结束时间
        var lastTotal = -1
        var activity = LiveActivity(id: url.path, source: .codex)

        // 类型标记都在每行开头附近（{"timestamp":"…","type":"…","payload":{"type":"…"），只在前 200 字节里找，
        // 避免工具输出的正文里恰好出现这些字样
        func head(_ p: UnsafeRawPointer, _ len: Int, _ n: [UInt8]) -> Bool {
            n.withUnsafeBytes { memmem(p, min(len, 200), $0.baseAddress, $0.count) != nil }
        }
        func json(_ p: UnsafeRawPointer, _ len: Int) -> [String: Any]? {
            try? JSONSerialization.jsonObject(with: Data(bytes: p, count: len)) as? [String: Any]
        }

        func handle(_ p: UnsafeRawPointer, _ len: Int) {
            if head(p, len, nTaskComplete) || head(p, len, nTaskAborted) {
                if let ts = SessionScanner.quickTimestamp(p, len) { activity.update(.idle, at: ts) }
                boundary = nil
                return
            }
            if head(p, len, nFunctionCall) || head(p, len, nCustomCall) {
                if let ts = SessionScanner.quickTimestamp(p, len) { activity.update(.tools, at: ts) }
                return
            }
            if head(p, len, nTokenCount) {
                guard let d = json(p, len), let pl = d["payload"] as? [String: Any],
                      let ts = SessionScanner.date(d["timestamp"]) else { return }
                if let rl = pl["rate_limits"] as? [String: Any] {
                    func window(_ k: String) -> CodexLimits.Window? {
                        guard let w = rl[k] as? [String: Any], let used = (w["used_percent"] as? NSNumber)?.doubleValue else { return nil }
                        let reset = (w["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
                        return .init(percent: used, minutes: (w["window_minutes"] as? NSNumber)?.intValue ?? 0, resetsAt: reset)
                    }
                    let lim = CodexLimits(plan: rl["plan_type"] as? String ?? f.limits?.plan,
                                          primary: window("primary"), secondary: window("secondary"), observedAt: ts)
                    if lim.primary != nil || lim.secondary != nil { f.limits = lim }
                }
                var recordedResponse = false
                if let info = pl["info"] as? [String: Any],
                   let total = ((info["total_token_usage"] as? [String: Any])?["total_tokens"] as? NSNumber)?.intValue,
                   total > lastTotal, let last = info["last_token_usage"] as? [String: Any] {
                    lastTotal = total
                    func int(_ k: String) -> Int { (last[k] as? NSNumber)?.intValue ?? 0 }
                    let input = int("input_tokens"), cached = int("cached_input_tokens"), output = int("output_tokens")
                    if input + output > 0 {
                        let t = TokenCount(input: max(0, input - cached), output: output,
                                           cacheRead: cached, cacheWrite: int("cache_write_input_tokens"))
                        let end = pendingEnd ?? ts
                        let dur = boundary.flatMap { SessionScanner.sane(end.timeIntervalSince($0)) }
                        recordedResponse = true
                        f.messages.append(MessageUsage(ts: end, model: f.model ?? "codex", tokens: t, source: .codex, duration: dur))
                    }
                }
                pendingEnd = nil
                // 不把相同累计用量的额度刷新当成新回复。
                if recordedResponse {
                    if activity.phase == .generating { activity.update(.idle, at: ts) }
                    boundary = ts
                }
            } else if head(p, len, nUsageRecord) {
                pendingEnd = SessionScanner.quickTimestamp(p, len)
            } else if head(p, len, nCallOutput) || head(p, len, nTaskStarted) {
                boundary = SessionScanner.quickTimestamp(p, len)
                if let boundary { activity.update(.generating, at: boundary) }
            } else if head(p, len, nUserMessage) {
                boundary = SessionScanner.quickTimestamp(p, len)
                if let boundary { activity.update(.generating, at: boundary) }
                if f.firstPrompt == nil, let d = json(p, len), let pl = d["payload"] as? [String: Any],
                   let msg = pl["message"] as? String, !msg.isEmpty {
                    f.firstPrompt = msg
                }
            } else if head(p, len, nTurnContext) {
                if let d = json(p, len), let pl = d["payload"] as? [String: Any], let m = pl["model"] as? String { f.model = m; activity.model = m }
            } else if head(p, len, nSessionMeta) {
                if let d = json(p, len), let pl = d["payload"] as? [String: Any] {
                    f.id = pl["id"] as? String ?? ""
                    f.cwd = pl["cwd"] as? String
                    f.start = SessionScanner.date(pl["timestamp"]) ?? SessionScanner.date(d["timestamp"])
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
        f.activity = activity
        return f
    }

    static func build(_ files: [CodexFile], titles: [String: String], cutoff: Date, limits: CodexLimits?)
        -> (sessions: [SessionSummary], messages: [MessageUsage], limits: CodexLimits?) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var sessions: [SessionSummary] = []
        var messages: [MessageUsage] = []
        for f in files {
            let msgs = f.messages.filter { $0.ts >= cutoff }
            guard !msgs.isEmpty else { continue }
            let project: String = {
                guard let cwd = f.cwd else { return "Codex" }
                if cwd == home { return "~" }
                // 桌面版没选项目时在 ~/Documents/Codex/<日期>/<序号> 里干活
                if cwd.hasPrefix(home + "/Documents/Codex/") { return "Codex" }
                return (cwd as NSString).lastPathComponent
            }()
            var tokens = TokenCount()
            for m in msgs { tokens += m.tokens }
            messages.append(contentsOf: msgs.map { var m = $0; m.project = project; m.sessionId = "codex-" + f.id; return m })
            var title = titles[f.id] ?? f.firstPrompt ?? L("（无标题）", "(untitled)", ja: "（無題）", ko: "(제목 없음)")
            title = title.replacingOccurrences(of: "\n", with: " ")
            if title.count > 60 { title = String(title.prefix(60)) + "…" }
            sessions.append(SessionSummary(id: "codex-" + f.id, project: project, cwd: f.cwd, title: title,
                                           start: f.start ?? msgs.first!.ts, end: msgs.last!.ts,
                                           tokens: tokens, subagentTokens: 0, requests: msgs.count,
                                           mainModel: f.model ?? "codex", source: .codex))
        }
        return (sessions, messages, limits)
    }
}

extension SessionScanner {
    static func date(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        return isoFrac.date(from: s) ?? isoPlain.date(from: s)
    }
}
