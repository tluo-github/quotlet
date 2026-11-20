import Foundation

// Quotlet Cloud hooks 运行时：
// 1. `--hook` 命令行分支：从 stdin 读最多 64KB JSON，只保留必要字段，追加一行到 events.jsonl，
//    超过 1MB 自动轮转，不联网、不打印 stdout、永远 exit 0（目标 <20ms）。
// 2. App 内 DispatchSource 监听 events.jsonl，将 hook 事件映射成精确会话状态，状态变化立即上报。
// 3. 10 分钟兜底规则：处于 running 但 10 分钟无任何事件/日志变化时自动降级为 idle。

struct HookEventRecord: Codable, Equatable {
    let source: String
    let hookEventName: String
    let sessionId: String
    let cwd: String?
    let notificationType: String?
    let message: String?
    let prompt: String?
    let toolName: String?
    let ts: Int64

    enum CodingKeys: String, CodingKey {
        case source
        case hookEventName = "hook_event_name"
        case sessionId = "session_id"
        case cwd
        case notificationType = "notification_type"
        case message
        case prompt
        case toolName = "tool_name"
        case ts
    }
}

struct HookSessionState: Equatable {
    let sessionId: String
    let source: String
    let status: String          // idle | running | waiting | done | ended
    let detail: String?
    let isPromptExcerpt: Bool
    let cwd: String?
    let updatedAt: Date
    /// true 表示已收到 SessionStart 且尚未收到 SessionEnd（终端交互会话处于打开状态）
    let interactiveOpen: Bool

    /// 兜底规则：running 状态超过 10 分钟无新事件则回落为 idle
    func effectiveStatus(now: Date, staleInterval: TimeInterval = 600) -> String {
        if status == "running", now.timeIntervalSince(updatedAt) >= staleInterval {
            return "idle"
        }
        return status
    }
}

enum HookStatusMapper {
    struct Mapped {
        let status: String
        let detail: String?
        let isPromptExcerpt: Bool
        let interactiveOpen: Bool
    }

    static func map(_ record: HookEventRecord) -> Mapped? {
        switch record.hookEventName {
        // Claude Code + Antigravity CLI 通用
        case "SessionStart":
            return Mapped(status: "idle", detail: nil, isPromptExcerpt: false, interactiveOpen: true)
        case "UserPromptSubmit", "BeforeAgent":
            return Mapped(status: "running", detail: record.prompt, isPromptExcerpt: true, interactiveOpen: true)
        case "Notification":
            let nt = (record.notificationType ?? "").lowercased()
            let msg = record.message
            // Claude Code 权限弹窗为 permission_prompt；其他通知若包含授权提示也归类为 waiting
            if nt == "permission_prompt" || nt.contains("permission") || nt.contains("approval") || nt.contains("confirm")
                || (record.source == "gemini" && msg != nil) {
                return Mapped(status: "waiting", detail: msg, isPromptExcerpt: false, interactiveOpen: true)
            }
            return nil
        case "PostToolUse", "AfterTool":
            return Mapped(status: "running", detail: nil, isPromptExcerpt: false, interactiveOpen: true)
        case "Stop", "AfterAgent":
            return Mapped(status: "done", detail: nil, isPromptExcerpt: false, interactiveOpen: true)
        case "SessionEnd":
            return Mapped(status: "ended", detail: nil, isPromptExcerpt: false, interactiveOpen: false)
        default:
            return nil
        }
    }
}

enum HookCLI {
    static let maxStdinBytes = 65_536
    static let rotateBytes: UInt64 = 1_048_576

