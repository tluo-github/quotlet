import Combine
import Foundation

// 免钥匙串获取 Claude Code 额度（Claude Code v2.1.80+ 官方 statusLine 机制）：
// 1. `--statusline` 命令行模式：在 SwiftUI 启动前从 stdin 读 Claude Code 传入的 JSON，
//    提取 rate_limits（five_hour / seven_day）并原子写入本地快照文件；
//    若用户原本配置了自定义 statusLine，则透明转发 stdin/stdout，不破坏原有终端状态栏。
// 2. ClaudeStatusLineInstaller：安全写入/卸载/修复 ~/.claude/settings.json 的 statusLine，
//    修改前先备份，卸载时还原用户原有配置。
// 3. ClaudeStatusLineManager：使用 DispatchSource 监听快照文件目录变化，秒级推送到 Store、
//    CloudSync、HistoryStore 与 Notifier，全程零钥匙串访问、零额外网络请求。

struct ClaudeStatusLineWindow: Codable, Equatable {
    let usedPercentage: Double
    let resetsAt: Date?
}

struct ClaudeStatusLineSnapshot: Codable, Equatable {
    let observedAt: Date
    let fiveHour: ClaudeStatusLineWindow?
    let sevenDay: ClaudeStatusLineWindow?
    let modelName: String?
    let sessionId: String?

    var hasAnyLimit: Bool { fiveHour != nil || sevenDay != nil }

    func toUsageSnapshot(now: Date = Date()) -> UsageSnapshot {
        var limits: [LimitItem] = []
        if let w = fiveHour {
            let expired = w.resetsAt.map { $0 <= now } ?? false
            limits.append(LimitItem(
                id: "statusline-session",
                kind: "session",
                title: L("当前会话 · 5 小时", "Current session · 5 hours", ja: "現在のセッション · 5 時間", ko: "현재 세션 · 5시간"),
                percent: expired ? 0 : w.usedPercentage,
                severity: nil,
                resetsAt: expired ? nil : w.resetsAt
            ))
        }
        if let w = sevenDay {
            let expired = w.resetsAt.map { $0 <= now } ?? false
            limits.append(LimitItem(
                id: "statusline-weekly",
                kind: "weekly_all",
                title: L("本周 · 所有模型", "This week · all models", ja: "今週 · すべてのモデル", ko: "이번 주 · 모든 모델"),
                percent: expired ? 0 : w.usedPercentage,
                severity: nil,
                resetsAt: expired ? nil : w.resetsAt
            ))
        }
        return UsageSnapshot(limits: limits, breakdown: [], breakdownStart: nil, extra: nil, plan: nil)
    }
}

struct ClaudeStatusLineWrappedConfig: Codable, Equatable {
    let type: String
    let command: String
    let padding: Int?
}

enum ClaudeStatusLinePaths {
    static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Quotlet", isDirectory: true)
    }
    static var snapshotURL: URL {
        supportDir.appendingPathComponent("claude-statusline-limits.json")
    }
    static var wrappedConfigURL: URL {
        supportDir.appendingPathComponent("claude-statusline-wrapped.json")
    }
}

// MARK: - CLI 模式（Quotlet --statusline）

enum ClaudeStatusLineCLI {
    static let maxStdinBytes = 262_144

    /// 供 App.swift 在 SwiftUI 启动前调用。永远不抛出、不访问钥匙串、不联网。
    static func run(stdinData: Data? = nil,
                    snapshotURL: URL = ClaudeStatusLinePaths.snapshotURL,
                    wrappedConfigURL: URL = ClaudeStatusLinePaths.wrappedConfigURL,
                    now: Date = Date()) {
        let data = stdinData ?? readStdinUpTo(limit: maxStdinBytes)
        if let snap = parseSnapshot(from: data, now: now) {
            saveSnapshot(snap, to: snapshotURL)
        }
        forwardToWrappedCommandIfNeeded(stdinData: data, wrappedConfigURL: wrappedConfigURL)
    }

