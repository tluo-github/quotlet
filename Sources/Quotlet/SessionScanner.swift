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

struct MessageUsage {
    let ts: Date
    let model: String
    let tokens: TokenCount
    var project: String = ""
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

    static let empty = LocalSnapshot(sessions: [], messages: [])

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

    func scan(days: Int = 31) -> LocalSnapshot {
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

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    private static let needleAssistant = Array(#""type":"assistant""#.utf8)
    private static let needleAITitle = Array(#""type":"ai-title""#.utf8)
    private static let needleCustomTitle = Array(#""type":"custom-title""#.utf8)
    private static let needleLastPrompt = Array(#""type":"last-prompt""#.utf8)

    /// 日志文件可能有几十 MB，大部分行（工具结果、请求快照）用不到。
    /// 先用 memmem 按字节找类型标记，命中了才做 JSON 解析。
    private static func parse(url: URL, sid: String, sub: Bool) -> FileStats {
        var st = FileStats(sessionId: sid, isSubagent: sub)
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return st }
        var seen = Set<String>()

        func contains(_ p: UnsafeRawPointer, _ len: Int, _ needle: [UInt8]) -> Bool {
            needle.withUnsafeBytes { n in memmem(p, len, n.baseAddress, n.count) != nil }
        }

        func handle(_ p: UnsafeRawPointer, _ len: Int) {
            let isAssistant = contains(p, len, needleAssistant)
            let isAI = !isAssistant && contains(p, len, needleAITitle)
            let isCustom = !isAssistant && !isAI && contains(p, len, needleCustomTitle)
            let isPrompt = !isAssistant && !isAI && !isCustom && contains(p, len, needleLastPrompt)
            guard isAssistant || isAI || isCustom || isPrompt else { return }

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
                // 同一条回复按内容块拆成多行，用量重复，按 message.id + requestId 去重
                let key = (msg["id"] as? String ?? "") + "|" + (d["requestId"] as? String ?? "")
                if key != "|" {
                    if seen.contains(key) { return }
                    seen.insert(key)
                }
                func int(_ k: String) -> Int { (usage[k] as? NSNumber)?.intValue ?? 0 }
                let t = TokenCount(input: int("input_tokens"),
                                   output: int("output_tokens"),
                                   cacheRead: int("cache_read_input_tokens"),
                                   cacheWrite: int("cache_creation_input_tokens"))
                st.messages.append(MessageUsage(ts: ts, model: model, tokens: t))
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