    static var defaultEventsURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Quotlet", isDirectory: true)
            .appendingPathComponent("events.jsonl")
    }

    /// 供 App.swift 在 SwiftUI 启动前调用。永远不抛出、不打印 stdout、不联网。
    static func run(arguments: [String] = CommandLine.arguments,
                    stdinData: Data? = nil,
                    eventsURL: URL = defaultEventsURL,
                    now: Date = Date()) {
        let sourceOverride = parseSourceOverride(arguments)
        let data = stdinData ?? readStdinUpTo(limit: maxStdinBytes)
        guard let record = parseRecord(from: data, sourceOverride: sourceOverride, now: now) else { return }
        append(record, to: eventsURL)
    }

    static func parseSourceOverride(_ arguments: [String]) -> String? {
        guard let idx = arguments.firstIndex(of: "--hook-source"), idx + 1 < arguments.count else { return nil }
        let val = arguments[idx + 1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["claude", "codex", "gemini"].contains(val) ? val : nil
    }

    static func parseRecord(from data: Data, sourceOverride: String? = nil, now: Date = Date()) -> HookEventRecord? {
        guard !data.isEmpty,
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let eventName = cleanString(raw["hook_event_name"] ?? raw["event"], maxLength: 64),
              let sessionId = cleanString(raw["session_id"] ?? raw["sessionId"], maxLength: 128) else {
            return nil
        }
        let source: String = {
            if let sourceOverride { return sourceOverride }
            if ["BeforeAgent", "AfterAgent", "AfterTool"].contains(eventName) { return "gemini" }
            return "claude"
        }()
        let prompt = cleanString(raw["prompt"] ?? raw["user_prompt"], maxLength: 80)
        let message = cleanString(raw["message"] ?? raw["notification"], maxLength: 200)
        return HookEventRecord(
            source: source,
            hookEventName: eventName,
            sessionId: sessionId,
            cwd: cleanString(raw["cwd"], maxLength: 512),
            notificationType: cleanString(raw["notification_type"] ?? raw["notificationType"], maxLength: 64),
            message: message,
            prompt: prompt,
            toolName: cleanString(raw["tool_name"] ?? raw["toolName"], maxLength: 64),
            ts: Int64((now.timeIntervalSince1970 * 1000).rounded())
        )
    }

    static func append(_ record: HookEventRecord, to url: URL, rotateAt: UInt64 = rotateBytes) {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        if let attrs = try? fm.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? UInt64,
           size >= rotateAt {
            let rotated = url.deletingPathExtension().appendingPathExtension("jsonl.1")
            try? fm.removeItem(at: rotated)
            try? fm.moveItem(at: url, to: rotated)
        }

        guard var line = try? JSONEncoder().encode(record) else { return }
        line.append(0x0A)

        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let fh = try? FileHandle(forWritingTo: url) else { return }
        defer { try? fh.close() }
        _ = try? fh.seekToEnd()
        try? fh.write(contentsOf: line)
    }

    private static func readStdinUpTo(limit: Int) -> Data {
        var result = Data()
        let fd = FileHandle.standardInput.fileDescriptor
        var buf = [UInt8](repeating: 0, count: 4096)
        while result.count < limit {
            let remaining = min(buf.count, limit - result.count)
            let n = read(fd, &buf, remaining)
            if n <= 0 { break }
            result.append(buf, count: n)
        }
        return result
    }

    private static func cleanString(_ value: Any?, maxLength: Int) -> String? {
        guard let s = value as? String else { return nil }
        let trimmed = s.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLength))
    }
}

/// 监听 events.jsonl 增量写入，维护会话精确状态并回调状态变化。
final class HookEventWatcher {
    private let eventsURL: URL
    private let queue = DispatchQueue(label: "app.quotlet.hook-events", qos: .utility)
    private let onTransition: (HookSessionState, HookEventRecord) -> Void

    private var dirSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var fileFD: Int32 = -1
    private var dirFD: Int32 = -1
    private var currentInode: UInt64 = 0
    private var offset: UInt64 = 0
    private var remainder = Data()
    private var states: [String: HookSessionState] = [:]

    init(eventsURL: URL = HookCLI.defaultEventsURL,
         onTransition: @escaping (HookSessionState, HookEventRecord) -> Void) {
        self.eventsURL = eventsURL
        self.onTransition = onTransition
    }

    deinit {
        stop()
    }

    func start() {
        queue.async { [weak self] in
            self?.setupWatchers()
        }
    }

