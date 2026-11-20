import Foundation

// 统一的三来源远程指令执行器（Claude Code / Codex / Antigravity CLI）：
// - 权限沿用用户本机 CLI 自身配置，不注入 --dangerously-skip-permissions / --yolo
// - 逐行解析各家 JSONL / stream-json 输出，节流回报实时进度并提炼最终回复摘要
// - 支持超时自动终止，避免僵尸子进程

struct ProviderExecutionResult: Equatable {
    let succeeded: Bool
    let summary: String?
    let error: String?
    let resultSessionId: String?
}

struct ProviderCommandInvocation: Equatable {
    let executable: String
    let arguments: [String]
}

enum ProviderCommandBuilder {
    static func build(source: Source,
                      cliPath: String,
                      mode: CommandExecutionMode,
                      sessionId: String?,
                      prompt: String) throws -> ProviderCommandInvocation {
        switch source {
        case .claude:
            // 实测 claude 2.1.x：--print + --output-format stream-json 必须搭配 --verbose
            var args = ["-p"]
            switch mode {
            case .new:
                break
            case .resume:
                guard let sessionId, !sessionId.isEmpty else { throw ProviderRunnerError.missingSessionId }
                args.append(contentsOf: ["--resume", sessionId])
            case .fork:
                guard let sessionId, !sessionId.isEmpty else { throw ProviderRunnerError.missingSessionId }
                args.append(contentsOf: ["--resume", sessionId, "--fork-session"])
            }
            args.append(contentsOf: [prompt, "--output-format", "stream-json", "--verbose"])
            return ProviderCommandInvocation(executable: cliPath, arguments: args)

        case .codex:
            switch mode {
            case .new:
                return ProviderCommandInvocation(executable: cliPath, arguments: ["exec", "--json", prompt])
            case .resume:
                guard let sessionId, !sessionId.isEmpty else { throw ProviderRunnerError.missingSessionId }
                return ProviderCommandInvocation(executable: cliPath, arguments: ["exec", "resume", sessionId, "--json", prompt])
            case .fork:
                throw ProviderRunnerError.unsupportedMode("Codex CLI 不支持分支续聊（--fork-session）")
            }

        case .gemini:
            // 仅通过 Antigravity CLI (`agy`) 执行
            switch mode {
            case .new:
                return ProviderCommandInvocation(executable: cliPath, arguments: ["-p", prompt, "--output-format", "stream-json"])
            case .resume:
                guard let sessionId, !sessionId.isEmpty else { throw ProviderRunnerError.missingSessionId }
                return ProviderCommandInvocation(executable: cliPath, arguments: ["-p", prompt, "--conversation", sessionId, "--output-format", "stream-json"])
            case .fork:
                throw ProviderRunnerError.unsupportedMode("Antigravity CLI (agy) 暂不支持分支续聊")
            }
        }
    }
}

enum ProviderRunnerError: LocalizedError, Equatable {
    case missingSessionId
    case unsupportedMode(String)

    var errorDescription: String? {
        switch self {
        case .missingSessionId: return "缺少会话 ID"
        case .unsupportedMode(let msg): return msg
        }
    }
}

/// 逐行解析三家 CLI 的流式 JSON 输出，提取进度文本、最终回复摘要、错误与结果 session_id。
final class ProviderStreamParser {
    let source: Source

    private(set) var resultSessionId: String?
    private(set) var lastProgress: String?
    private(set) var finalResultText: String?
    private(set) var errorMessage: String?
    private(set) var explicitError = false

    private var assistantChunks: [String] = []
    private var rawLines: [String] = []

    init(source: Source) {
        self.source = source
    }

    /// 解析一行 stdout；若有新的进度文案返回给调用方做节流上报
    @discardableResult
    func consume(line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if rawLines.count < 200 { rawLines.append(trimmed) }

        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Antigravity CLI (agy) 使用顶层 "event" 字段而非 "type"
        if source == .gemini, let event = obj["event"] as? String {
            return parseAgy(event: event, obj: obj)
        }

        guard let type = obj["type"] as? String else { return nil }

        switch source {
        case .claude:
            return parseClaude(type: type, obj: obj)
        case .codex:
            return parseCodex(type: type, obj: obj)
        case .gemini:
            return parseGemini(type: type, obj: obj)
        }
    }

