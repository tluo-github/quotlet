import Foundation

// MARK: - 数据模型

struct TokenCount {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0

    var total: Int { input + output + cacheRead + cacheWrite }

    static func += (a: inout TokenCount, b: TokenCount) {
        a.input += b.input
        a.output += b.output
        a.cacheRead += b.cacheRead
        a.cacheWrite += b.cacheWrite
    }
}

/// 用量来自哪个工具
enum Source: String, CaseIterable, Identifiable {
    case claude, codex
    var id: String { rawValue }
    var title: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }
}

struct MessageUsage {
    let ts: Date
    let model: String
    let tokens: TokenCount
    var project: String = ""
    var source: Source = .claude
    /// 这次回复花的时间：从发出请求（上一条用户消息 / 工具结果）到回复写完。算速度用，拿不到就是 nil。
    var duration: TimeInterval? = nil

    /// 算速度用的 (输出 token, 耗时)。输出太少的回复（十几个 token 却等了很久）主要是在读上下文，不计入速度。
    var timed: (output: Int, seconds: TimeInterval)? {
        guard let d = duration, tokens.output >= 20 else { return nil }
        return (tokens.output, d)
    }
}

struct ProjectShare: Identifiable {
    var id: String { project }
    let project: String
    let tokens: Int
}

struct SessionSummary: Identifiable {
    let id: String
    let project: String
    let cwd: String?
    let title: String
    let start: Date
    let end: Date
    let tokens: TokenCount
    let subagentTokens: Int
    let requests: Int
    let mainModel: String
    var source: Source = .claude

    func isActive(now: Date) -> Bool { now.timeIntervalSince(end) < 180 }
}

struct ModelShare: Identifiable {
    var id: String { model }
    let model: String
    let tokens: TokenCount
}

struct LocalSnapshot {
    let sessions: [SessionSummary]   // 按最后活动时间倒序
    let messages: [MessageUsage]     // 按时间正序
    /// Codex 日志里最近一次记下的额度（没装 / 没用过 Codex 就是 nil）
    var codexLimits: CodexLimits? = nil

    static let empty = LocalSnapshot(sessions: [], messages: [])

    /// 只保留某个来源（上报网站时只传 Claude 的，网站还不区分来源）
    func only(_ source: Source) -> LocalSnapshot {
        LocalSnapshot(sessions: sessions.filter { $0.source == source },
                      messages: messages.filter { $0.source == source },
                      codexLimits: source == .codex ? codexLimits : nil)
    }

    var hasCodex: Bool { codexLimits != nil || messages.contains { $0.source == .codex } }

    func tokens(since: Date) -> (tokens: TokenCount, requests: Int) {
        var t = TokenCount(), n = 0
        for m in messages where m.ts >= since { t += m.tokens; n += 1 }
        return (t, n)
    }

    func sessions(since: Date) -> [SessionSummary] {
        sessions.filter { $0.end >= since }
    }

    func projects(since: Date) -> [ProjectShare] {
        var by: [String: Int] = [:]
        for m in messages where m.ts >= since { by[m.project, default: 0] += m.tokens.total }
        return by.map { ProjectShare(project: $0.key, tokens: $0.value) }.sorted { $0.tokens > $1.tokens }
    }

    func models(since: Date) -> [ModelShare] {
        var by: [String: TokenCount] = [:]
        for m in messages where m.ts >= since { by[m.model, default: TokenCount()] += m.tokens }
        return by.map { ModelShare(model: $0.key, tokens: $0.value) }.sorted { $0.tokens.total > $1.tokens.total }
    }

    /// 最近 days 天每天的 token（北京时间自然日），最早的在前。
    func daily(days: Int, now: Date) -> [(day: Date, tokens: TokenCount)] {
        let cal = Fmt.calendar
        let today = cal.startOfDay(for: now)
        var buckets: [Date: TokenCount] = [:]
        let start = cal.date(byAdding: .day, value: -(days - 1), to: today)!
        for m in messages where m.ts >= start {
            buckets[cal.startOfDay(for: m.ts), default: TokenCount()] += m.tokens
        }
        return (0..<days).map { i in
            let d = cal.date(byAdding: .day, value: i, to: start)!
            return (d, buckets[d] ?? TokenCount())
        }
    }
}

// MARK: - 扫描 ~/.claude/projects 下的会话日志

private struct FileStats {
    var sessionId: String
    var isSubagent: Bool
    var cwd: String?
    var aiTitle: String?
    var customTitle: String?
    var lastPrompt: String?
    var messages: [MessageUsage] = []
}