    static func parseSnapshot(from data: Data, now: Date = Date()) -> ClaudeStatusLineSnapshot? {
        guard !data.isEmpty,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rateLimits = root["rate_limits"] as? [String: Any] else {
            return nil
        }

        let fiveHour = parseWindow(rateLimits["five_hour"])
        let sevenDay = parseWindow(rateLimits["seven_day"])
        guard fiveHour != nil || sevenDay != nil else { return nil }

        let modelName = (root["model"] as? [String: Any])?["display_name"] as? String
            ?? (root["model"] as? [String: Any])?["id"] as? String
        let sessionId = (root["session_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        return ClaudeStatusLineSnapshot(
            observedAt: now,
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            modelName: modelName,
            sessionId: sessionId?.isEmpty == true ? nil : sessionId
        )
    }

    private static func parseWindow(_ raw: Any?) -> ClaudeStatusLineWindow? {
        guard let dict = raw as? [String: Any] else { return nil }
        let pctNum = (dict["used_percentage"] as? NSNumber) ?? (dict["utilization"] as? NSNumber)
        guard let pct = pctNum?.doubleValue, pct.isFinite else { return nil }
        let clamped = min(max(pct, 0), 1000)
        return ClaudeStatusLineWindow(usedPercentage: clamped, resetsAt: parseResetDate(dict["resets_at"]))
    }

    private static func parseResetDate(_ raw: Any?) -> Date? {
        if let num = raw as? NSNumber {
            let v = num.doubleValue
            guard v.isFinite, v > 0 else { return nil }
            // Claude Code statusLine 传入 Unix 秒；若未来改为毫秒（> 1e12）也自动兼容
            return Date(timeIntervalSince1970: v > 1_000_000_000_000 ? v / 1000.0 : v)
        }
        if let str = raw as? String, !str.isEmpty {
            return Fmt.parseISO(str)
        }
        return nil
    }

    static func saveSnapshot(_ snapshot: ClaudeStatusLineSnapshot, to url: URL) {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? enc.encode(snapshot) else { return }
        let tmp = dir.appendingPathComponent(".statusline-limits.tmp.\(UUID().uuidString)")
        do {
            try data.write(to: tmp, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: url)
            }
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            try? fm.removeItem(at: tmp)
        }
    }