    func finalize(exitCode: Int32, stderrText: String) -> ProviderExecutionResult {
        let joined = assistantChunks.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let summaryCandidate = (finalResultText?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? (joined.isEmpty ? nil : joined)
            ?? (rawLines.last.flatMap { $0.hasPrefix("{") ? nil : $0 })

        let cleanStderr = Self.cleanError(stderrText)
        let ok = (exitCode == 0) && !explicitError
        if ok {
            let summary = summaryCandidate.map { Self.truncate($0, max: 4000) } ?? "执行完成（无文本输出）"
            return ProviderExecutionResult(succeeded: true, summary: summary, error: nil, resultSessionId: resultSessionId)
        } else {
            let err = errorMessage
                ?? (explicitError ? summaryCandidate : nil)
                ?? cleanStderr
                ?? "进程退出码 \(exitCode)"
            return ProviderExecutionResult(
                succeeded: false,
                summary: summaryCandidate.map { Self.truncate($0, max: 4000) },
                error: Self.truncate(err, max: 1000),
                resultSessionId: resultSessionId
            )
        }
    }

    private func parseClaude(type: String, obj: [String: Any]) -> String? {
        if let sid = obj["session_id"] as? String, !sid.isEmpty {
            resultSessionId = sid
        }
        switch type {
        case "system":
            if (obj["subtype"] as? String) == "init" {
                lastProgress = "Claude Code 会话已启动…"
                return lastProgress
            }
        case "assistant":
            if let msg = obj["message"] as? [String: Any],
               let content = msg["content"] as? [[String: Any]] {
                var texts: [String] = []
                var toolNames: [String] = []
                for block in content {
                    let kind = block["type"] as? String
                    if kind == "text", let text = block["text"] as? String, !text.isEmpty {
                        texts.append(text)
                    } else if kind == "tool_use", let name = block["name"] as? String {
                        toolNames.append(name)
                    }
                }
                if !texts.isEmpty {
                    let combined = texts.joined(separator: "\n")
                    assistantChunks.append(combined)
                    lastProgress = Self.truncate(combined, max: 300)
                    return lastProgress
                }
                if !toolNames.isEmpty {
                    lastProgress = "正在调用工具：\(toolNames.joined(separator: ", "))"
                    return lastProgress
                }
            }
        case "result":
            let isErr = (obj["is_error"] as? Bool) == true || (obj["subtype"] as? String) == "error"
            if let res = obj["result"] as? String, !res.isEmpty {
                if isErr {
                    explicitError = true
                    errorMessage = res
                } else {
                    finalResultText = res
                }
            } else if isErr {
                explicitError = true
            }
        default:
            break
        }
        return nil
    }

    private func parseCodex(type: String, obj: [String: Any]) -> String? {
        switch type {
        case "thread.started":
            if let tid = obj["thread_id"] as? String, !tid.isEmpty {
                resultSessionId = tid
            }
            lastProgress = "Codex 会话已启动…"
            return lastProgress
        case "item.completed", "item.updated":
            if let item = obj["item"] as? [String: Any] {
                let itemType = item["type"] as? String ?? ""
                if itemType == "agent_message", let text = item["text"] as? String, !text.isEmpty {
                    if type == "item.completed" {
                        assistantChunks.append(text)
                        finalResultText = text
                    }
                    lastProgress = Self.truncate(text, max: 300)
                    return lastProgress
                }
                if itemType == "command_execution", let cmd = item["command"] as? String {
                    lastProgress = "正在执行：\(Self.truncate(cmd, max: 160))"
                    return lastProgress
                }
            }
        case "turn.failed", "error":
            explicitError = true
            if let errObj = obj["error"] as? [String: Any], let msg = errObj["message"] as? String {
                errorMessage = msg
            } else if let msg = obj["message"] as? String {
                errorMessage = msg
            }
        default:
            break
        }
        return nil
    }

    private var agyStreamBuffer = ""

    private func parseAgy(event: String, obj: [String: Any]) -> String? {
        if let cid = obj["conversation_id"] as? String, !cid.isEmpty {
            resultSessionId = cid
        }
        switch event {
        case "init":
            lastProgress = "Antigravity 会话已启动…"
            return lastProgress
        case "step_update":
            guard let upd = obj["step_update"] as? [String: Any] else { return nil }
            if let cid = upd["conversation_id"] as? String, !cid.isEmpty {
                resultSessionId = cid
            }
            let stepType = (upd["step_type"] as? String ?? "").lowercased()
            if stepType == "agent_response", let delta = upd["text_delta"] as? String, !delta.isEmpty {
                agyStreamBuffer += delta
                let trimmed = agyStreamBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    lastProgress = Self.truncate(trimmed, max: 300)
                    return lastProgress
                }
            } else if !stepType.isEmpty, stepType != "user_input", stepType != "system_message", stepType != "agent_response" {
                lastProgress = "正在执行步骤：\(stepType)"
                return lastProgress
            }
        case "result":
            let resObj = (obj["result"] as? [String: Any]) ?? obj
            if let cid = resObj["conversation_id"] as? String, !cid.isEmpty {
                resultSessionId = cid
            }
            let status = (resObj["status"] as? String ?? "").uppercased()
            if status == "ERROR" || status == "FAILED" || status == "CANCELLED" {
                explicitError = true
                errorMessage = (resObj["error"] as? String)
                    ?? (resObj["message"] as? String)
                    ?? (resObj["response"] as? String)
                    ?? "Antigravity 执行失败（\(status)）"
            } else if let text = resObj["response"] as? String, !text.isEmpty {
                finalResultText = text
            } else if !agyStreamBuffer.isEmpty {
                finalResultText = agyStreamBuffer
            }
        case "error":
            explicitError = true
            let errObj = (obj["error"] as? [String: Any])
            errorMessage = (errObj?["message"] as? String)
                ?? (obj["error"] as? String)
                ?? (obj["message"] as? String)
                ?? "Antigravity 执行出错"
        default:
            break
        }
        return nil
    }