actor SessionScanner {
    private let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")
    /// 按 文件路径 缓存解析结果，文件没变（修改时间+大小相同）就不重新读。
    private var cache: [String: (mtime: Date, size: Int, stats: FileStats)] = [:]

    private var codexCache: [String: (mtime: Date, size: Int, stats: CodexFile)] = [:]

    func scan(days: Int = 31) -> LocalSnapshot {
        let claude = scanClaude(days: days)
        let codex = scanCodex(days: days)
        var sessions = claude.sessions + codex.sessions
        var messages = claude.messages + codex.messages
        sessions.sort { $0.end > $1.end }
        messages.sort { $0.ts < $1.ts }
        return LocalSnapshot(sessions: sessions, messages: messages, codexLimits: codex.limits)
    }

    private func scanCodex(days: Int) -> (sessions: [SessionSummary], messages: [MessageUsage], limits: CodexLimits?) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        let files = CodexLogs.files(modifiedAfter: cutoff)
        let imported = CodexLogs.importedThreadIDs()
        let titles = CodexLogs.threadNames()
        var fresh: [String: (mtime: Date, size: Int, stats: CodexFile)] = [:]
        for f in files {
            let path = f.url.path
            if let c = codexCache[path], c.mtime == f.mtime, c.size == f.size {
                fresh[path] = c
            } else {
                fresh[path] = (f.mtime, f.size, CodexLogs.parse(url: f.url))
            }
        }
        codexCache = fresh
        // 额度取所有文件里最新的一条（不管是不是导入的会话，导入的文件里没有额度）
        let limits = fresh.values.compactMap(\.stats.limits).max { $0.observedAt < $1.observedAt }
        let native = fresh.values.map(\.stats).filter { !$0.id.isEmpty && !imported.contains($0.id) }
        return CodexLogs.build(native, titles: titles, cutoff: cutoff, limits: limits)
    }

    private func scanClaude(days: Int) -> LocalSnapshot {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]

        var files: [(url: URL, sid: String, sub: Bool, mtime: Date, size: Int)] = []
        func consider(_ url: URL, sid: String, sub: Bool) {
            guard url.pathExtension == "jsonl",
                  let v = try? url.resourceValues(forKeys: Set(keys)),
                  let mtime = v.contentModificationDate, mtime >= cutoff
            else { return }
            files.append((url, sid, sub, mtime, v.fileSize ?? 0))
        }

        let projects = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for project in projects {
            let entries = (try? fm.contentsOfDirectory(at: project, includingPropertiesForKeys: keys)) ?? []
            for e in entries {
                if e.pathExtension == "jsonl" {
                    consider(e, sid: e.deletingPathExtension().lastPathComponent, sub: false)
                } else if (try? e.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    let subdir = e.appendingPathComponent("subagents")
                    for f in (try? fm.contentsOfDirectory(at: subdir, includingPropertiesForKeys: keys)) ?? [] {
                        consider(f, sid: e.lastPathComponent, sub: true)
                    }
                }
            }
        }

        var fresh: [String: (mtime: Date, size: Int, stats: FileStats)] = [:]
        for f in files {
            let path = f.url.path
            if let c = cache[path], c.mtime == f.mtime, c.size == f.size {
                fresh[path] = c
            } else {
                let stats = Self.parse(url: f.url, sid: f.sid, sub: f.sub)
                fresh[path] = (f.mtime, f.size, stats)
            }
        }
        cache = fresh

        return Self.build(fresh.values.map(\.stats), cutoff: cutoff)
    }

    private static func build(_ all: [FileStats], cutoff: Date) -> LocalSnapshot {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var groups: [String: [FileStats]] = [:]
        for f in all { groups[f.sessionId, default: []].append(f) }

        var sessions: [SessionSummary] = []
        var messages: [MessageUsage] = []

        for (sid, files) in groups {
            let msgs = files.flatMap(\.messages).filter { $0.ts >= cutoff }
            guard !msgs.isEmpty else { continue }

            let main = files.first { !$0.isSubagent }
            var tokens = TokenCount()
            var outByModel: [String: Int] = [:]
            for m in msgs {
                tokens += m.tokens
                outByModel[m.model, default: 0] += m.tokens.output + m.tokens.input
            }
            let subTokens = files.filter(\.isSubagent).flatMap(\.messages).reduce(0) { $0 + $1.tokens.total }
            let cwd = main?.cwd ?? files.compactMap(\.cwd).first
            let project: String = {
                guard let cwd else { return L("未知目录", "Unknown folder", ja: "不明なフォルダ", ko: "알 수 없는 폴더") }
                return cwd == home ? "~" : (cwd as NSString).lastPathComponent
            }()
            messages.append(contentsOf: msgs.map { var m = $0; m.project = project; return m })
            var title = main?.customTitle ?? main?.aiTitle ?? main?.lastPrompt ?? L("（无标题）", "(untitled)", ja: "（無題）", ko: "(제목 없음)")
            title = title.replacingOccurrences(of: "\n", with: " ")
            if title.count > 60 { title = String(title.prefix(60)) + "…" }

            sessions.append(SessionSummary(
                id: sid,
                project: project,
                cwd: cwd,
                title: title,
                start: msgs.map(\.ts).min()!,
                end: msgs.map(\.ts).max()!,
                tokens: tokens,
                subagentTokens: subTokens,
                requests: main?.messages.count ?? 0,
                mainModel: outByModel.max { $0.value < $1.value }?.key ?? "?"))
        }

        sessions.sort { $0.end > $1.end }
        messages.sort { $0.ts < $1.ts }
        return LocalSnapshot(sessions: sessions, messages: messages)
    }

    // MARK: 单个文件解析

    /// 耗时只在 0.2 秒到 15 分钟之间才可信（太短是时间戳误差，太长是中间等了人）
    static func sane(_ t: TimeInterval) -> TimeInterval? { (0.2...900).contains(t) ? t : nil }

    static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let isoPlain = ISO8601DateFormatter()

    private static let needleAssistant = Array(#""type":"assistant""#.utf8)
    private static let needleAITitle = Array(#""type":"ai-title""#.utf8)
    private static let needleCustomTitle = Array(#""type":"custom-title""#.utf8)
    private static let needleLastPrompt = Array(#""type":"last-prompt""#.utf8)
    private static let needleUser = Array(#""type":"user""#.utf8)
    private static let needleTimestamp = Array(#""timestamp":""#.utf8)

    /// 不做 JSON 解析，直接从一行里取出 "timestamp":"…" 的值（用户消息行可能是很大的工具结果）
    static func quickTimestamp(_ p: UnsafeRawPointer, _ len: Int) -> Date? {
        guard let hit = needleTimestamp.withUnsafeBytes({ n in memmem(p, len, n.baseAddress, n.count) }) else { return nil }
        let start = UnsafeRawPointer(hit) + needleTimestamp.count
        let remain = len - (start - p)
        guard remain > 0 else { return nil }
        var n = 0
        while n < min(remain, 40), start.load(fromByteOffset: n, as: UInt8.self) != 0x22 { n += 1 }
        guard let str = String(bytes: UnsafeRawBufferPointer(start: start, count: n), encoding: .utf8) else { return nil }
        return isoFrac.date(from: str) ?? isoPlain.date(from: str)
    }

    /// 日志文件可能有几十 MB，大部分行（工具结果、请求快照）用不到。
    /// 先用 memmem 按字节找类型标记，命中了才做 JSON 解析。
    private static func parse(url: URL, sid: String, sub: Bool) -> FileStats {
        var st = FileStats(sessionId: sid, isSubagent: sub)
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return st }
        // 同一条回复按内容块拆成多行：key → (在 messages 里的下标, 请求开始时间)
        var seen: [String: (index: Int, start: Date?)] = [:]
        var lastUserTs: Date?

        func contains(_ p: UnsafeRawPointer, _ len: Int, _ needle: [UInt8]) -> Bool {
            needle.withUnsafeBytes { n in memmem(p, len, n.baseAddress, n.count) != nil }
        }

        func handle(_ p: UnsafeRawPointer, _ len: Int) {
            let isAssistant = contains(p, len, needleAssistant)
            let isAI = !isAssistant && contains(p, len, needleAITitle)
            let isCustom = !isAssistant && !isAI && contains(p, len, needleCustomTitle)
            let isPrompt = !isAssistant && !isAI && !isCustom && contains(p, len, needleLastPrompt)
            if !isAssistant && !isAI && !isCustom && !isPrompt {
                // 用户消息 / 工具结果：只记时间，作为下一次回复的开始
                if contains(p, len, needleUser), let ts = quickTimestamp(p, len) { lastUserTs = ts }
                return
            }

            let line = Data(bytes: p, count: len)
            guard let d = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = d["type"] as? String else { return }

            switch type {
            case "assistant":
                guard let msg = d["message"] as? [String: Any],
                      let usage = msg["usage"] as? [String: Any],
                      let model = msg["model"] as? String, !model.hasPrefix("<"),
                      let tsStr = d["timestamp"] as? String,
                      let ts = isoFrac.date(from: tsStr) ?? isoPlain.date(from: tsStr)
                else { return }
                // 同一条回复按内容块拆成多行，用量相同，按 message.id + requestId 去重；
                // 结束时间取最后一行的时间
                let key = (msg["id"] as? String ?? "") + "|" + (d["requestId"] as? String ?? "")
                if key != "|", let prev = seen[key] {
                    if let start = prev.start { st.messages[prev.index].duration = Self.sane(ts.timeIntervalSince(start)) }
                    return
                }
                let start = lastUserTs.flatMap { $0 <= ts ? $0 : nil }
                if key != "|" { seen[key] = (st.messages.count, start) }
                func int(_ k: String) -> Int { (usage[k] as? NSNumber)?.intValue ?? 0 }
                let t = TokenCount(input: int("input_tokens"),
                                   output: int("output_tokens"),
                                   cacheRead: int("cache_read_input_tokens"),
                                   cacheWrite: int("cache_creation_input_tokens"))
                st.messages.append(MessageUsage(ts: ts, model: model, tokens: t,
                                                duration: start.flatMap { Self.sane(ts.timeIntervalSince($0)) }))
                if st.cwd == nil { st.cwd = d["cwd"] as? String }
            case "ai-title":
                if let t = d["aiTitle"] as? String, !t.isEmpty { st.aiTitle = t }
            case "custom-title":
                if let t = (d["customTitle"] ?? d["title"]) as? String, !t.isEmpty { st.customTitle = t }
            case "last-prompt":
                if let t = d["lastPrompt"] as? String, !t.isEmpty { st.lastPrompt = t }
            default:
                break
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
        return st
    }
}
