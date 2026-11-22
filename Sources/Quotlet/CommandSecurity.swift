import AppKit
import Foundation

// 远程指令安全校验与本地完整指令历史（docs/cloud-design.md 第 7 节）：
// 1. 仅允许在近 30 天内出现过的项目目录中执行（Mac 自己从本机 30 天会话解析 cwd，不信任远端路径）
// 2. 避免干扰正在终端里交互的会话：检测到活跃交互会话时拒绝 resume，提示改用 --fork-session
// 3. 可选本机弹窗确认（NSAlert）
// 4. 所有收到的指令都完整落盘记录在 ~/Library/Application Support/Quotlet/commands-history.json

enum CommandExecutionMode: String, Codable, Equatable {
    case new
    case resume
    case fork
}

struct RemoteCommand: Codable, Equatable, Identifiable {
    let id: String
    let deviceId: String
    let provider: String       // claude | codex | gemini
    let mode: String           // new | resume | fork
    let sessionId: String?
    let project: String?
    let prompt: String
    let status: String
    let createdAt: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case deviceId = "device_id"
        case provider
        case mode
        case sessionId = "session_id"
        case project
        case prompt
        case status
        case createdAt = "created_at"
    }

    var source: Source? { Source(rawValue: provider.lowercased()) }
    var executionMode: CommandExecutionMode? { CommandExecutionMode(rawValue: mode.lowercased()) }
}

struct CommandHistoryEntry: Codable, Equatable, Identifiable {
    let id: String
    let provider: String
    let mode: String
    let sessionId: String?
    let project: String?
    var resolvedCwd: String?
    let prompt: String
    var status: String
    var result: String?
    var error: String?
    var resultSessionId: String?
    let receivedAt: Date
    var finishedAt: Date?
}

final class CommandHistoryStore {
    static let shared = CommandHistoryStore()

    private let fileURL: URL
    private let maxEntries: Int
    private let lock = NSLock()
    private var entries: [CommandHistoryEntry] = []

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Quotlet", isDirectory: true)
            .appendingPathComponent("commands-history.json")
    }

    init(fileURL: URL = defaultURL, maxEntries: Int = 500) {
        self.fileURL = fileURL
        self.maxEntries = maxEntries
        self.entries = Self.load(from: fileURL)
    }

    func all() -> [CommandHistoryEntry] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }

    func upsert(_ entry: CommandHistoryEntry) {
        lock.lock()
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
        } else {
            entries.insert(entry, at: 0)
            if entries.count > maxEntries {
                entries.removeLast(entries.count - maxEntries)
            }
        }
        let snapshot = entries
        lock.unlock()
        Self.save(snapshot, to: fileURL)
    }

    func remove(id: String) {
        lock.lock()
        let before = entries.count
        entries.removeAll { $0.id == id }
        let snapshot = entries
        let changed = entries.count != before
        lock.unlock()
        if changed {
            Self.save(snapshot, to: fileURL)
        }
    }

    func clearFinished() {
        let active: Set<String> = ["queued", "delivered", "running"]
        lock.lock()
        let before = entries.count
        entries.removeAll { !active.contains($0.status) }
        let snapshot = entries
        let changed = entries.count != before
        lock.unlock()
        if changed {
            Self.save(snapshot, to: fileURL)
        }
    }

    private static func load(from url: URL) -> [CommandHistoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return (try? decoder.decode([CommandHistoryEntry].self, from: data)) ?? []
    }

    private static func save(_ entries: [CommandHistoryEntry], to url: URL) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        do {
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }
}

enum CommandValidationResult: Equatable {
    case approved(source: Source, mode: CommandExecutionMode, cwd: String, cliPath: String)
    case rejected(_ reason: String)
}

struct CommandSecurityValidator {
    static let allowedProjectWindow: TimeInterval = 30 * 86400

    typealias InteractiveChecker = (_ sessionId: String, _ local: LocalSnapshot?, _ now: Date) -> Bool

    let fileManager: FileManager
    let isInteractiveActive: InteractiveChecker

    init(fileManager: FileManager = .default,
         isInteractiveActive: @escaping InteractiveChecker = Self.defaultInteractiveCheck) {
        self.fileManager = fileManager
        self.isInteractiveActive = isInteractiveActive
    }

    func validate(command: RemoteCommand,
                  capabilities: DeviceCapabilities,
                  local: LocalSnapshot?,
                  now: Date = Date()) -> CommandValidationResult {
        guard let source = command.source else {
            return .rejected("不支持的模型提供方：\(command.provider)")
        }
        guard let mode = command.executionMode else {
            return .rejected("不支持的执行模式：\(command.mode)")
        }
        guard !command.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .rejected("指令内容为空")
        }

