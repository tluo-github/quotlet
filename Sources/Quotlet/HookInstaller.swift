import Combine
import Foundation

// 管理 Claude Code（以及可选的 Antigravity CLI）hooks 的安全安装、卸载与路径自愈。
//
// 安全与行为约束（docs/cloud-design.md 第 2 节）：
// - 默认关闭；必须先登录 Quotlet Cloud 才能打开；退出登录时自动卸载
// - 修改前先备份 settings.json -> settings.json.quotlet-bak
// - 只合并，不覆盖用户原有 hooks；使用 `# quotlet-hook` 尾标识别我们写入的条目
// - 通过临时文件 + 原子替换写入，避免半截文件损坏配置
// - 启动时自检：app 路径变化则自动修复；用户手动删掉了 hooks 则把开关同步为关闭

struct HookInstaller {
    static let marker = "# quotlet-hook"

    static let claudeEvents = ["SessionStart", "UserPromptSubmit", "Notification", "PostToolUse", "Stop", "SessionEnd"]
    static let geminiEvents = ["SessionStart", "BeforeAgent", "Notification", "AfterTool", "AfterAgent", "SessionEnd"]

    let claudeSettingsURL: URL
    let geminiSettingsURL: URL
    let executablePath: String
    let installGeminiHooks: Bool

    init(claudeSettingsURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json"),
         geminiSettingsURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/settings.json"),
         executablePath: String = Bundle.main.executablePath ?? CommandLine.arguments.first ?? "/Applications/Quotlet.app/Contents/MacOS/Quotlet",
         installGeminiHooks: Bool = false) {
        self.claudeSettingsURL = claudeSettingsURL
        self.geminiSettingsURL = geminiSettingsURL
        self.executablePath = executablePath
        self.installGeminiHooks = installGeminiHooks
    }

    enum InstallState: Equatable {
        case notInstalled
        case installed(pathMatches: Bool)
    }

    static func commandString(executablePath: String, source: String? = nil) -> String {
        let escaped = executablePath.replacingOccurrences(of: "'", with: "'\\''")
        if let source, source != "claude" {
            return "'\(escaped)' --hook --hook-source \(source)   \(marker)"
        }
        return "'\(escaped)' --hook   \(marker)"
    }

    func install() throws -> [String] {
        var targets: [String] = []
        try installTarget(url: claudeSettingsURL, events: Self.claudeEvents, command: Self.commandString(executablePath: executablePath))
        targets.append("Claude Code")
        if installGeminiHooks {
            try installTarget(url: geminiSettingsURL, events: Self.geminiEvents, command: Self.commandString(executablePath: executablePath, source: "gemini"))
            targets.append("Antigravity CLI")
        }
        return targets
    }

    func uninstall() throws {
        try uninstallTarget(url: claudeSettingsURL)
        if FileManager.default.fileExists(atPath: geminiSettingsURL.path) {
            try uninstallTarget(url: geminiSettingsURL)
        }
    }

    func inspectClaude() -> InstallState {
        inspectTarget(url: claudeSettingsURL, expectedCommand: Self.commandString(executablePath: executablePath))
    }

    // MARK: 内部读写

    private func installTarget(url: URL, events: [String], command: String) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        var root = try readSettingsObject(url: url)
        backupIfNeeded(url: url, existingRoot: root)

        var hooks = (root["hooks"] as? [String: Any]) ?? [:]
        // 先清掉旧的 quotlet-hook 条目，确保幂等且能修复 app 移动后的路径
        hooks = stripQuotletHooks(from: hooks)

        let entry: [String: Any] = [
            "matcher": "",
            "hooks": [
                ["type": "command", "command": command]
            ],
        ]