    func stop() {
        queue.sync {
            teardownFileSource()
            if let dirSource {
                dirSource.cancel()
                self.dirSource = nil
            }
            if dirFD >= 0 {
                close(dirFD)
                dirFD = -1
            }
        }
    }

    func snapshotStates() -> [String: HookSessionState] {
        queue.sync { states }
    }

    /// 供测试或手动触发增量读取
    func drainNow() {
        queue.sync { readAvailableBytes() }
    }

    private func setupWatchers() {
        let dir = eventsURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: eventsURL.path) {
            FileManager.default.createFile(atPath: eventsURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }

        // 首次启动跳到文件末尾，只处理运行后产生的新事件（避免把几天前的旧事件当作刚发生重发）
        if let attrs = try? FileManager.default.attributesOfItem(atPath: eventsURL.path) {
            offset = (attrs[.size] as? UInt64) ?? 0
            currentInode = (attrs[.systemFileNumber] as? UInt64) ?? 0
        }

        openFileSource()

        // 监听父目录，处理文件轮转 / 重建
        dirFD = open(dir.path, O_EVTONLY)
        if dirFD >= 0 {
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: dirFD, eventMask: [.write, .rename], queue: queue)
            src.setEventHandler { [weak self] in
                self?.reconcileFileRotation()
                self?.readAvailableBytes()
            }
            src.resume()
            dirSource = src
        }
    }

    private func openFileSource() {
        teardownFileSource()
        fileFD = open(eventsURL.path, O_EVTONLY)
        guard fileFD >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileFD, eventMask: [.write, .extend, .rename, .delete], queue: queue)
        src.setEventHandler { [weak self] in
            self?.reconcileFileRotation()
            self?.readAvailableBytes()
        }
        src.resume()
        fileSource = src
    }

    private func teardownFileSource() {
        if let fileSource {
            fileSource.cancel()
            self.fileSource = nil
        }
        if fileFD >= 0 {
            close(fileFD)
            fileFD = -1
        }
    }

    private func reconcileFileRotation() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: eventsURL.path) else { return }
        let inode = (attrs[.systemFileNumber] as? UInt64) ?? 0
        let size = (attrs[.size] as? UInt64) ?? 0
        if inode != currentInode || size < offset {
            currentInode = inode
            offset = 0
            remainder.removeAll(keepingCapacity: false)
            openFileSource()
        }
    }

    private func readAvailableBytes() {
        guard let fh = try? FileHandle(forReadingFrom: eventsURL) else { return }
        defer { try? fh.close() }
        do {
            try fh.seek(toOffset: offset)
            let chunk = try fh.readToEnd() ?? Data()
            guard !chunk.isEmpty else { return }
            offset += UInt64(chunk.count)
            remainder.append(chunk)
        } catch {
            return
        }

        let decoder = JSONDecoder()
        while let nl = remainder.firstIndex(of: 0x0A) {
            let line = remainder[..<nl]
            remainder.removeSubrange(...nl)
            guard !line.isEmpty,
                  let record = try? decoder.decode(HookEventRecord.self, from: Data(line)) else { continue }
            apply(record)
        }
    }

    private func apply(_ record: HookEventRecord) {
        guard let mapped = HookStatusMapper.map(record) else { return }
        let prev = states[record.sessionId]
        let next = HookSessionState(
            sessionId: record.sessionId,
            source: record.source,
            status: mapped.status,
            detail: mapped.detail,
            isPromptExcerpt: mapped.isPromptExcerpt,
            cwd: record.cwd ?? prev?.cwd,
            updatedAt: Date(timeIntervalSince1970: Double(record.ts) / 1000.0),
            interactiveOpen: mapped.interactiveOpen
        )
        states[record.sessionId] = next

        // PostToolUse 触发频繁：仅当状态真正改变（或等待授权内容变化）时回调上报
        let statusChanged = prev?.status != next.status
        let waitingDetailChanged = next.status == "waiting" && prev?.detail != next.detail
        let newPrompt = record.hookEventName == "UserPromptSubmit" || record.hookEventName == "BeforeAgent"
        if statusChanged || waitingDetailChanged || newPrompt {
            onTransition(next, record)
        }
    }
}
