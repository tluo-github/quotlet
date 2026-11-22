import Combine
import Foundation

// 二期远程指令调度器（D1 持久化队列轮询 + 弱网结果持久化重试队列）：
// - 不依赖脆弱的 WebSocket 长连接，全程复用 Cloud.request（代理优先 + 直连回退 + 自动重试）
// - 开启远程指令后，Mac 定时轮询 POST /api/commands/poll 认领排队指令并感知远程取消
// - 终态执行结果先落盘至本地 Outbox，弱网/断网上报失败时在后续轮询周期自动重传，确保结果不丢失
// - 退出登录时自动关闭远程指令、停止轮询并清空本地 Outbox

struct RemoteLogEntry: Identifiable, Equatable {
    enum Level: String {
        case info, ok, warn, error
    }
    let id = UUID()
    let ts: Date
    let level: Level
    let category: String   // POLL | CMD | OUTBOX | CAP | API
    let message: String
}

/// 待回传到云端的指令状态记录（弱网持久化重试队列项）
struct PendingCommandReport: Codable, Equatable {
    static let terminalStatuses: Set<String> = ["done", "failed", "rejected", "cancelled", "expired"]

    let commandId: String
    let status: String
    let progress: String?
    let result: String?
    let error: String?
    let resultSessionId: String?
    let updatedAt: Date
    var attempts: Int

    var isTerminal: Bool { Self.terminalStatuses.contains(status) }

    func jsonBody() -> [String: Any] {
        var body: [String: Any] = ["status": status]
        if let progress { body["progress"] = progress }
        if let result { body["result"] = result }
        if let error { body["error"] = error }
        if let resultSessionId { body["result_session_id"] = resultSessionId }
        return body
    }
}

