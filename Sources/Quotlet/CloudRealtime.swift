import Combine
import Foundation

// 二期实时通道与远程指令调度器：
// - Mac 与 Worker UserHub DO 保持 WebSocket 长连接（/api/ws），自动重连与心跳保活
// - 收到远程指令后按安全边界校验（仅本机手动开启、近 30 天项目目录、避免冲突交互会话、可选本机确认）
// - 串行执行指令并实时回报进度与摘要（POST /api/commands/:id/status）
// - 退出登录时自动关闭远程指令并断开 WebSocket

struct RemoteLogEntry: Identifiable, Equatable {
    enum Level: String {
        case info, ok, warn, error
    }
    let id = UUID()
    let ts: Date
    let level: Level
    let category: String   // WS | CMD | CAP | API
    let message: String
}

@MainActor
final class RemoteCommandManager: ObservableObject {
    static let shared = RemoteCommandManager()

    enum Key {
        static let enabled = "cloudRemoteCommandsEnabled"
        static let confirm = "cloudRemoteConfirmRequired"
    }

    static var debugLogURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Quotlet", isDirectory: true)
            .appendingPathComponent("remote-debug.log")
    }

    /// 远程指令开关：默认关闭，仅能在本台 Mac 上登录后手动开启
    @Published private(set) var enabled: Bool = false
    /// 可选：每条指令执行前在 Mac 上弹窗确认
    @Published var requireConfirmation: Bool {
        didSet { UserDefaults.standard.set(requireConfirmation, forKey: Key.confirm) }
    }
    @Published private(set) var wsConnected: Bool = false
    @Published private(set) var lastWSConnectedAt: Date?
    @Published private(set) var wsRouteLabel: String = ""
    @Published private(set) var capabilities: DeviceCapabilities?
    @Published private(set) var activeCommandId: String?
    @Published private(set) var lastError: String?
    @Published private(set) var recentHistory: [CommandHistoryEntry] = []
    @Published private(set) var logs: [RemoteLogEntry] = []

    private var localSnapshot: LocalSnapshot?
    private var userWatch: AnyCancellable?
    private var wsTask: URLSessionWebSocketTask?
    private var wsSession: URLSession?
    private var wsRouteIndex = 0
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectDelay: TimeInterval = 2
    private var isConnecting = false

    /// 正在排队 / 执行中的指令去重集合与 FIFO 队列
    private var seenCommandIds: Set<String> = []
    private var queue: [RemoteCommand] = []
    private var processingQueue = false
    /// 记录当前由 Quotlet 远程执行器运行中的 sessionId，避免误判自己为终端交互冲突
    private var ownRunningSessionIds: Set<String> = []

    private let runner = SubprocessProviderRunner()

    private init() {
        UserDefaults.standard.register(defaults: [Key.enabled: false, Key.confirm: false])
        requireConfirmation = UserDefaults.standard.bool(forKey: Key.confirm)
        recentHistory = CommandHistoryStore.shared.all()

        // 仅在开发联调模式（-cloudDevToken + -cloudBaseURL + -cloudDevRemote YES）时允许启动即开启，不写入 UserDefaults
        let devArgs = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        let devAutoRemote = (devArgs["cloudDevToken"] as? String) != nil
            && UserDefaults.standard.string(forKey: "cloudBaseURL") != nil
            && ((devArgs["cloudDevRemote"] as? Bool) == true || (devArgs["cloudDevRemote"] as? String)?.uppercased() == "YES")

        enabled = devAutoRemote ? true : UserDefaults.standard.bool(forKey: Key.enabled)
        if !Cloud.shared.isSignedIn {
            enabled = false
        }

        if Cloud.isPreview { return }

        probeCapabilities()

        userWatch = Cloud.shared.$user
            .map { $0?.id }
            .removeDuplicates()
            .sink { [weak self] userId in
                Task { @MainActor in
                    guard let self else { return }
                    if userId == nil {
                        self.handleSignedOut()
                    } else {
                        self.syncDeviceStateToServer()
                        self.ensureConnectionState()
                    }
                }
            }
    }

    var shouldMaintainWebSocket: Bool {
        Cloud.shared.isSignedIn && !Cloud.isPreview && !Demo.enabled
            && !UserDefaults.standard.bool(forKey: "offline")
            && (enabled || CloudSync.shared.enabled)
    }

    func localUpdated(_ snapshot: LocalSnapshot) {
        localSnapshot = snapshot
    }

    func probeCapabilities() {
        log(.info, "CAP", "正在探测本机 Claude / Codex / Antigravity CLI…")
        Task.detached(priority: .utility) {
            let caps = CLICapabilityProber.probeAll()
            await MainActor.run {
                self.capabilities = caps
                self.log(.ok, "CAP", "探测完成：Claude=\(caps.claude.available ? (caps.claude.version ?? "✓") : "未安装") · Codex=\(caps.codex.available ? (caps.codex.version ?? "✓") : "未安装") · Antigravity=\(caps.gemini.available ? (caps.gemini.version ?? "✓") : "未安装")")
                CloudSync.shared.capabilitiesUpdated(caps)
                self.syncDeviceStateToServer()
            }
        }
    }

    func reconnectAndSync() {
        log(.info, "WS", "手动触发重连并拉取排队指令")
        reconnectDelay = 2
        disconnectWebSocket()
        syncDeviceStateToServer()
        ensureConnectionState()
        if enabled {
            Task { await reconcileQueuedCommands() }
        }
    }

    func clearLogs() {
        logs.removeAll()
        try? FileManager.default.removeItem(at: Self.debugLogURL)
    }

    private func log(_ level: RemoteLogEntry.Level, _ category: String, _ message: String) {
        let entry = RemoteLogEntry(ts: Date(), level: level, category: category, message: message)
        logs.insert(entry, at: 0)
        if logs.count > 250 {
            logs.removeLast(logs.count - 250)
        }
        NSLog("[cloud-%@] %@", category.lowercased(), message)
        Self.appendDebugLogLine(entry)
    }

    private static let logDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static func appendDebugLogLine(_ entry: RemoteLogEntry) {
        let url = debugLogURL
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if let attrs = try? fm.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? UInt64, size > 512_000 {
            let rotated = dir.appendingPathComponent("remote-debug.log.1")
            try? fm.removeItem(at: rotated)
            try? fm.moveItem(at: url, to: rotated)
        }
        let line = "[\(logDateFmt.string(from: entry.ts))] [\(entry.level.rawValue.uppercased())] [\(entry.category)] \(entry.message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let fh = try? FileHandle(forWritingTo: url) else { return }
        defer { try? fh.close() }
        _ = try? fh.seekToEnd()
        try? fh.write(contentsOf: data)
    }

    func setEnabled(_ on: Bool) {
        lastError = nil
        if on {
            guard Cloud.shared.isSignedIn else {
                enabled = false
                UserDefaults.standard.set(false, forKey: Key.enabled)
                return
            }
            enabled = true
            UserDefaults.standard.set(true, forKey: Key.enabled)
            probeCapabilities()
            syncDeviceStateToServer()
            ensureConnectionState()
        } else {
            enabled = false
            UserDefaults.standard.set(false, forKey: Key.enabled)
            syncDeviceStateToServer()
            ensureConnectionState()
        }
    }

    func handleSignedOut() {
        enabled = false
        UserDefaults.standard.set(false, forKey: Key.enabled)
        disconnectWebSocket()
        queue.removeAll()
        seenCommandIds.removeAll()
        lastError = nil
    }

    // MARK: 同步本机开关 / 能力 / 近期项目到服务端

    private func syncDeviceStateToServer() {
        guard let token = Cloud.shared.token, !Cloud.isPreview, !Demo.enabled,
              !UserDefaults.standard.bool(forKey: "offline") else { return }
        var body: [String: Any] = ["remote_enabled": enabled]
        if let capabilities {
            body["capabilities"] = capabilities.jsonObject()
        }
        if let local = localSnapshot {
            let cutoff = Date().addingTimeInterval(-CommandSecurityValidator.allowedProjectWindow)
            var seen = Set<String>()
            var projects: [String] = []
            for s in local.sessions where s.end >= cutoff && s.cwd != nil {
                let p = s.project.trimmingCharacters(in: .whitespacesAndNewlines)
                if !p.isEmpty && !p.contains("/") && !p.contains("\\") && seen.insert(p).inserted {
                    projects.append(p)
                    if projects.count >= 200 { break }
                }
            }
            body["projects"] = projects
        }
        let remoteFlag = enabled
        let projCount = (body["projects"] as? [String])?.count ?? 0
        Task {
            do {
                let (_, status) = try await Cloud.request("PATCH", "/api/devices/self", json: body, token: token)
                if status == 401 {
                    self.log(.error, "API", "PATCH /api/devices/self 返回 401，已退出登录")
                    Cloud.shared.handleUnauthorized()
                } else if !(200..<300).contains(status) {
                    self.log(.warn, "API", "PATCH /api/devices/self -> HTTP \(status) (remote=\(remoteFlag))")
                } else {
                    self.log(.ok, "API", "已同步设备状态：remote=\(remoteFlag ? "开" : "关")，近 30 天项目 \(projCount) 个")
                }
            } catch {
                self.log(.error, "API", "同步设备状态失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: WebSocket 实时通道

    func ensureConnectionState() {
        if shouldMaintainWebSocket {
            connectWebSocket()
        } else {
            disconnectWebSocket()
        }
    }

    private func webSocketURL() -> URL? {
        var comps = URLComponents(url: CloudConfig.base.appendingPathComponent("/api/ws"), resolvingAgainstBaseURL: false)
        if comps?.scheme == "https" { comps?.scheme = "wss" }
        else if comps?.scheme == "http" { comps?.scheme = "ws" }
        return comps?.url
    }

    private func connectWebSocket() {
        guard shouldMaintainWebSocket, let token = Cloud.shared.token, let url = webSocketURL() else { return }
        guard wsTask == nil, !isConnecting else { return }
        isConnecting = true
        reconnectTask?.cancel()
        reconnectTask = nil

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20

        let sessions = Network.sessions(for: url, allowFallback: true)
        let idx = sessions.isEmpty ? 0 : (wsRouteIndex % sessions.count)
        let session = sessions.isEmpty ? URLSession(configuration: .ephemeral) : sessions[idx]
        wsRouteLabel = (idx == 0 && sessions.count > 1) ? "代理" : "直连"
        let task = session.webSocketTask(with: req)
        wsSession = session
        wsTask = task
        task.resume()
        isConnecting = false
        log(.info, "WS", "正在连接 \(url.absoluteString)（\(wsRouteLabel)）")

        receiveLoop(for: task)
        startPingLoop(for: task)
    }

    private func disconnectWebSocket() {
        reconnectTask?.cancel()
        reconnectTask = nil
        pingTask?.cancel()
        pingTask = nil
        wsTask?.cancel(with: .normalClosure, reason: nil)
        wsTask = nil
        wsConnected = false
        isConnecting = false
    }

    private func startPingLoop(for task: URLSessionWebSocketTask) {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self, self.wsTask === task else { return }
                let msg = URLSessionWebSocketTask.Message.string(#"{"type":"ping"}"#)
                do {
                    try await task.send(msg)
                } catch {
                    self.handleSocketClosed(task, error: error)
                    return
                }
            }
        }
    }

    private func receiveLoop(for task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.wsTask === task else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleWSMessage(text)
                    case .data(let data):
                        self.handleWSMessage(String(decoding: data, as: UTF8.self))
                    @unknown default:
                        break
                    }
                    self.receiveLoop(for: task)
                case .failure(let error):
                    self.handleSocketClosed(task, error: error)
                }
            }
        }
    }

    private func handleSocketClosed(_ task: URLSessionWebSocketTask, error: Error) {
        guard wsTask === task else { return }
        wsTask = nil
        wsConnected = false
        wsRouteIndex += 1
        pingTask?.cancel()
        pingTask = nil
        log(.warn, "WS", "实时通道断开：\(error.localizedDescription)，\(Int(reconnectDelay))s 后重连")
        guard shouldMaintainWebSocket else { return }
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 30)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.connectWebSocket()
        }
    }

    private func handleWSMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = root["type"] as? String else { return }

        switch type {
        case "hello":
            wsConnected = true
            lastWSConnectedAt = Date()
            reconnectDelay = 2
            let helloDevId = ((root["data"] as? [String: Any])?["device_id"] as? String) ?? Cloud.shared.deviceId ?? "unknown"
            log(.ok, "WS", "实时通道已连接（\(wsRouteLabel)，device_id=\(helloDevId.suffix(8))）")
            if enabled {
                syncDeviceStateToServer()
                Task { await reconcileQueuedCommands() }
            }
        case "pong":
            wsConnected = true
        case "command":
            guard let cmdObj = root["data"],
                  let cmdData = try? JSONSerialization.data(withJSONObject: cmdObj),
                  let cmd = try? JSONDecoder().decode(RemoteCommand.self, from: cmdData) else { return }
            log(.info, "CMD", "通过 WS 收到指令 \(cmd.id.prefix(8)) [\(cmd.provider)/\(cmd.mode)] 项目=\(cmd.project ?? "-")")
            sendAck(commandId: cmd.id)
            enqueue(cmd)
        default:
            break
        }
    }

    private func sendAck(commandId: String) {
        guard let task = wsTask else { return }
        if let data = try? JSONSerialization.data(withJSONObject: ["type": "command_ack", "command_id": commandId]),
           let str = String(data: data, encoding: .utf8) {
            task.send(.string(str)) { _ in }
        }
    }

    /// 连上 WebSocket 时向服务端兜底拉取一次 queued 指令，防止离线期间漏投递
    private func reconcileQueuedCommands() async {
        guard enabled, let token = Cloud.shared.token else { return }
        guard let deviceId = Cloud.shared.deviceId else {
            await Cloud.shared.refreshMe()
            guard let id = Cloud.shared.deviceId else { return }
            await fetchQueued(deviceId: id, token: token)
            return
        }
        await fetchQueued(deviceId: deviceId, token: token)
    }

    private func fetchQueued(deviceId: String, token: String) async {
        let path = "/api/commands?device=\(deviceId)&status=queued,delivered&limit=20"
        guard let (data, status) = try? await Cloud.request("GET", path, token: token) else {
            log(.warn, "API", "拉取排队指令失败（网络错误）")
            return
        }
        guard status == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = root["commands"],
              let arrData = try? JSONSerialization.data(withJSONObject: arr),
              let cmds = try? JSONDecoder().decode([RemoteCommand].self, from: arrData) else {
            log(.warn, "API", "拉取排队指令返回 HTTP \(status)")
            return
        }
        log(.info, "API", "对账排队指令（device=\(deviceId.suffix(8))）：找到 \(cmds.count) 条")
        for cmd in cmds.reversed() {
            enqueue(cmd)
        }
    }

    // MARK: 指令执行流水线

    func enqueue(_ command: RemoteCommand) {
        guard seenCommandIds.insert(command.id).inserted else { return }
        queue.append(command)
        if !processingQueue {
            processingQueue = true
            Task { await processQueue() }
        }
    }

    private func processQueue() async {
        defer {
            processingQueue = false
            activeCommandId = nil
        }
        while !queue.isEmpty {
            let cmd = queue.removeFirst()
            activeCommandId = cmd.id
            await execute(cmd)
        }
    }

    private func execute(_ cmd: RemoteCommand) async {
        var entry = CommandHistoryEntry(
            id: cmd.id,
            provider: cmd.provider,
            mode: cmd.mode,
            sessionId: cmd.sessionId,
            project: cmd.project,
            resolvedCwd: nil,
            prompt: cmd.prompt,
            status: "delivered",
            result: nil,
            error: nil,
            resultSessionId: nil,
            receivedAt: Date(),
            finishedAt: nil
        )
        recordHistory(entry)

        // 本机总开关关闭时一律拒绝（双保险）
        guard enabled else {
            let reason = "该 Mac 的远程指令开关已关闭。"
            entry.status = "rejected"
            entry.error = reason
            entry.finishedAt = Date()
            recordHistory(entry)
            await reportStatus(cmd.id, status: "rejected", error: reason)
            return
        }

        let caps = capabilities ?? CLICapabilityProber.probeAll()
        let ownIds = ownRunningSessionIds
        let hookInteractive = cmd.sessionId.map { HookManager.shared.isInteractivelyActive(sessionId: $0) } ?? false
        let validator = CommandSecurityValidator(isInteractiveActive: { sid, local, now in
            if ownIds.contains(sid) { return false }
            if sid == cmd.sessionId && hookInteractive { return true }
            return CommandSecurityValidator.defaultInteractiveCheck(sessionId: sid, local: local, now: now)
        })

        let validation = validator.validate(command: cmd, capabilities: caps, local: localSnapshot)
        switch validation {
        case .rejected(let reason):
            entry.status = "rejected"
            entry.error = reason
            entry.finishedAt = Date()
            recordHistory(entry)
            log(.warn, "CMD", "指令 \(cmd.id.prefix(8)) 被安全策略拒绝：\(reason)")
            await reportStatus(cmd.id, status: "rejected", error: reason)
            return

        case .approved(let source, let mode, let cwd, let cliPath):
            entry.resolvedCwd = cwd
            recordHistory(entry)

            // 可选本机弹窗确认
            if requireConfirmation {
                let allowed = CommandSecurityValidator.requestLocalConfirmation(command: cmd, resolvedCwd: cwd)
                if !allowed {
                    let reason = "用户在 Mac 上拒绝了该远程指令。"
                    entry.status = "rejected"
                    entry.error = reason
                    entry.finishedAt = Date()
                    recordHistory(entry)
                    log(.warn, "CMD", "指令 \(cmd.id.prefix(8)) 在本机弹窗被用户拒绝")
                    await reportStatus(cmd.id, status: "rejected", error: reason)
                    return
                }
            }

            entry.status = "running"
            recordHistory(entry)
            log(.info, "CMD", "开始执行 \(cmd.id.prefix(8))：\(cliPath) [\(mode.rawValue)] cwd=\(cwd)")
            await reportStatus(cmd.id, status: "running", progress: "正在启动 \(source.title)…")

            if let sid = cmd.sessionId { ownRunningSessionIds.insert(sid) }
            defer { if let sid = cmd.sessionId { ownRunningSessionIds.remove(sid) } }

            let commandId = cmd.id
            let result = await runner.run(
                source: source,
                cliPath: cliPath,
                mode: mode,
                sessionId: cmd.sessionId,
                cwd: cwd,
                prompt: cmd.prompt,
                onProgress: { progress in
                    Task { @MainActor in
                        await RemoteCommandManager.shared.reportStatus(commandId, status: "running", progress: progress)
                    }
                }
            )

            entry.status = result.succeeded ? "done" : "failed"
            entry.result = result.summary
            entry.error = result.error
            entry.resultSessionId = result.resultSessionId
            entry.finishedAt = Date()
            recordHistory(entry)

            if result.succeeded {
                log(.ok, "CMD", "指令 \(cmd.id.prefix(8)) 执行完成（session=\(result.resultSessionId ?? "-")）")
            } else {
                log(.error, "CMD", "指令 \(cmd.id.prefix(8)) 执行失败：\(result.error ?? "未知错误")")
            }

            await reportStatus(
                cmd.id,
                status: entry.status,
                result: result.summary,
                error: result.error,
                resultSessionId: result.resultSessionId
            )
        }
    }

    private func recordHistory(_ entry: CommandHistoryEntry) {
        CommandHistoryStore.shared.upsert(entry)
        recentHistory = CommandHistoryStore.shared.all()
    }

    func reportStatus(_ commandId: String,
                      status: String,
                      progress: String? = nil,
                      result: String? = nil,
                      error: String? = nil,
                      resultSessionId: String? = nil) async {
        guard let token = Cloud.shared.token else { return }
        var body: [String: Any] = ["status": status]
        if let progress { body["progress"] = progress }
        if let result { body["result"] = result }
        if let error { body["error"] = error }
        if let resultSessionId { body["result_session_id"] = resultSessionId }
        do {
            let (_, code) = try await Cloud.request("POST", "/api/commands/\(commandId)/status", json: body, token: token)
            if code == 401 { Cloud.shared.handleUnauthorized() }
        } catch {
            NSLog("[cloud-remote] reportStatus %@ (%@) failed: %@", commandId, status, error.localizedDescription)
        }
    }
}