    static func loadSnapshot(from url: URL = ClaudeStatusLinePaths.snapshotURL) -> ClaudeStatusLineSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .millisecondsSince1970
        return try? dec.decode(ClaudeStatusLineSnapshot.self, from: data)
    }

    static func forwardToWrappedCommandIfNeeded(stdinData: Data,
                                                wrappedConfigURL: URL,
                                                timeout: TimeInterval = 2.0,
                                                outputHandle: FileHandle = .standardOutput) {
        guard let cfgData = try? Data(contentsOf: wrappedConfigURL),
              let cfg = try? JSONDecoder().decode(ClaudeStatusLineWrappedConfig.self, from: cfgData),
              !cfg.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !cfg.command.contains(ClaudeStatusLineInstaller.marker) else {
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", cfg.command]
        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            return
        }

        if !stdinData.isEmpty {
            try? inPipe.fileHandleForWriting.write(contentsOf: stdinData)
        }
        try? inPipe.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning && Date() < deadline {
            usleep(10_000)
        }
        if proc.isRunning {
            proc.terminate()
            return
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        if !outData.isEmpty {
            try? outputHandle.write(contentsOf: outData)
        }
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
}

// MARK: - settings.json 安全安装器

enum ClaudeStatusLineError: LocalizedError {
    case invalidSettingsJSON(String)

    var errorDescription: String? {
        switch self {
        case .invalidSettingsJSON(let path):
            return L("配置文件格式不是有效的 JSON：\(path)",
                     "Invalid JSON in settings file: \(path)",
                     ja: "設定ファイルが有効な JSON ではありません：\(path)",
                     ko: "설정 파일이 올바른 JSON이 아닙니다: \(path)")
        }
    }
}

struct ClaudeStatusLineInstaller {
    static let marker = "# quotlet-statusline"

    let claudeSettingsURL: URL
    let wrappedConfigURL: URL
    let executablePath: String

    init(claudeSettingsURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json"),
         wrappedConfigURL: URL = ClaudeStatusLinePaths.wrappedConfigURL,
         executablePath: String = Bundle.main.executablePath ?? CommandLine.arguments.first ?? "/Applications/Quotlet.app/Contents/MacOS/Quotlet") {
        self.claudeSettingsURL = claudeSettingsURL
        self.wrappedConfigURL = wrappedConfigURL
        self.executablePath = executablePath
    }

    enum InstallState: Equatable {
        case notInstalled
        case installed(pathMatches: Bool)
    }

    static func commandString(executablePath: String) -> String {
        let escaped = executablePath.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)' --statusline   \(marker)"
    }

    func inspect() -> InstallState {
        guard let root = try? readSettingsObject(url: claudeSettingsURL),
              let sl = root["statusLine"] as? [String: Any],
              let cmd = sl["command"] as? String,
              cmd.contains(Self.marker) else {
            return .notInstalled
        }
        let expected = Self.commandString(executablePath: executablePath)
        return .installed(pathMatches: cmd == expected)
    }

    func install() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: claudeSettingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var root = try readSettingsObject(url: claudeSettingsURL)
        backupIfNeeded(url: claudeSettingsURL)

        // 若用户原本配置了自己的 statusLine，保存到 sidecar 以便透明转发，卸载时原样恢复
        if let existing = root["statusLine"] as? [String: Any],
           let existingCmd = existing["command"] as? String,
           !existingCmd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !existingCmd.contains(Self.marker) {
            let wrapped = ClaudeStatusLineWrappedConfig(
                type: (existing["type"] as? String) ?? "command",
                command: existingCmd,
                padding: existing["padding"] as? Int
            )
            try saveWrappedConfig(wrapped)
        }

        var nextStatusLine: [String: Any] = [
            "type": "command",
            "command": Self.commandString(executablePath: executablePath),
        ]
        if let wrapped = loadWrappedConfig(), let padding = wrapped.padding {
            nextStatusLine["padding"] = padding
        }
        root["statusLine"] = nextStatusLine
        try atomicWriteJSON(root, to: claudeSettingsURL)
    }

    func uninstall() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: claudeSettingsURL.path) else {
            try? fm.removeItem(at: wrappedConfigURL)
            return
        }
        var root = try readSettingsObject(url: claudeSettingsURL)
        if let sl = root["statusLine"] as? [String: Any],
           let cmd = sl["command"] as? String,
           cmd.contains(Self.marker) {
            if let wrapped = loadWrappedConfig() {
                var restored: [String: Any] = ["type": wrapped.type, "command": wrapped.command]
                if let padding = wrapped.padding { restored["padding"] = padding }
                root["statusLine"] = restored
            } else {
                root.removeValue(forKey: "statusLine")
            }
            try atomicWriteJSON(root, to: claudeSettingsURL)
        }
        try? fm.removeItem(at: wrappedConfigURL)
    }

    private func loadWrappedConfig() -> ClaudeStatusLineWrappedConfig? {
        guard let data = try? Data(contentsOf: wrappedConfigURL) else { return nil }
        return try? JSONDecoder().decode(ClaudeStatusLineWrappedConfig.self, from: data)
    }

    private func saveWrappedConfig(_ config: ClaudeStatusLineWrappedConfig) throws {
        let fm = FileManager.default
        let dir = wrappedConfigURL.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(config)
        try data.write(to: wrappedConfigURL, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: wrappedConfigURL.path)
    }

    private func readSettingsObject(url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [:] }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeStatusLineError.invalidSettingsJSON(url.path)
        }
        return obj
    }

    private func backupIfNeeded(url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        let backupURL = url.deletingLastPathComponent().appendingPathComponent("settings.json.quotlet-bak")
        if !fm.fileExists(atPath: backupURL.path) {
            try? fm.copyItem(at: url, to: backupURL)
        }
    }

    private func atomicWriteJSON(_ root: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".settings.quotlet-statusline.\(UUID().uuidString).tmp")
        try data.write(to: tmp, options: .atomic)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: url)
        }
    }
}

