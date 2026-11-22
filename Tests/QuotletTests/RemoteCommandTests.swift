import XCTest
@testable import Quotlet

final class RemoteCommandTests: XCTestCase {

    func testProviderCommandBuilderMatchesVerifiedCLIFlags() throws {
        let claudeNew = try ProviderCommandBuilder.build(source: .claude, cliPath: "/bin/claude", mode: .new, sessionId: nil, prompt: "hello")
        XCTAssertEqual(claudeNew.arguments, ["-p", "hello", "--output-format", "stream-json", "--verbose"])

        let claudeResume = try ProviderCommandBuilder.build(source: .claude, cliPath: "/bin/claude", mode: .resume, sessionId: "s-1", prompt: "continue")
        XCTAssertEqual(claudeResume.arguments, ["-p", "--resume", "s-1", "continue", "--output-format", "stream-json", "--verbose"])

        let claudeFork = try ProviderCommandBuilder.build(source: .claude, cliPath: "/bin/claude", mode: .fork, sessionId: "s-1", prompt: "branch")
        XCTAssertEqual(claudeFork.arguments, ["-p", "--resume", "s-1", "--fork-session", "branch", "--output-format", "stream-json", "--verbose"])

        let codexNew = try ProviderCommandBuilder.build(source: .codex, cliPath: "/bin/codex", mode: .new, sessionId: nil, prompt: "fix bug")
        XCTAssertEqual(codexNew.arguments, ["exec", "--json", "fix bug"])

        let codexResume = try ProviderCommandBuilder.build(source: .codex, cliPath: "/bin/codex", mode: .resume, sessionId: "t-9", prompt: "more")
        XCTAssertEqual(codexResume.arguments, ["exec", "resume", "t-9", "--json", "more"])

        XCTAssertThrowsError(try ProviderCommandBuilder.build(source: .codex, cliPath: "/bin/codex", mode: .fork, sessionId: "t-9", prompt: "fork"))

        let agyNew = try ProviderCommandBuilder.build(source: .gemini, cliPath: "/Users/me/.local/bin/agy", mode: .new, sessionId: nil, prompt: "explain")
        XCTAssertEqual(agyNew.arguments, ["-p", "explain", "--output-format", "stream-json"])

        let agyResume = try ProviderCommandBuilder.build(source: .gemini, cliPath: "/Users/me/.local/bin/agy", mode: .resume, sessionId: "conv-uuid-1", prompt: "follow up")
        XCTAssertEqual(agyResume.arguments, ["-p", "follow up", "--conversation", "conv-uuid-1", "--output-format", "stream-json"])

        let agyPrefixedResume = try ProviderCommandBuilder.build(source: .gemini, cliPath: "/Users/me/.local/bin/agy", mode: .resume, sessionId: "gemini-conv-uuid-1", prompt: "follow up")
        XCTAssertEqual(agyPrefixedResume.arguments, ["-p", "follow up", "--conversation", "conv-uuid-1", "--output-format", "stream-json"])

        let codexPrefixedResume = try ProviderCommandBuilder.build(source: .codex, cliPath: "/bin/codex", mode: .resume, sessionId: "codex-t-9", prompt: "more")
        XCTAssertEqual(codexPrefixedResume.arguments, ["exec", "resume", "t-9", "--json", "more"])

        XCTAssertThrowsError(try ProviderCommandBuilder.build(source: .gemini, cliPath: "/Users/me/.local/bin/agy", mode: .fork, sessionId: "conv-uuid-1", prompt: "fork"))
    }

