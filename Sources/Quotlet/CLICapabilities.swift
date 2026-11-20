import Foundation

// 探测本机实际可用的 AI CLI 能力（Claude Code / Codex / Gemini CLI）。
// 不猜测参数：实测检查二进制路径、--version 与 --help 支持的标志，上报给 Quotlet Cloud。

struct ProviderCapability: Codable, Equatable {
    let available: Bool
    let cliPath: String?
    let version: String?
    let supportsNew: Bool
    let supportsResume: Bool
    let supportsFork: Bool
    let supportsHooks: Bool
    let note: String?

    enum CodingKeys: String, CodingKey {
        case available
        case cliPath = "cli_path"
        case version
        case supportsNew = "supports_new"
        case supportsResume = "supports_resume"
        case supportsFork = "supports_fork"
        case supportsHooks = "supports_hooks"
        case note
    }

    func jsonObject() -> [String: Any] {
        var d: [String: Any] = [
            "available": available,
            "supports_new": supportsNew,
            "supports_resume": supportsResume,
            "supports_fork": supportsFork,
            "supports_hooks": supportsHooks,
        ]
        if let cliPath { d["cli_path"] = cliPath }
        if let version { d["version"] = version }
        if let note { d["note"] = note }
        return d
    }
}

struct DeviceCapabilities: Codable, Equatable {
    let claude: ProviderCapability
    let codex: ProviderCapability
    let gemini: ProviderCapability

    subscript(_ source: Source) -> ProviderCapability {
        switch source {
        case .claude: return claude
        case .codex: return codex
        case .gemini: return gemini
        }
    }

    func jsonObject() -> [String: Any] {
        [
            "claude": claude.jsonObject(),
            "codex": codex.jsonObject(),
            "gemini": gemini.jsonObject(),
        ]
    }
}

enum CLICapabilityProber {
    typealias CommandOutput = (exitCode: Int32, stdout: String, stderr: String)
    typealias CommandRunner = (_ executable: String, _ arguments: [String], _ timeout: TimeInterval) -> CommandOutput?