        // 1. 校验本机能力
        let cap = capabilities[source]
        guard cap.available, let cliPath = cap.cliPath, !cliPath.isEmpty else {
            return .rejected(cap.note ?? "本机未检测到 \(source.title) CLI")
        }
        if mode == .new && !cap.supportsNew {
            return .rejected(cap.note ?? "\(source.title) 不支持新建非交互会话")
        }
        if mode == .resume && !cap.supportsResume {
            return .rejected(cap.note ?? "\(source.title) 不支持无头续聊，请改用新建会话")
        }
        if mode == .fork && !cap.supportsFork {
            return .rejected(cap.note ?? "\(source.title) 不支持分支续聊")
        }
        if (mode == .resume || mode == .fork) && (command.sessionId?.isEmpty ?? true) {
            return .rejected("续聊或分支模式缺少 session_id")
        }

        // 2. 安全边界：只允许在近 30 天出现过的项目目录中执行
        guard let resolvedCwd = resolveAllowedDirectory(command: command, local: local, now: now) else {
            return .rejected("目标项目目录未在近 30 天会话中出现或目录已不存在，已拒绝执行。")
        }

        // 3. 安全边界：避免干扰正在终端里交互的会话
        if mode == .resume, let sid = command.sessionId, isInteractiveActive(sid, local, now) {
            return .rejected("该会话正在终端交互中，为避免冲突已拒绝续聊，请改用分支会话（--fork-session）或新建会话。")
        }

        return .approved(source: source, mode: mode, cwd: resolvedCwd, cliPath: cliPath)
    }

    /// 仅从近 30 天内本机扫描到的会话记录中解析并校验项目目录，绝不接受外部拼装路径。
    func resolveAllowedDirectory(command: RemoteCommand, local: LocalSnapshot?, now: Date = Date()) -> String? {
        guard let local else { return nil }
        let cutoff = now.addingTimeInterval(-Self.allowedProjectWindow)
        let recent = local.sessions.filter { $0.end >= cutoff && $0.cwd != nil }

        var rawCwd: String?
        if let sid = command.sessionId, !sid.isEmpty {
            let prefix = command.provider.lowercased() + "-"
            let stripped = sid.hasPrefix(prefix) ? String(sid.dropFirst(prefix.count)) : sid
            rawCwd = recent.first(where: {
                $0.id == sid || $0.id == stripped || $0.id == prefix + stripped
            })?.cwd
        }
        if rawCwd == nil, let project = command.project?.trimmingCharacters(in: .whitespacesAndNewlines), !project.isEmpty {
            // 防止目录名里包含路径遍历字符
            guard !project.contains("/"), !project.contains("\\"), project != "..", project != "." else {
                return nil
            }
            rawCwd = recent.first(where: { $0.project == project })?.cwd
        }

        guard let candidate = rawCwd, !candidate.isEmpty else { return nil }
        let canonical = URL(fileURLWithPath: candidate).standardizedFileURL.resolvingSymlinksInPath().path
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: canonical, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return canonical
    }

    /// 综合判断该会话是否正在终端里交互：
    /// 1) Hook 生命周期处于开启状态（SessionStart 后未收到 SessionEnd，且不是 Quotlet 自己启动的）
    /// 2) LiveActivity 显示 60 秒内正在生成或调用工具
    /// 3) 本机 TTY 终端进程命令行中正在 `--resume <sessionId>`
    static func defaultInteractiveCheck(sessionId: String, local: LocalSnapshot?, now: Date) -> Bool {
        if let local {
            for act in local.liveActivities {
                if act.id.contains(sessionId),
                   (act.phase == .generating || act.phase == .tools),
                   now.timeIntervalSince(act.updatedAt) < 60 {
                    return true
                }
            }
        }
        return hasInteractiveTTYProcess(sessionId: sessionId)
    }

    static func hasInteractiveTTYProcess(sessionId: String) -> Bool {
        guard let out = CLICapabilityProber.runSync(executable: "/bin/ps", arguments: ["-eo", "tty,args"], timeout: 1.5),
              out.exitCode == 0 else {
            return false
        }
        return detectTTYSessionInProcessList(out.stdout, sessionId: sessionId)
    }

    static func detectTTYSessionInProcessList(_ psOutput: String, sessionId: String) -> Bool {
        for line in psOutput.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            let tty = String(trimmed[..<space])
            guard tty != "??", tty != "TTY", !tty.isEmpty else { continue }
            let args = String(trimmed[space...])
            if args.contains(sessionId) && (args.contains("claude") || args.contains("codex") || args.contains("agy")) {
                return true
            }
        }
        return false
    }

    @MainActor
    static func requestLocalConfirmation(command: RemoteCommand, resolvedCwd: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L("确认执行远程指令？", "Run remote command?", ja: "リモートコマンドを実行しますか？", ko: "원격 명령을 실행할까요?")
        let preview = command.prompt.count > 260 ? String(command.prompt.prefix(260)) + "…" : command.prompt
        let providerTitle = command.source?.title ?? command.provider
        alert.informativeText = """
        \(L("模型", "Provider", ja: "プロバイダー", ko: "제공자")): \(providerTitle) (\(command.mode))
        \(L("目录", "Folder", ja: "フォルダ", ko: "폴더")): \(resolvedCwd)

        \(preview)
        """
        alert.addButton(withTitle: L("允许执行", "Allow", ja: "許可して実行", ko: "실행 허용"))
        alert.addButton(withTitle: L("拒绝", "Reject", ja: "拒否", ko: "거부"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