    private func parseGemini(type: String, obj: [String: Any]) -> String? {
        switch type {
        case "init":
            if let sid = obj["session_id"] as? String, !sid.isEmpty {
                resultSessionId = sid
            }
            lastProgress = "Antigravity CLI 会话已启动…"
            return lastProgress
        case "message":
            let role = (obj["role"] as? String ?? "").lowercased()
            if role == "assistant" || role == "model", let content = obj["content"] as? String, !content.isEmpty {
                assistantChunks.append(content)
                lastProgress = Self.truncate(assistantChunks.joined(), max: 300)
                return lastProgress
            }
        case "tool_use":
            if let tool = (obj["tool"] as? String) ?? (obj["tool_name"] as? String) {
                lastProgress = "正在调用工具：\(tool)"
                return lastProgress
            }
        case "error":
            explicitError = true
            if let msg = obj["message"] as? String, !msg.isEmpty {
                errorMessage = msg
            }
        case "result":
            if let status = obj["status"] as? String, status.lowercased() == "error" {
                explicitError = true
                if let err = obj["error"] as? String { errorMessage = err }
            }
            if let text = obj["response"] as? String, !text.isEmpty {
                finalResultText = text
            }
        default:
            break
        }
        return nil
    }

    private static func truncate(_ s: String, max: Int) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > max else { return trimmed }
        return String(trimmed.prefix(max)) + "…"
    }

    private static func cleanError(_ stderr: String) -> String? {
        let lines = stderr.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("Warning: Basic terminal") && !$0.hasPrefix("Warning: 256-color") }
        guard !lines.isEmpty else { return nil }
        return lines.prefix(6).joined(separator: "\n")
    }
}

/// 通过子进程执行三家 CLI 并流式读取 stdout/stderr。
final class SubprocessProviderRunner: Sendable {
    let timeout: TimeInterval
    let progressMinInterval: TimeInterval