/// 持久化状态回传重试队列（Outbox）：
/// - 按 commandId 合并去重，终态不会被非终态覆盖
/// - 写盘权限 0600，重启 App 后仍可继续补发未送达的指令结果
final class CommandStatusOutbox {
    private let fileURL: URL
    private let maxEntries: Int
    private let maxAge: TimeInterval
    private let lock = NSLock()
    private var items: [PendingCommandReport] = []

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Quotlet", isDirectory: true)
            .appendingPathComponent("command-status-outbox.json")
    }

    init(fileURL: URL = CommandStatusOutbox.defaultURL, maxEntries: Int = 100, maxAge: TimeInterval = 7 * 86400, now: Date = Date()) {
        self.fileURL = fileURL
        self.maxEntries = maxEntries
        self.maxAge = maxAge
        self.items = Self.load(from: fileURL)
        pruneLocked(now: now)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return items.count
    }

    func all(now: Date = Date()) -> [PendingCommandReport] {
        lock.lock()
        defer { lock.unlock() }
        pruneLocked(now: now)
        return items.sorted { $0.updatedAt < $1.updatedAt }
    }

    func upsert(_ report: PendingCommandReport, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        if let idx = items.firstIndex(where: { $0.commandId == report.commandId }) {
            // 已进入终态的待重传记录不被迟到的非终态覆盖
            if items[idx].isTerminal && !report.isTerminal { return }
            items[idx] = report
        } else {
            items.append(report)
        }
        pruneLocked(now: now)
        saveLocked()
    }

    func recordAttempt(commandId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let idx = items.firstIndex(where: { $0.commandId == commandId }) else { return }
        items[idx].attempts += 1
        saveLocked()
    }

    func remove(commandId: String) {
        lock.lock()
        defer { lock.unlock() }
        let before = items.count
        items.removeAll { $0.commandId == commandId }
        if items.count != before {
            saveLocked()
        }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        items.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func pruneLocked(now: Date) {
        let cutoff = now.addingTimeInterval(-maxAge)
        items.removeAll { $0.updatedAt < cutoff }
        if items.count > maxEntries {
            // 超出上限时优先保留终态结果，再按时间保留最新的
            items.sort {
                if $0.isTerminal != $1.isTerminal { return $0.isTerminal && !$1.isTerminal }
                return $0.updatedAt > $1.updatedAt
            }
            items = Array(items.prefix(maxEntries))
        }
    }

    private static func load(from url: URL) -> [PendingCommandReport] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .millisecondsSince1970
        return (try? dec.decode([PendingCommandReport].self, from: data)) ?? []
    }

    private func saveLocked() {
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? enc.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
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

    private static let idlePollInterval: TimeInterval = 12
    private static let activePollInterval: TimeInterval = 5
    private static let maxErrorBackoff: TimeInterval = 30

    /// 远程指令开关：默认关闭，仅能在本台 Mac 上登录后手动开启
    @Published private(set) var enabled: Bool = false
    /// 可选：每条指令执行前在 Mac 上弹窗确认
    @Published var requireConfirmation: Bool {
        didSet { UserDefaults.standard.set(requireConfirmation, forKey: Key.confirm) }
    }
    /// 队列轮询最近是否健康连通
    @Published private(set) var pollConnected: Bool = false
    /// 最近一次成功轮询的时间
    @Published private(set) var lastPollAt: Date?
    /// 等待弱网重传的状态结果条数
    @Published private(set) var pendingOutboxCount: Int = 0
    @Published private(set) var capabilities: DeviceCapabilities?
    @Published private(set) var activeCommandId: String?
    @Published private(set) var lastError: String?
    @Published private(set) var recentHistory: [CommandHistoryEntry] = []
    @Published private(set) var logs: [RemoteLogEntry] = []

    private var localSnapshot: LocalSnapshot?
    private var userWatch: AnyCancellable?
    private var pollTask: Task<Void, Never>?
    private var consecutivePollFailures = 0
    private var needsDeliveredRecovery = true
    private var isFlushingOutbox = false

    /// 正在排队 / 执行中的指令去重集合与 FIFO 队列
    private var seenCommandIds: Set<String> = []
    private var cancelledCommandIds: Set<String> = []
    private var activeCancelToken: ExecutionCancelToken?
    private var queue: [RemoteCommand] = []
    private var processingQueue = false
    /// 记录当前由 Quotlet 远程执行器运行中的 sessionId，避免误判自己为终端交互冲突
    private var ownRunningSessionIds: Set<String> = []

    private let outbox = CommandStatusOutbox()
    private let runner = SubprocessProviderRunner()

    private init() {
        UserDefaults.standard.register(defaults: [Key.enabled: false, Key.confirm: false])
        requireConfirmation = UserDefaults.standard.bool(forKey: Key.confirm)
        recentHistory = CommandHistoryStore.shared.all()
        pendingOutboxCount = outbox.count

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
                        self.needsDeliveredRecovery = true
                        self.syncDeviceStateToServer()
                        self.ensureConnectionState()
                    }
                }
            }
    }

    var shouldPollCommands: Bool {
        Cloud.shared.isSignedIn && !Cloud.isPreview && !Demo.enabled
            && !UserDefaults.standard.bool(forKey: "offline")
            && (enabled || pendingOutboxCount > 0)
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

    /// 手动立即同步：同步设备状态 + 重传未送达结果 + 立刻拉取云端队列
    func reconnectAndSync() {
        log(.info, "POLL", "手动触发队列同步并重传待回传结果")
        consecutivePollFailures = 0
        needsDeliveredRecovery = true
        syncDeviceStateToServer()
        stopPolling()
        ensureConnectionState()
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
            needsDeliveredRecovery = true
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
        stopPolling()
        activeCancelToken?.cancel()
        activeCancelToken = nil
        queue.removeAll()
        seenCommandIds.removeAll()
        cancelledCommandIds.removeAll()
        outbox.clear()
        pendingOutboxCount = 0
        lastPollAt = nil
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

    // MARK: D1 队列轮询循环

    func ensureConnectionState() {
        if shouldPollCommands {
            startPollingIfNeeded()
        } else {
            stopPolling()
        }
    }

    private func startPollingIfNeeded() {
        guard pollTask == nil else { return }
        log(.info, "POLL", "已启动 D1 队列轮询（空闲 \(Int(Self.idlePollInterval))s / 执行中 \(Int(Self.activePollInterval))s）")
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.shouldPollCommands else { break }
                await self.pollOnce()
                if Task.isCancelled || !self.shouldPollCommands { break }
                let delay = self.nextPollInterval()
                try? await Task.sleep(for: .seconds(delay))
            }
            await MainActor.run { [weak self] in
                self?.pollTask = nil
                self?.pollConnected = false
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        pollConnected = false
        consecutivePollFailures = 0
    }

    private func nextPollInterval() -> TimeInterval {
        if consecutivePollFailures > 0 {
            let exp = min(consecutivePollFailures - 1, 2)
            return min(10 * pow(2.0, Double(exp)), Self.maxErrorBackoff)
        }
        if activeCommandId != nil || !queue.isEmpty || pendingOutboxCount > 0 {
            return Self.activePollInterval
        }
        return Self.idlePollInterval
    }

    private func currentActiveCommandIds() -> [String] {
        var ids: [String] = []
        if let activeCommandId { ids.append(activeCommandId) }
        for cmd in queue where !ids.contains(cmd.id) {
            ids.append(cmd.id)
        }
        return ids
    }

    private func pollOnce() async {
        guard let token = Cloud.shared.token else { return }

        // 1. 先重传本地 Outbox 中尚未送达的状态/结果
        await flushOutbox()

        // 如果远程指令开关已关且仅是为了清空 Outbox，重传完成后不再拉新指令
        guard enabled else { return }

        let activeIds = currentActiveCommandIds()
        let includeDelivered = needsDeliveredRecovery
        var payload: [String: Any] = ["include_delivered": includeDelivered]
        if !activeIds.isEmpty {
            payload["active_ids"] = activeIds
        }

        do {
            let (data, status) = try await Cloud.request("POST", "/api/commands/poll", json: payload, token: token)
            if status == 401 {
                log(.error, "POLL", "POST /api/commands/poll 返回 401，已退出登录")
                Cloud.shared.handleUnauthorized()
                return
            }
            guard status == 200,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                recordPollFailure("轮询队列返回 HTTP \(status)")
                return
            }

            let wasDisconnected = !pollConnected
            consecutivePollFailures = 0
            pollConnected = true
            lastPollAt = Date()
            lastError = nil
            needsDeliveredRecovery = false
            if wasDisconnected {
                log(.ok, "POLL", "队列轮询已连通")
            }

            if let cancelled = root["cancelled_ids"] as? [String], !cancelled.isEmpty {
                for id in cancelled {
                    cancelCommand(id: id, fromRemote: true)
                }
            }

            if let arr = root["commands"],
               let arrData = try? JSONSerialization.data(withJSONObject: arr),
               let cmds = try? JSONDecoder().decode([RemoteCommand].self, from: arrData),
               !cmds.isEmpty {
                log(.info, "POLL", "从云端队列拉取到 \(cmds.count) 条待执行指令")
                for cmd in cmds {
                    enqueue(cmd)
                }
            }
        } catch {
            recordPollFailure("轮询队列失败：\(error.localizedDescription)")
        }
    }

    private func recordPollFailure(_ message: String) {
        consecutivePollFailures += 1
        // 首次波动或每 3 次失败记一条日志，避免弱网刷屏
        if consecutivePollFailures == 1 || consecutivePollFailures % 3 == 0 {
            log(.warn, "POLL", "\(message)（第 \(consecutivePollFailures) 次失败，将自动重试）")
        }
        if consecutivePollFailures >= 2 {
            pollConnected = false
            lastError = message
        }
    }

    // MARK: 弱网结果重传队列（Outbox）

    func flushOutbox() async {
        guard !isFlushingOutbox, let token = Cloud.shared.token else { return }
        let pending = outbox.all()
        pendingOutboxCount = pending.count
        guard !pending.isEmpty else { return }

        isFlushingOutbox = true
        defer {
            isFlushingOutbox = false
            pendingOutboxCount = outbox.count
        }

        for item in pending {
            let outcome = await sendStatusRequest(commandId: item.commandId, body: item.jsonBody(), token: token)
            switch outcome {
            case .delivered(let serverStatus):
                outbox.remove(commandId: item.commandId)
                log(.ok, "OUTBOX", "补发指令 \(item.commandId.prefix(8)) 状态(\(item.status))成功")
                if serverStatus == "cancelled", item.status != "cancelled" {
                    cancelCommand(id: item.commandId, fromRemote: true)
                }
            case .permanentReject(let code):
                outbox.remove(commandId: item.commandId)
                log(.warn, "OUTBOX", "指令 \(item.commandId.prefix(8)) 状态补发返回 HTTP \(code)，已放弃重传")
            case .unauthorized:
                Cloud.shared.handleUnauthorized()
                return
            case .retryable:
                outbox.recordAttempt(commandId: item.commandId)
                // 当前网络不通时立刻结束本轮，避免对剩余项连续超时阻塞
                return
            }
        }
    }

    private enum ReportOutcome {
        case delivered(serverStatus: String?)
        case permanentReject(Int)
        case unauthorized
        case retryable
    }

    private func sendStatusRequest(commandId: String, body: [String: Any], token: String) async -> ReportOutcome {
        do {
            let (data, code) = try await Cloud.request("POST", "/api/commands/\(commandId)/status", json: body, token: token)
            if code == 401 { return .unauthorized }
            if (200..<300).contains(code) {
                let serverStatus = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["command"] as? [String: Any])?["status"] as? String
                return .delivered(serverStatus: serverStatus)
            }
            if code == 400 || code == 403 || code == 404 {
                return .permanentReject(code)
            }
            return .retryable
        } catch {
            NSLog("[cloud-remote] reportStatus %@ failed: %@", commandId, error.localizedDescription)
            return .retryable
        }
    }

    // MARK: 指令执行流水线

    func enqueue(_ command: RemoteCommand) {
        guard !cancelledCommandIds.contains(command.id) else { return }
        guard seenCommandIds.insert(command.id).inserted else { return }
        queue.append(command)
        if !processingQueue {
            processingQueue = true
            Task { await processQueue() }
        }
    }

    func cancelCommand(id: String, fromRemote: Bool = false) {
        cancelledCommandIds.insert(id)
        if let idx = queue.firstIndex(where: { $0.id == id }) {
            let cmd = queue.remove(at: idx)
            log(.warn, "CMD", "指令 \(id.prefix(8)) 已在排队阶段被终止")
            let entry = CommandHistoryEntry(
                id: cmd.id,
                provider: cmd.provider,
                mode: cmd.mode,
                sessionId: cmd.sessionId,
                project: cmd.project,
                resolvedCwd: nil,
                prompt: cmd.prompt,
                status: "cancelled",
                result: nil,
                error: "用户已终止",
                resultSessionId: nil,
                receivedAt: Date(),
                finishedAt: Date()
            )
            recordHistory(entry)
        }
        if activeCommandId == id {
            log(.warn, "CMD", "收到终止指令 \(id.prefix(8))，正在结束子进程…")
            activeCancelToken?.cancel()
        }
        if !fromRemote, let token = Cloud.shared.token {
            Task {
                _ = try? await Cloud.request("POST", "/api/commands/\(id)/cancel", json: [:], token: token)
            }
        }
    }

    /// 删除单条执行历史（若仍在进行中会先终止；登录态下同步删除云端记录）
    func deleteHistoryEntry(id: String) {
        if activeCommandId == id || queue.contains(where: { $0.id == id }) {
            cancelCommand(id: id, fromRemote: true)
        }
        outbox.remove(commandId: id)
        pendingOutboxCount = outbox.count
        CommandHistoryStore.shared.remove(id: id)
        recentHistory = CommandHistoryStore.shared.all()
        if let token = Cloud.shared.token {
            let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
            Task {
                _ = try? await Cloud.request("DELETE", "/api/commands/\(encoded)", token: token)
            }
        }
    }

    /// 清空已结束的执行历史（保留进行中记录，登录态下同步清理云端）
    func clearFinishedHistory() {
        CommandHistoryStore.shared.clearFinished()
        recentHistory = CommandHistoryStore.shared.all()
        if let token = Cloud.shared.token {
            Task {
                _ = try? await Cloud.request("DELETE", "/api/commands?scope=terminal", token: token)
            }
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

            if cancelledCommandIds.contains(cmd.id) {
                entry.status = "cancelled"
                entry.error = "用户已终止"
                entry.finishedAt = Date()
                recordHistory(entry)
                log(.warn, "CMD", "指令 \(cmd.id.prefix(8)) 在启动前已被终止")
                await reportStatus(cmd.id, status: "cancelled", error: "用户已终止")
                return
            }

            entry.status = "running"
            recordHistory(entry)
            log(.info, "CMD", "开始执行 \(cmd.id.prefix(8))：\(cliPath) [\(mode.rawValue)] cwd=\(cwd)")
            await reportStatus(cmd.id, status: "running", progress: "正在启动 \(source.title)…")

            if let sid = cmd.sessionId { ownRunningSessionIds.insert(sid) }
            defer { if let sid = cmd.sessionId { ownRunningSessionIds.remove(sid) } }

            let cancelToken = ExecutionCancelToken()
            activeCancelToken = cancelToken
            defer { if activeCancelToken === cancelToken { activeCancelToken = nil } }

            let commandId = cmd.id
            let result = await runner.run(
                source: source,
                cliPath: cliPath,
                mode: mode,
                sessionId: cmd.sessionId,
                cwd: cwd,
                prompt: cmd.prompt,
                cancelToken: cancelToken,
                onProgress: { progress in
                    Task { @MainActor in
                        guard !RemoteCommandManager.shared.cancelledCommandIds.contains(commandId) else { return }
                        await RemoteCommandManager.shared.reportStatus(commandId, status: "running", progress: progress)
                    }
                }
            )

            let wasCancelled = result.cancelled || cancelledCommandIds.contains(cmd.id)
            entry.status = wasCancelled ? "cancelled" : (result.succeeded ? "done" : "failed")
            entry.result = result.summary
            entry.error = wasCancelled ? "用户已终止" : result.error
            entry.resultSessionId = result.resultSessionId
            entry.finishedAt = Date()
            recordHistory(entry)

            if wasCancelled {
                log(.warn, "CMD", "指令 \(cmd.id.prefix(8)) 已终止")
            } else if result.succeeded {
                log(.ok, "CMD", "指令 \(cmd.id.prefix(8)) 执行完成（session=\(result.resultSessionId ?? "-")）")
            } else {
                log(.error, "CMD", "指令 \(cmd.id.prefix(8)) 执行失败：\(result.error ?? "未知错误")")
            }

            await reportStatus(
                cmd.id,
                status: entry.status,
                result: result.summary,
                error: entry.error,
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
        let report = PendingCommandReport(
            commandId: commandId,
            status: status,
            progress: progress,
            result: result,
            error: error,
            resultSessionId: resultSessionId,
            updatedAt: Date(),
            attempts: 0
        )

        // 终态先落盘到 Outbox，保证弱网或 App 意外退出后结果不丢失
        if report.isTerminal {
            outbox.upsert(report)
            pendingOutboxCount = outbox.count
        }

        guard let token = Cloud.shared.token else { return }
        let outcome = await sendStatusRequest(commandId: commandId, body: report.jsonBody(), token: token)
        switch outcome {
        case .delivered(let serverStatus):
            if report.isTerminal {
                outbox.remove(commandId: commandId)
                pendingOutboxCount = outbox.count
            }
            if serverStatus == "cancelled", status != "cancelled" {
                cancelCommand(id: commandId, fromRemote: true)
            }
        case .permanentReject(let code):
            if report.isTerminal {
                outbox.remove(commandId: commandId)
                pendingOutboxCount = outbox.count
            }
            log(.warn, "API", "上报指令 \(commandId.prefix(8)) 状态(\(status))返回 HTTP \(code)")
        case .unauthorized:
            Cloud.shared.handleUnauthorized()
        case .retryable:
            if report.isTerminal {
                outbox.recordAttempt(commandId: commandId)
                pendingOutboxCount = outbox.count
                log(.warn, "OUTBOX", "指令 \(commandId.prefix(8)) 终态(\(status))暂未送达，已保留在弱网重试队列（待重传 \(pendingOutboxCount) 条）")
                ensureConnectionState()
            }
        }
    }
}