    func testStreamParsersHandleClaudeCodexAndGeminiJSONL() {
        // Claude stream-json
        let cp = ProviderStreamParser(source: .claude)
        XCTAssertNotNil(cp.consume(line: #"{"type":"system","subtype":"init","session_id":"c-sess-1"}"#))
        let toolProgress = cp.consume(line: #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}"#)
        XCTAssertEqual(toolProgress, "正在调用工具：Bash")
        _ = cp.consume(line: #"{"type":"assistant","message":{"content":[{"type":"text","text":"Draft answer"}]}}"#)
        _ = cp.consume(line: #"{"type":"result","subtype":"success","is_error":false,"result":"All 44 tests passed.","session_id":"c-sess-1"}"#)
        let cRes = cp.finalize(exitCode: 0, stderrText: "")
        XCTAssertTrue(cRes.succeeded)
        XCTAssertEqual(cRes.summary, "All 44 tests passed.")
        XCTAssertEqual(cRes.resultSessionId, "c-sess-1")

        // Codex JSONL
        let xp = ProviderStreamParser(source: .codex)
        _ = xp.consume(line: #"{"type":"thread.started","thread_id":"codex-thread-42"}"#)
        _ = xp.consume(line: #"{"type":"item.completed","item":{"id":"i1","type":"agent_message","text":"Updated README and tests."}}"#)
        let xRes = xp.finalize(exitCode: 0, stderrText: "")
        XCTAssertTrue(xRes.succeeded)
        XCTAssertEqual(xRes.summary, "Updated README and tests.")
        XCTAssertEqual(xRes.resultSessionId, "codex-thread-42")

        // Gemini stream-json (both success and auth error)
        let gp = ProviderStreamParser(source: .gemini)
        _ = gp.consume(line: #"{"type":"init","session_id":"gem-cli-7"}"#)
        _ = gp.consume(line: #"{"type":"message","role":"assistant","content":"Hello "}"#)
        _ = gp.consume(line: #"{"type":"message","role":"assistant","content":"world"}"#)
        _ = gp.consume(line: #"{"type":"result","status":"success"}"#)
        let gRes = gp.finalize(exitCode: 0, stderrText: "")
        XCTAssertTrue(gRes.succeeded)
        XCTAssertEqual(gRes.summary, "Hello \nworld")
        XCTAssertEqual(gRes.resultSessionId, "gem-cli-7")

        let gpErr = ProviderStreamParser(source: .gemini)
        let gFail = gpErr.finalize(exitCode: 1, stderrText: "Warning: Basic terminal detected\nError authenticating: IneligibleTierError")
        XCTAssertFalse(gFail.succeeded)
        XCTAssertTrue(gFail.error?.contains("IneligibleTierError") == true)

        // Antigravity CLI (agy) stream-json
        let ap = ProviderStreamParser(source: .gemini)
        XCTAssertEqual(ap.consume(line: #"{"event":"init","conversation_id":"0a47852f-ace3-4ccb-aa7f-a02f6240d9e4","init":{"cwd":"/tmp"}}"#), "Antigravity 会话已启动…")
        XCTAssertEqual(ap.consume(line: #"{"event":"step_update","step_update":{"conversation_id":"0a47852f-ace3-4ccb-aa7f-a02f6240d9e4","step_index":1,"state":"ACTIVE","step_type":"agent_response","text_delta":"AGY_OK"}}"#), "AGY_OK")
        _ = ap.consume(line: #"{"event":"result","result":{"conversation_id":"0a47852f-ace3-4ccb-aa7f-a02f6240d9e4","status":"SUCCESS","response":"AGY_OK\n","num_turns":1}}"#)
        let aRes = ap.finalize(exitCode: 0, stderrText: "")
        XCTAssertTrue(aRes.succeeded)
        XCTAssertEqual(aRes.summary, "AGY_OK")
        XCTAssertEqual(aRes.resultSessionId, "0a47852f-ace3-4ccb-aa7f-a02f6240d9e4")
    }

    func testSecurityValidatorEnforces30DayAllowlistAndInteractiveConflictProtection() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("quotlet-sec-\(UUID().uuidString)")
        let validProj = dir.appendingPathComponent("quotlet")
        let oldProj = dir.appendingPathComponent("ancient")
        try FileManager.default.createDirectory(at: validProj, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: oldProj, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let recentSession = SessionSummary(
            id: "s-active", project: "quotlet", cwd: validProj.path, title: "Work",
            start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-60),
            tokens: TokenCount(), subagentTokens: 0, requests: 1, mainModel: "claude-opus-5-5", source: .claude
        )
        let oldSession = SessionSummary(
            id: "s-old", project: "ancient", cwd: oldProj.path, title: "Old",
            start: now.addingTimeInterval(-35 * 86400), end: now.addingTimeInterval(-31 * 86400),
            tokens: TokenCount(), subagentTokens: 0, requests: 1, mainModel: "claude-opus-5-5", source: .claude
        )
        let snap = LocalSnapshot(sessions: [recentSession, oldSession], messages: [])
        let caps = DeviceCapabilities(
            claude: ProviderCapability(available: true, cliPath: "/mock/claude", version: "2.1", supportsNew: true, supportsResume: true, supportsFork: true, supportsHooks: true, note: nil),
            codex: ProviderCapability(available: false, cliPath: nil, version: nil, supportsNew: false, supportsResume: false, supportsFork: false, supportsHooks: false, note: "codex missing"),
            gemini: ProviderCapability(available: true, cliPath: "/mock/gemini", version: "0.68", supportsNew: true, supportsResume: false, supportsFork: false, supportsHooks: true, note: "Antigravity not resumable")
        )

        let validator = CommandSecurityValidator(isInteractiveActive: { sid, _, _ in sid == "s-active" })

        // 1. Project older than 30 days -> rejected
        let oldCmd = RemoteCommand(id: "c1", deviceId: "m1", provider: "claude", mode: "new", sessionId: nil, project: "ancient", prompt: "hi", status: "queued", createdAt: 0)
        if case .rejected(let reason) = validator.validate(command: oldCmd, capabilities: caps, local: snap, now: now) {
            XCTAssertTrue(reason.contains("30"))
        } else {
            XCTFail("Expected old project to be rejected")
        }

        // 2. Path traversal project -> rejected
        let badProjCmd = RemoteCommand(id: "c2", deviceId: "m1", provider: "claude", mode: "new", sessionId: nil, project: "../etc", prompt: "hi", status: "queued", createdAt: 0)
        if case .rejected = validator.validate(command: badProjCmd, capabilities: caps, local: snap, now: now) {
            // ok
        } else {
            XCTFail("Expected path traversal project to be rejected")
        }

        // 3. Active interactive session -> resume rejected with --fork-session guidance
        let resumeActive = RemoteCommand(id: "c3", deviceId: "m1", provider: "claude", mode: "resume", sessionId: "s-active", project: "quotlet", prompt: "hi", status: "queued", createdAt: 0)
        if case .rejected(let reason) = validator.validate(command: resumeActive, capabilities: caps, local: snap, now: now) {
            XCTAssertTrue(reason.contains("--fork-session"))
        } else {
            XCTFail("Expected active interactive session resume to be rejected")
        }

        // 4. Same active session with fork -> approved!
        let forkActive = RemoteCommand(id: "c4", deviceId: "m1", provider: "claude", mode: "fork", sessionId: "s-active", project: "quotlet", prompt: "hi", status: "queued", createdAt: 0)
        if case .approved(let src, let mode, let cwd, _) = validator.validate(command: forkActive, capabilities: caps, local: snap, now: now) {
            XCTAssertEqual(src, .claude)
            XCTAssertEqual(mode, .fork)
            XCTAssertEqual(cwd, URL(fileURLWithPath: validProj.path).standardizedFileURL.resolvingSymlinksInPath().path)
        } else {
            XCTFail("Expected fork on active session to be approved")
        }

        // 5. Unavailable codex -> rejected
        let codexCmd = RemoteCommand(id: "c5", deviceId: "m1", provider: "codex", mode: "new", sessionId: nil, project: "quotlet", prompt: "hi", status: "queued", createdAt: 0)
        if case .rejected(let reason) = validator.validate(command: codexCmd, capabilities: caps, local: snap, now: now) {
            XCTAssertEqual(reason, "codex missing")
        } else {
            XCTFail("Expected missing codex to be rejected")
        }

        // 6. Gemini resume -> rejected; Gemini new -> approved
        let gemResume = RemoteCommand(id: "c6", deviceId: "m1", provider: "gemini", mode: "resume", sessionId: "s-active", project: "quotlet", prompt: "hi", status: "queued", createdAt: 0)
        if case .rejected = validator.validate(command: gemResume, capabilities: caps, local: snap, now: now) {
            // ok
        } else {
            XCTFail("Expected gemini resume to be rejected")
        }
        let gemNew = RemoteCommand(id: "c7", deviceId: "m1", provider: "gemini", mode: "new", sessionId: nil, project: "quotlet", prompt: "hi", status: "queued", createdAt: 0)
        if case .approved(let src, let mode, _, _) = validator.validate(command: gemNew, capabilities: caps, local: snap, now: now) {
            XCTAssertEqual(src, .gemini)
            XCTAssertEqual(mode, .new)
        } else {
            XCTFail("Expected gemini new session to be approved")
        }

        // 7. TTY process list detection
        let psOut = """
        TTY      ARGS
        ??       /usr/local/bin/claude -p --resume sess-bg
        ttys003  claude --resume sess-tty
        """
        XCTAssertFalse(CommandSecurityValidator.detectTTYSessionInProcessList(psOut, sessionId: "sess-bg"))
        XCTAssertTrue(CommandSecurityValidator.detectTTYSessionInProcessList(psOut, sessionId: "sess-tty"))
    }

    func testCommandHistoryStorePersistsAndCapsEntries() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("quotlet-hist-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("commands-history.json")

        let store = CommandHistoryStore(fileURL: file, maxEntries: 2)
        for i in 1...3 {
            store.upsert(CommandHistoryEntry(
                id: "cmd-\(i)", provider: "claude", mode: "new", sessionId: nil,
                project: "quotlet", resolvedCwd: "/tmp/quotlet", prompt: "p\(i)",
                status: "done", result: "ok \(i)", error: nil, resultSessionId: nil,
                receivedAt: Date(timeIntervalSince1970: Double(i * 1000)), finishedAt: Date()
            ))
        }
        XCTAssertEqual(store.all().map(\.id), ["cmd-3", "cmd-2"])

        let reloaded = CommandHistoryStore(fileURL: file, maxEntries: 2)
        XCTAssertEqual(reloaded.all().map(\.id), ["cmd-3", "cmd-2"])

        // Single delete persists across reload
        reloaded.remove(id: "cmd-2")
        XCTAssertEqual(CommandHistoryStore(fileURL: file, maxEntries: 2).all().map(\.id), ["cmd-3"])

        // Clear finished keeps running entries
        reloaded.upsert(CommandHistoryEntry(
            id: "cmd-run", provider: "claude", mode: "new", sessionId: nil,
            project: "quotlet", resolvedCwd: "/tmp/quotlet", prompt: "running",
            status: "running", result: nil, error: nil, resultSessionId: nil,
            receivedAt: Date(), finishedAt: nil
        ))
        reloaded.clearFinished()
        XCTAssertEqual(CommandHistoryStore(fileURL: file, maxEntries: 2).all().map(\.id), ["cmd-run"])
    }

    func testSubprocessProviderRunnerStreamsAndEnforcesTimeout() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("quotlet-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Mock CLI emitting Claude stream-json lines
        let mockCLI = dir.appendingPathComponent("mock-claude.sh")
        let script = """
        #!/bin/sh
        echo '{"type":"system","subtype":"init","session_id":"mock-sess-99"}'
        echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Working on it"}]}}'
        echo '{"type":"result","subtype":"success","is_error":false,"result":"Mock reply OK","session_id":"mock-sess-99"}'
        """
        try script.write(to: mockCLI, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mockCLI.path)

        let runner = SubprocessProviderRunner(timeout: 5, progressMinInterval: 0)
        var progressUpdates: [String] = []
        let lock = NSLock()
        let res = await runner.run(
            source: .claude, cliPath: mockCLI.path, mode: .new, sessionId: nil,
            cwd: dir.path, prompt: "hello",
            onProgress: { p in
                lock.lock()
                progressUpdates.append(p)
                lock.unlock()
            }
        )
        XCTAssertTrue(res.succeeded)
        XCTAssertEqual(res.summary, "Mock reply OK")
        XCTAssertEqual(res.resultSessionId, "mock-sess-99")
        XCTAssertFalse(progressUpdates.isEmpty)

        // Timeout enforcement
        let slowCLI = dir.appendingPathComponent("slow-cli.sh")
        try "#!/bin/sh\nsleep 10\n".write(to: slowCLI, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: slowCLI.path)
        let fastTimeoutRunner = SubprocessProviderRunner(timeout: 0.4, progressMinInterval: 0)
        let timeoutRes = await fastTimeoutRunner.run(
            source: .claude, cliPath: slowCLI.path, mode: .new, sessionId: nil,
            cwd: dir.path, prompt: "hang", onProgress: { _ in }
        )
        XCTAssertFalse(timeoutRes.succeeded)
        XCTAssertTrue(timeoutRes.error?.contains("超时") == true)

        // Active cancellation via ExecutionCancelToken
        let cancelToken = ExecutionCancelToken()
        let cancelRunner = SubprocessProviderRunner(timeout: 10, progressMinInterval: 0)
        Task.detached {
            try? await Task.sleep(for: .milliseconds(250))
            cancelToken.cancel()
        }
        let started = Date()
        let cancelRes = await cancelRunner.run(
            source: .claude, cliPath: slowCLI.path, mode: .new, sessionId: nil,
            cwd: dir.path, prompt: "cancel me", cancelToken: cancelToken, onProgress: { _ in }
        )
        XCTAssertTrue(cancelRes.cancelled)
        XCTAssertFalse(cancelRes.succeeded)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3.0)
    }

    func testLoopbackURLsBypassHTTPProxy() {
        let localURL = URL(string: "http://127.0.0.1:8787/api/commands/poll")!
        let sessions = Network.sessions(for: localURL, allowFallback: true)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertNil(sessions[0].configuration.connectionProxyDictionary)
    }

    func testCommandStatusOutboxPersistsCoalescesAndProtectsTerminalStates() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("quotlet-outbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("outbox.json")

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let outbox = CommandStatusOutbox(fileURL: file, maxEntries: 3, maxAge: 3600, now: t0)

        // Running -> Done coalesces on same commandId
        outbox.upsert(PendingCommandReport(
            commandId: "cmd-1", status: "running", progress: "step 1", result: nil, error: nil,
            resultSessionId: nil, updatedAt: t0, attempts: 0
        ), now: t0)
        outbox.upsert(PendingCommandReport(
            commandId: "cmd-1", status: "done", progress: nil, result: "Finished OK", error: nil,
            resultSessionId: "sess-1", updatedAt: t0.addingTimeInterval(5), attempts: 0
        ), now: t0.addingTimeInterval(5))

        // Late non-terminal update must not overwrite terminal status
        outbox.upsert(PendingCommandReport(
            commandId: "cmd-1", status: "running", progress: "late progress", result: nil, error: nil,
            resultSessionId: nil, updatedAt: t0.addingTimeInterval(6), attempts: 0
        ), now: t0.addingTimeInterval(6))

        outbox.recordAttempt(commandId: "cmd-1")

        let reloaded = CommandStatusOutbox(fileURL: file, maxEntries: 3, maxAge: 3600, now: t0.addingTimeInterval(10))
        let items = reloaded.all(now: t0.addingTimeInterval(10))
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].status, "done")
        XCTAssertEqual(items[0].result, "Finished OK")
        XCTAssertEqual(items[0].resultSessionId, "sess-1")
        XCTAssertEqual(items[0].attempts, 1)

        // Expiration prunes stale entries
        XCTAssertTrue(reloaded.all(now: t0.addingTimeInterval(4000)).isEmpty)

        // Remove & clear
        reloaded.remove(commandId: "cmd-1")
        XCTAssertEqual(reloaded.count, 0)
    }

    func testSubprocessEnvironmentInjectsConfiguredProxyWithLoopbackBypass() {
        let suite = "QuotletTests.ProxyEnv.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: Network.Key.enabled)
        defaults.set("127.0.0.1", forKey: Network.Key.host)
        defaults.set(7890, forKey: Network.Key.port)

        let env = SubprocessProviderRunner.buildEnvironment(base: [:], defaults: defaults)
        XCTAssertEqual(env["HTTPS_PROXY"], "http://127.0.0.1:7890")
        XCTAssertEqual(env["http_proxy"], "http://127.0.0.1:7890")
        XCTAssertEqual(env["ALL_PROXY"], "http://127.0.0.1:7890")
        XCTAssertTrue(env["NO_PROXY"]?.contains("127.0.0.1") == true)
        XCTAssertTrue(env["NO_PROXY"]?.contains("localhost") == true)

        defaults.set(false, forKey: Network.Key.enabled)
        let directEnv = SubprocessProviderRunner.buildEnvironment(base: [:], defaults: defaults)
        XCTAssertNil(directEnv["HTTPS_PROXY"])
    }
}