    init(timeout: TimeInterval = 600, progressMinInterval: TimeInterval = 1.5) {
        self.timeout = timeout
        self.progressMinInterval = progressMinInterval
    }

    func run(source: Source,
             cliPath: String,
             mode: CommandExecutionMode,
             sessionId: String?,
             cwd: String,
             prompt: String,
             onProgress: @escaping @Sendable (String) -> Void) async -> ProviderExecutionResult {
        let invocation: ProviderCommandInvocation
        do {
            invocation = try ProviderCommandBuilder.build(
                source: source, cliPath: cliPath, mode: mode, sessionId: sessionId, prompt: prompt
            )
        } catch {
            return ProviderExecutionResult(succeeded: false, summary: nil, error: error.localizedDescription, resultSessionId: nil)
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.executeSync(source: source, invocation: invocation, cwd: cwd, onProgress: onProgress)
                continuation.resume(returning: result)
            }
        }
    }

    private func executeSync(source: Source,
                             invocation: ProviderCommandInvocation,
                             cwd: String,
                             onProgress: @escaping @Sendable (String) -> Void) -> ProviderExecutionResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: invocation.executable)
        proc.arguments = invocation.arguments
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        proc.standardInput = FileHandle.nullDevice

        // 继承用户环境并补充常见 CLI PATH
        var env = ProcessInfo.processInfo.environment
        let extraPath = CLICapabilityProber.defaultSearchDirectories().joined(separator: ":")
        env["PATH"] = extraPath
        env["TERM"] = "xterm-256color"
        proc.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        let parser = ProviderStreamParser(source: source)
        let ioQueue = DispatchQueue(label: "app.quotlet.runner-io")
        var outBuffer = Data()
        var errBuffer = Data()
        var lastProgressSentAt = Date.distantPast

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            ioQueue.sync {
                outBuffer.append(chunk)
                while let nl = outBuffer.firstIndex(of: 0x0A) {
                    let lineData = outBuffer[..<nl]
                    outBuffer.removeSubrange(...nl)
                    let line = String(decoding: lineData, as: UTF8.self)
                    if let progress = parser.consume(line: line) {
                        let now = Date()
                        if now.timeIntervalSince(lastProgressSentAt) >= self.progressMinInterval {
                            lastProgressSentAt = now
                            onProgress(progress)
                        }
                    }
                }
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            ioQueue.sync {
                if errBuffer.count < 65_536 {
                    errBuffer.append(chunk)
                }
            }
        }

        do {
            try proc.run()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            return ProviderExecutionResult(succeeded: false, summary: nil, error: "启动 CLI 失败：\(error.localizedDescription)", resultSessionId: nil)
        }

        let sem = DispatchSemaphore(value: 0)
        proc.terminationHandler = { _ in sem.signal() }
        let timedOut = sem.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            proc.terminate()
            _ = sem.wait(timeout: .now() + 2.0)
            if proc.isRunning { kill(proc.processIdentifier, SIGKILL) }
        }

        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        // 排空管道残留字节
        let tailOut = outPipe.fileHandleForReading.readDataToEndOfFile()
        let tailErr = errPipe.fileHandleForReading.readDataToEndOfFile()

        return ioQueue.sync {
            outBuffer.append(tailOut)
            if !outBuffer.isEmpty {
                for line in String(decoding: outBuffer, as: UTF8.self).split(whereSeparator: \.isNewline) {
                    parser.consume(line: String(line))
                }
            }
            if errBuffer.count < 65_536 { errBuffer.append(tailErr) }
            let stderrText = String(decoding: errBuffer, as: UTF8.self)
            if timedOut {
                return ProviderExecutionResult(
                    succeeded: false,
                    summary: parser.lastProgress,
                    error: "执行超时（超过 \(Int(timeout)) 秒），已终止进程。",
                    resultSessionId: parser.resultSessionId
                )
            }
            return parser.finalize(exitCode: proc.terminationStatus, stderrText: stderrText)
        }
    }
}