// MARK: - 主 App 运行时监听管理

@MainActor
final class ClaudeStatusLineManager: ObservableObject {
    static let shared = ClaudeStatusLineManager()

    static let enabledKey = "claudeStatusLineEnabled"
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    @Published private(set) var enabled: Bool = false
    @Published private(set) var installed: Bool = false
    @Published private(set) var latest: ClaudeStatusLineSnapshot?
    @Published private(set) var lastError: String?

    var onSnapshot: ((ClaudeStatusLineSnapshot) -> Void)?

    private var dirFD: Int32 = -1
    private var dirSource: DispatchSourceFileSystemObject?
    private var fallbackTimer: Timer?
    private let watchQueue = DispatchQueue(label: "com.quotlet.claude-statusline-watch", qos: .utility)

    private init() {
        UserDefaults.standard.register(defaults: [Self.enabledKey: false])
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        if Cloud.isPreview { return }
        verifyAndRepairOnLaunch()
        if enabled {
            reloadFromDisk(notify: false)
            startWatching()
        }
    }

    func setEnabled(_ on: Bool) {
        lastError = nil
        let installer = ClaudeStatusLineInstaller()
        if on {
            do {
                try installer.install()
                enabled = true
                installed = true
                UserDefaults.standard.set(true, forKey: Self.enabledKey)
                reloadFromDisk(notify: true)
                startWatching()
            } catch {
                enabled = false
                installed = false
                UserDefaults.standard.set(false, forKey: Self.enabledKey)
                lastError = error.localizedDescription
            }
        } else {
            do {
                try installer.uninstall()
            } catch {
                lastError = error.localizedDescription
            }
            enabled = false
            installed = false
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
            stopWatching()
        }
    }

    func verifyAndRepairOnLaunch() {
        let installer = ClaudeStatusLineInstaller()
        let state = installer.inspect()
        switch state {
        case .notInstalled:
            installed = false
            if enabled {
                // 用户手动从 settings.json 移除时尊重用户选择
                enabled = false
                UserDefaults.standard.set(false, forKey: Self.enabledKey)
                stopWatching()
            }
        case .installed(let pathMatches):
            installed = true
            if enabled && !pathMatches {
                try? installer.install()
            } else if !enabled {
                enabled = true
                UserDefaults.standard.set(true, forKey: Self.enabledKey)
            }
        }
    }

    func reloadFromDisk(notify: Bool = true) {
        guard let snap = ClaudeStatusLineCLI.loadSnapshot() else { return }
        let changed = snap != latest
        latest = snap
        if notify && changed {
            onSnapshot?(snap)
        }
    }

    private func startWatching() {
        guard dirSource == nil else { return }
        let dir = ClaudeStatusLinePaths.supportDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.path, O_EVTONLY)
        if fd >= 0 {
            dirFD = fd
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: watchQueue)
            src.setEventHandler { [weak self] in
                Task { @MainActor [weak self] in
                    self?.reloadFromDisk(notify: true)
                }
            }
            src.setCancelHandler { [fd] in
                close(fd)
            }
            dirSource = src
            src.resume()
        }
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadFromDisk(notify: true)
            }
        }
    }

    private func stopWatching() {
        dirSource?.cancel()
        dirSource = nil
        dirFD = -1
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }
}