        for event in events {
            var groups = (hooks[event] as? [[String: Any]]) ?? []
            groups.append(entry)
            hooks[event] = groups
        }
        root["hooks"] = hooks
        try atomicWriteJSON(root, to: url)
    }

    private func uninstallTarget(url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var root = try readSettingsObject(url: url)
        guard let hooks = root["hooks"] as? [String: Any] else { return }
        let hadOurs = containsQuotletHook(in: hooks)
        guard hadOurs else { return }

        let cleaned = stripQuotletHooks(from: hooks)
        if cleaned.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = cleaned
        }
        try atomicWriteJSON(root, to: url)
    }

    private func inspectTarget(url: URL, expectedCommand: String) -> InstallState {
        guard FileManager.default.fileExists(atPath: url.path),
              let root = try? readSettingsObject(url: url),
              let hooks = root["hooks"] as? [String: Any] else {
            return .notInstalled
        }
        var foundAny = false
        var allMatch = true
        for event in Self.claudeEvents {
            guard let groups = hooks[event] as? [[String: Any]] else {
                allMatch = false
                continue
            }
            var eventHasMatch = false
            for g in groups {
                for h in (g["hooks"] as? [[String: Any]]) ?? [] {
                    guard let cmd = h["command"] as? String, cmd.contains(Self.marker) else { continue }
                    foundAny = true
                    if cmd == expectedCommand { eventHasMatch = true } else { allMatch = false }
                }
            }
            if !eventHasMatch { allMatch = false }
        }
        return foundAny ? .installed(pathMatches: allMatch) : .notInstalled
    }

    private func backupIfNeeded(url: URL, existingRoot: [String: Any]) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        let backupURL = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".quotlet-bak")
        let alreadyHasHook = (existingRoot["hooks"] as? [String: Any]).map { containsQuotletHook(in: $0) } ?? false
        if !alreadyHasHook || !fm.fileExists(atPath: backupURL.path) {
            try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: url, to: backupURL)
        }
    }

    private func containsQuotletHook(in hooks: [String: Any]) -> Bool {
        for (_, raw) in hooks {
            guard let groups = raw as? [[String: Any]] else { continue }
            for g in groups {
                for h in (g["hooks"] as? [[String: Any]]) ?? [] {
                    if let cmd = h["command"] as? String, cmd.contains(Self.marker) { return true }
                }
            }
        }
        return false
    }

    private func stripQuotletHooks(from hooks: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (event, raw) in hooks {
            guard let groups = raw as? [[String: Any]] else {
                result[event] = raw
                continue
            }
            var keptGroups: [[String: Any]] = []
            for var g in groups {
                if let items = g["hooks"] as? [[String: Any]] {
                    let filtered = items.filter { !(($0["command"] as? String)?.contains(Self.marker) ?? false) }
                    if !filtered.isEmpty {
                        g["hooks"] = filtered
                        keptGroups.append(g)
                    }
                } else {
                    keptGroups.append(g)
                }
            }
            if !keptGroups.isEmpty {
                result[event] = keptGroups
            }
        }
        return result
    }

    private func readSettingsObject(url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Quotlet.HookInstaller", code: 1, userInfo: [NSLocalizedDescriptionKey: "settings.json 格式不是 JSON 对象"])
        }
        return obj
    }

    private func atomicWriteJSON(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).quotlet-tmp-\(UUID().uuidString)")
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    }
}

/// App 级 hooks 生命周期管理：开关持久化、登录/退出联动、events.jsonl 监听。
@MainActor
final class HookManager: ObservableObject {
    static let shared = HookManager()

    static let enabledKey = "cloudHooksEnabled"

    @Published private(set) var enabled: Bool = false
    @Published private(set) var installedTargets: [String] = []
    @Published private(set) var lastError: String?

    private var watcher: HookEventWatcher?
    private var userWatch: AnyCancellable?
    private var states: [String: HookSessionState] = [:]

    private init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        if Cloud.isPreview { return }
        reconcileOnLaunch()
        userWatch = Cloud.shared.$user
            .map { $0?.id }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] userId in
                Task { @MainActor in
                    guard let self else { return }
                    if userId == nil {
                        self.handleSignedOut()
                    }
                }
            }
    }

    /// 供设置页开关绑定：未登录禁止开启
    func setEnabled(_ on: Bool) {
        lastError = nil
        if on {
            guard Cloud.shared.isSignedIn else {
                enabled = false
                UserDefaults.standard.set(false, forKey: Self.enabledKey)
                return
            }
            do {
                installedTargets = try HookInstaller().install()
                enabled = true
                UserDefaults.standard.set(true, forKey: Self.enabledKey)
                startWatcherIfNeeded()
            } catch {
                enabled = false
                UserDefaults.standard.set(false, forKey: Self.enabledKey)
                lastError = error.localizedDescription
            }
        } else {
            disableAndUninstall()
        }
    }

    func handleSignedOut() {
        disableAndUninstall()
    }

    func hookState(for sessionId: String) -> HookSessionState? {
        states[sessionId]
    }

    func isInteractivelyActive(sessionId: String, now: Date = Date()) -> Bool {
        guard let st = states[sessionId] else { return false }
        return st.interactiveOpen && now.timeIntervalSince(st.updatedAt) < 3600
    }

    private func disableAndUninstall() {
        stopWatcher()
        do {
            try HookInstaller().uninstall()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        installedTargets = []
        enabled = false
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
    }

    private func reconcileOnLaunch() {
        let installer = HookInstaller()
        let state = installer.inspectClaude()
        if !Cloud.shared.isSignedIn {
            // 未登录时若残留旧 hook，自动清理并保持关闭
            if state != .notInstalled {
                try? installer.uninstall()
            }
            enabled = false
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
            return
        }
        if enabled {
            switch state {
            case .notInstalled:
                // 用户手动删掉了 settings.json 里的 hook：同步把开关显示为关闭
                enabled = false
                UserDefaults.standard.set(false, forKey: Self.enabledKey)
            case .installed(let pathMatches):
                if !pathMatches {
                    installedTargets = (try? installer.install()) ?? ["Claude Code"]
                } else {
                    installedTargets = installer.installGeminiHooks ? ["Claude Code", "Antigravity CLI"] : ["Claude Code"]
                }
                startWatcherIfNeeded()
            }
        }
    }

    private func startWatcherIfNeeded() {
        guard watcher == nil else { return }
        let w = HookEventWatcher { [weak self] state, record in
            Task { @MainActor in
                guard let self else { return }
                self.states[state.sessionId] = state
                CloudSync.shared.hookStatusChanged(state, record: record)
            }
        }
        w.start()
        watcher = w
    }

    private func stopWatcher() {
        watcher?.stop()
        watcher = nil
    }
}