    static func defaultSearchDirectories(home: String = FileManager.default.homeDirectoryForCurrentUser.path,
                                         envPath: String? = ProcessInfo.processInfo.environment["PATH"]) -> [String] {
        var dirs: [String] = []
        if let envPath {
            dirs.append(contentsOf: envPath.split(separator: ":").map(String.init))
        }
        dirs.append(contentsOf: [
            "\(home)/.local/bin",
            "\(home)/.claude/local",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.volta/bin",
            "\(home)/.asdf/shims",
            "\(home)/.bun/bin",
        ])
        // 也检查 nvm 安装的 node 全局命令目录
        let nvmRoot = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmRoot) {
            for v in versions.sorted().reversed() {
                dirs.append("\(nvmRoot)/\(v)/bin")
            }
        }
        var seen = Set<String>()
        return dirs.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func findExecutable(named name: String,
                               searchDirectories: [String] = defaultSearchDirectories(),
                               fileManager: FileManager = .default) -> String? {
        for dir in searchDirectories {
            let candidate = (dir as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: candidate, isDirectory: &isDir),
               !isDir.boolValue,
               fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    static func probeAll(searchDirectories: [String] = defaultSearchDirectories(),
                         overrides: [Source: String] = [:],
                         runner: CommandRunner = runSync) -> DeviceCapabilities {
        let agyPath = overrides[.gemini] ?? findExecutable(named: "agy", searchDirectories: searchDirectories)
        return DeviceCapabilities(
            claude: probeClaude(path: overrides[.claude] ?? findExecutable(named: "claude", searchDirectories: searchDirectories), runner: runner),
            codex: probeCodex(path: overrides[.codex] ?? findExecutable(named: "codex", searchDirectories: searchDirectories), runner: runner),
            gemini: probeGemini(path: agyPath, runner: runner)
        )
    }

    static func probeClaude(path: String?, runner: CommandRunner = runSync) -> ProviderCapability {
        guard let path else {
            return ProviderCapability(
                available: false, cliPath: nil, version: nil,
                supportsNew: false, supportsResume: false, supportsFork: false, supportsHooks: false,
                note: "未检测到 claude CLI"
            )
        }
        let version = firstLine(runner(path, ["--version"], 2.5)?.stdout)
        let help = runner(path, ["--help"], 2.5)?.stdout ?? ""
        let supportsPrint = help.contains("--print") || help.contains("-p")
        let supportsStream = help.contains("--output-format")
        let supportsResume = help.contains("--resume")
        let supportsFork = help.contains("--fork-session")
        let available = supportsPrint && supportsStream
        return ProviderCapability(
            available: available,
            cliPath: path,
            version: version,
            supportsNew: available,
            supportsResume: available && supportsResume,
            supportsFork: available && supportsResume && supportsFork,
            supportsHooks: true,
            note: available ? nil : "当前 claude CLI 版本不支持非交互 stream-json 输出"
        )
    }

    static func probeCodex(path: String?, runner: CommandRunner = runSync) -> ProviderCapability {
        guard let path else {
            return ProviderCapability(
                available: false, cliPath: nil, version: nil,
                supportsNew: false, supportsResume: false, supportsFork: false, supportsHooks: false,
                note: "未检测到 codex CLI（需安装 @openai/codex 或 brew install codex）"
            )
        }
        let version = firstLine(runner(path, ["--version"], 2.5)?.stdout)
        let execHelp = runner(path, ["exec", "--help"], 2.5)
        let helpText = (execHelp?.stdout ?? "") + "\n" + (execHelp?.stderr ?? "")
        let supportsExec = (execHelp?.exitCode == 0) && (helpText.contains("--json") || helpText.contains("exec"))
        let supportsResume = supportsExec && helpText.contains("resume")
        return ProviderCapability(
            available: supportsExec,
            cliPath: path,
            version: version,
            supportsNew: supportsExec,
            supportsResume: supportsResume,
            supportsFork: false,
            supportsHooks: false,
            note: supportsExec ? "支持通过 codex exec --json 执行（不支持分支续聊与 hooks）" : "当前 codex CLI 不支持 codex exec --json 非交互模式"
        )
    }

    /// 仅支持 Antigravity CLI (`agy`)，不再使用 gemini CLI。
    static func probeGemini(path: String?, runner: CommandRunner = runSync) -> ProviderCapability {
        guard let path else {
            return ProviderCapability(
                available: false, cliPath: nil, version: nil,
                supportsNew: false, supportsResume: false, supportsFork: false, supportsHooks: false,
                note: "未检测到 Antigravity CLI（agy）"
            )
        }
        let rawVer = firstLine(runner(path, ["--version"], 2.5)?.stdout)
        let version = rawVer.map { $0.lowercased().contains("agy") ? $0 : "agy \($0)" }
        let helpOut = runner(path, ["--help"], 2.5)
        let help = (helpOut?.stdout ?? "") + "\n" + (helpOut?.stderr ?? "")
        let supportsPrint = help.contains("--print") || help.contains("-p")
        let supportsStream = help.contains("--output-format")
        let supportsResume = help.contains("--conversation")
        let available = supportsPrint && supportsStream
        return ProviderCapability(
            available: available,
            cliPath: path,
            version: version,
            supportsNew: available,
            supportsResume: available && supportsResume,
            supportsFork: false,
            supportsHooks: false,
            note: available
                ? "通过 Antigravity CLI (agy) 执行，支持新建与续聊 Antigravity 会话"
                : "当前 Antigravity CLI (agy) 不支持 --print + --output-format stream-json"
        )
    }

    private static func firstLine(_ s: String?) -> String? {
        guard let s else { return nil }
        let line = s.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        return (line?.isEmpty == false) ? String(line!.prefix(64)) : nil
    }

    static func runSync(executable: String, arguments: [String], timeout: TimeInterval = 2.5) -> CommandOutput? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        proc.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do {
            try proc.run()
        } catch {
            return nil
        }

        let sem = DispatchSemaphore(value: 0)
        proc.terminationHandler = { _ in sem.signal() }
        if sem.wait(timeout: .now() + timeout) == .timedOut {
            proc.terminate()
            _ = sem.wait(timeout: .now() + 0.3)
            return nil
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return (
            proc.terminationStatus,
            String(decoding: outData, as: UTF8.self),
            String(decoding: errData, as: UTF8.self)
        )
    }
}
