import XCTest
@testable import Quotlet

final class HooksAndCapabilitiesTests: XCTestCase {

    func testCLICapabilityProberDetectsThreeProvidersAccurately() {
        let runner: CLICapabilityProber.CommandRunner = { exe, args, _ in
            switch (exe, args) {
            case ("/mock/claude", ["--version"]):
                return (0, "2.1.327 (Claude Code)\n", "")
            case ("/mock/claude", ["--help"]):
                return (0, "Options: -p, --print, --output-format, --resume, --fork-session", "")
            case ("/mock/codex", ["--version"]):
                return (0, "codex-cli 0.42.0\n", "")
            case ("/mock/codex", ["exec", "--help"]):
                return (0, "Usage: codex exec [OPTIONS] [PROMPT]\n  --json\nCommands: resume", "")
            case ("/mock/agy", ["--version"]):
                return (0, "1.5.13\n", "")
            case ("/mock/agy", ["--help"]):
                return (0, "Usage of agy:\n  -p\n  --print\n  --conversation\n  --output-format", "")
            default:
                return nil
            }
        }

        let caps = CLICapabilityProber.probeAll(
            searchDirectories: [],
            overrides: [.claude: "/mock/claude", .codex: "/mock/codex", .gemini: "/mock/agy"],
            runner: runner
        )
        XCTAssertTrue(caps.claude.available)
        XCTAssertTrue(caps.claude.supportsNew)
        XCTAssertTrue(caps.claude.supportsResume)
        XCTAssertTrue(caps.claude.supportsFork)
        XCTAssertEqual(caps.claude.version, "2.1.327 (Claude Code)")

        XCTAssertTrue(caps.codex.available)
        XCTAssertTrue(caps.codex.supportsNew)
        XCTAssertTrue(caps.codex.supportsResume)
        XCTAssertFalse(caps.codex.supportsFork)
        XCTAssertFalse(caps.codex.supportsHooks)

        XCTAssertTrue(caps.gemini.available)
        XCTAssertEqual(caps.gemini.version, "agy 1.5.13")
        XCTAssertTrue(caps.gemini.supportsNew)
        XCTAssertTrue(caps.gemini.supportsResume)
        XCTAssertFalse(caps.gemini.supportsFork)
        XCTAssertFalse(caps.gemini.supportsHooks)

        // Missing codex or agy degrades gracefully
        let missingCodex = CLICapabilityProber.probeCodex(path: nil, runner: runner)
        XCTAssertFalse(missingCodex.available)
        XCTAssertNotNil(missingCodex.note)

        let missingAgy = CLICapabilityProber.probeGemini(path: nil, runner: runner)
        XCTAssertFalse(missingAgy.available)
        XCTAssertTrue(missingAgy.note?.contains("agy") == true)
    }

    func testHookCLISanitizesTruncatesAndRotatesEventsFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("quotlet-hook-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let eventsURL = dir.appendingPathComponent("events.jsonl")

        let longPrompt = String(repeating: "a", count: 140)
        let payload: [String: Any] = [
            "hook_event_name": "UserPromptSubmit",
            "session_id": "sess-123",
            "cwd": "/Users/dev/project",
            "prompt": longPrompt,
            "secret_extra_field": "should-not-be-saved",
        ]
        let input = try JSONSerialization.data(withJSONObject: payload)
        let record = HookCLI.parseRecord(from: input, now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.source, "claude")
        XCTAssertEqual(record?.sessionId, "sess-123")
        XCTAssertEqual(record?.prompt?.count, 80)

        // Append and rotate at tiny threshold (120 bytes)
        HookCLI.append(record!, to: eventsURL, rotateAt: 120)
        HookCLI.append(record!, to: eventsURL, rotateAt: 120)
        let rotated = dir.appendingPathComponent("events.jsonl.1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rotated.path))
        let content = try String(contentsOf: eventsURL)
        XCTAssertFalse(content.contains("secret_extra_field"))
    }

    func testHookStatusMapperAndWatcherTransitionsAndStaleFallback() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("quotlet-hook-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let eventsURL = dir.appendingPathComponent("events.jsonl")
        FileManager.default.createFile(atPath: eventsURL.path, contents: nil)

        var transitions: [(String, String?)] = []
        let watcher = HookEventWatcher(eventsURL: eventsURL) { state, _ in
            transitions.append((state.status, state.detail))
        }
        watcher.start()
        // Wait briefly for watcher setup
        Thread.sleep(forTimeInterval: 0.05)

        let base: Int64 = 1_700_000_000_000
        let seq: [HookEventRecord] = [
            HookEventRecord(source: "claude", hookEventName: "SessionStart", sessionId: "s1", cwd: "/tmp/p", notificationType: nil, message: nil, prompt: nil, toolName: nil, ts: base),
            HookEventRecord(source: "claude", hookEventName: "UserPromptSubmit", sessionId: "s1", cwd: "/tmp/p", notificationType: nil, message: nil, prompt: "run tests", toolName: nil, ts: base + 1000),
            // Repeated PostToolUse while already running should NOT trigger duplicate transition
            HookEventRecord(source: "claude", hookEventName: "PostToolUse", sessionId: "s1", cwd: "/tmp/p", notificationType: nil, message: nil, prompt: nil, toolName: "Bash", ts: base + 2000),
            HookEventRecord(source: "claude", hookEventName: "Notification", sessionId: "s1", cwd: "/tmp/p", notificationType: "permission_prompt", message: "Run npm test?", prompt: nil, toolName: nil, ts: base + 3000),
            // PostToolUse after waiting transitions back to running
            HookEventRecord(source: "claude", hookEventName: "PostToolUse", sessionId: "s1", cwd: "/tmp/p", notificationType: nil, message: nil, prompt: nil, toolName: "Bash", ts: base + 4000),
            HookEventRecord(source: "claude", hookEventName: "Stop", sessionId: "s1", cwd: "/tmp/p", notificationType: nil, message: nil, prompt: nil, toolName: nil, ts: base + 5000),
            HookEventRecord(source: "claude", hookEventName: "SessionEnd", sessionId: "s1", cwd: "/tmp/p", notificationType: nil, message: nil, prompt: nil, toolName: nil, ts: base + 6000),
        ]
        for r in seq { HookCLI.append(r, to: eventsURL) }
        watcher.drainNow()
        watcher.stop()

        XCTAssertEqual(transitions.map(\.0), ["idle", "running", "waiting", "running", "done", "ended"])
        XCTAssertEqual(transitions[1].1, "run tests")
        XCTAssertEqual(transitions[2].1, "Run npm test?")

        // Verify 10-minute stale fallback
        let running = HookSessionState(
            sessionId: "s2", source: "claude", status: "running", detail: nil,
            isPromptExcerpt: false, cwd: nil, updatedAt: Date(timeIntervalSince1970: 1000), interactiveOpen: true
        )
        XCTAssertEqual(running.effectiveStatus(now: Date(timeIntervalSince1970: 1599)), "running")
        XCTAssertEqual(running.effectiveStatus(now: Date(timeIntervalSince1970: 1600)), "idle")
    }

    func testHookInstallerMergesBacksUpRepairsAndUninstallsCleanly() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("quotlet-hook-inst-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let claudeSettings = dir.appendingPathComponent("claude-settings.json")
        let geminiSettings = dir.appendingPathComponent("gemini-settings.json")

        // Pre-populate with existing user config & user hook
        let existing: [String: Any] = [
            "theme": "dark",
            "hooks": [
                "PostToolUse": [
                    ["matcher": "Edit", "hooks": [["type": "command", "command": "echo user-hook"]]]
                ]
            ],
        ]
        try JSONSerialization.data(withJSONObject: existing).write(to: claudeSettings)

        let installer1 = HookInstaller(
            claudeSettingsURL: claudeSettings,
            geminiSettingsURL: geminiSettings,
            executablePath: "/Applications/Quotlet.app/Contents/MacOS/Quotlet",
            installGeminiHooks: true
        )
        let targets = try installer1.install()
        XCTAssertEqual(targets, ["Claude Code", "Antigravity CLI"])
        XCTAssertEqual(installer1.inspectClaude(), .installed(pathMatches: true))

        // Backup file should exist and preserve original without quotlet-hook
        let backup = dir.appendingPathComponent("claude-settings.json.quotlet-bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        let backupText = try String(contentsOf: backup)
        XCTAssertFalse(backupText.contains("# quotlet-hook"))

        // Existing user hook must still be preserved
        let afterInstall = try String(contentsOf: claudeSettings)
        XCTAssertTrue(afterInstall.contains("echo user-hook"))
        XCTAssertTrue(afterInstall.contains("# quotlet-hook"))

        // Simulate app moved to another path -> inspect detects mismatch -> reinstall repairs path
        let installer2 = HookInstaller(
            claudeSettingsURL: claudeSettings,
            geminiSettingsURL: geminiSettings,
            executablePath: "/Users/dev/Quotlet.app/Contents/MacOS/Quotlet",
            installGeminiHooks: true
        )
        XCTAssertEqual(installer2.inspectClaude(), .installed(pathMatches: false))
        _ = try installer2.install()
        XCTAssertEqual(installer2.inspectClaude(), .installed(pathMatches: true))

        // Uninstall removes ONLY quotlet-hook entries and keeps user hook & theme
        try installer2.uninstall()
        XCTAssertEqual(installer2.inspectClaude(), .notInstalled)
        let afterUninstallData = try Data(contentsOf: claudeSettings)
        let afterUninstall = try JSONSerialization.jsonObject(with: afterUninstallData) as? [String: Any]
        XCTAssertEqual(afterUninstall?["theme"] as? String, "dark")
        let remainingHooks = afterUninstall?["hooks"] as? [String: Any]
        XCTAssertEqual(remainingHooks?.keys.sorted(), ["PostToolUse"])
        let remainingText = String(decoding: afterUninstallData, as: UTF8.self)
        XCTAssertTrue(remainingText.contains("echo user-hook"))
        XCTAssertFalse(remainingText.contains("# quotlet-hook"))
    }

    func testClaudeStatusLineCLIParsesPersistsResetsExpiredAndForwardsWrappedCommand() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("quotlet-statusline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let settingsURL = dir.appendingPathComponent("settings.json")
        let wrappedURL = dir.appendingPathComponent("wrapped.json")
        let snapshotURL = dir.appendingPathComponent("limits.json")

        // Pre-populate settings.json with user's custom statusLine & unrelated keys
        let initial: [String: Any] = [
            "theme": "dark",
            "statusLine": [
                "type": "command",
                "command": "cat | sed 's/Opus/CUSTOM_OPUS/'",
                "padding": 2,
            ],
        ]
        try JSONSerialization.data(withJSONObject: initial).write(to: settingsURL)

        let installer1 = ClaudeStatusLineInstaller(
            claudeSettingsURL: settingsURL,
            wrappedConfigURL: wrappedURL,
            executablePath: "/Applications/Quotlet.app/Contents/MacOS/Quotlet"
        )
        try installer1.install()
        XCTAssertEqual(installer1.inspect(), .installed(pathMatches: true))

        // Simulate app move -> inspect detects path mismatch -> reinstall repairs while keeping wrapped command
        let installer2 = ClaudeStatusLineInstaller(
            claudeSettingsURL: settingsURL,
            wrappedConfigURL: wrappedURL,
            executablePath: "/Users/dev/Quotlet.app/Contents/MacOS/Quotlet"
        )
        XCTAssertEqual(installer2.inspect(), .installed(pathMatches: false))
        try installer2.install()
        XCTAssertEqual(installer2.inspect(), .installed(pathMatches: true))

        // Run CLI parser + saver + transparent forwarding
        let t0 = Date(timeIntervalSince1970: 1_774_000_000)
        let fiveReset: Double = 1_774_010_000   // +10,000s (future at t0)
        let sevenReset: Double = 1_774_500_000
        let payload = """
        {
          "session_id": "sess-sl-1",
          "model": { "display_name": "Opus" },
          "rate_limits": {
            "five_hour": { "used_percentage": 42.5, "resets_at": \(Int(fiveReset)) },
            "seven_day": { "used_percentage": 68.0, "resets_at": \(Int(sevenReset)) }
          }
        }
        """.data(using: .utf8)!

        let outPipe = Pipe()
        if let snap = ClaudeStatusLineCLI.parseSnapshot(from: payload, now: t0) {
            ClaudeStatusLineCLI.saveSnapshot(snap, to: snapshotURL)
        }
        ClaudeStatusLineCLI.forwardToWrappedCommandIfNeeded(
            stdinData: payload,
            wrappedConfigURL: wrappedURL,
            outputHandle: outPipe.fileHandleForWriting
        )
        try? outPipe.fileHandleForWriting.close()
        let forwarded = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertTrue(forwarded.contains("CUSTOM_OPUS"))

        let loaded = try XCTUnwrap(ClaudeStatusLineCLI.loadSnapshot(from: snapshotURL))
        XCTAssertEqual(loaded.sessionId, "sess-sl-1")
        XCTAssertEqual(loaded.fiveHour?.usedPercentage, 42.5)
        XCTAssertEqual(loaded.sevenDay?.usedPercentage, 68.0)

        let activeUsage = loaded.toUsageSnapshot(now: t0)
        XCTAssertEqual(activeUsage.session?.percent, 42.5)
        XCTAssertEqual(activeUsage.weekly?.percent, 68.0)

        // After five_hour reset passes, 5h resets to 0 while 7d stays intact
        let afterFiveReset = loaded.toUsageSnapshot(now: Date(timeIntervalSince1970: fiveReset + 60))
        XCTAssertEqual(afterFiveReset.session?.percent, 0)
        XCTAssertNil(afterFiveReset.session?.resetsAt)
        XCTAssertEqual(afterFiveReset.weekly?.percent, 68.0)

        // Uninstall restores user's exact original statusLine & keeps theme
        try installer2.uninstall()
        XCTAssertEqual(installer2.inspect(), .notInstalled)
        let restored = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any])
        XCTAssertEqual(restored["theme"] as? String, "dark")
        let sl = try XCTUnwrap(restored["statusLine"] as? [String: Any])
        XCTAssertEqual(sl["command"] as? String, "cat | sed 's/Opus/CUSTOM_OPUS/'")
        XCTAssertEqual(sl["padding"] as? Int, 2)
    }

    func testStatusLineIgnoresStaleIdleSessionAndAdvancesOnNewProgressOrCycle() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("quotlet-statusline-merge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let snapshotURL = dir.appendingPathComponent("limits.json")
        let wrappedURL = dir.appendingPathComponent("wrapped.json")

        let t1 = Date(timeIntervalSince1970: 1_795_663_000)
        let fiveReset: Int = 1_795_669_200   // Today 13:00
        let sevenReset: Int = 1_795_892_400  // Sunday 03:00

        func makePayload(session: String, fivePct: Double, fiveResetsAt: Int, sevenPct: Double, sevenResetsAt: Int) -> Data {
            """
            {
              "session_id": "\(session)",
              "model": { "display_name": "Opus 5.5" },
              "rate_limits": {
                "five_hour": { "used_percentage": \(fivePct), "resets_at": \(fiveResetsAt) },
                "seven_day": { "used_percentage": \(sevenPct), "resets_at": \(sevenResetsAt) }
              }
            }
            """.data(using: .utf8)!
        }

        // 1. Active Claude Code session reaches 97% / 53%
        let active97 = makePayload(session: "sess-active", fivePct: 97, fiveResetsAt: fiveReset, sevenPct: 53, sevenResetsAt: sevenReset)
        ClaudeStatusLineCLI.run(stdinData: active97, snapshotURL: snapshotURL, wrappedConfigURL: wrappedURL, now: t1)

        var loaded = try XCTUnwrap(ClaudeStatusLineCLI.loadSnapshot(from: snapshotURL))
        XCTAssertEqual(loaded.fiveHour?.usedPercentage, 97)
        XCTAssertEqual(loaded.sevenDay?.usedPercentage, 53)
        XCTAssertEqual(loaded.sessionId, "sess-active")
        XCTAssertEqual(loaded.observedAt.timeIntervalSince1970, t1.timeIntervalSince1970, accuracy: 0.002)

        // 2. Another idle terminal tab redraws its statusLine with cached 74% / 50% for the same window -> MUST NOT regress or bump observedAt
        let t2 = t1.addingTimeInterval(20)
        let idle74 = makePayload(session: "sess-idle", fivePct: 74, fiveResetsAt: fiveReset, sevenPct: 50, sevenResetsAt: sevenReset)
        ClaudeStatusLineCLI.run(stdinData: idle74, snapshotURL: snapshotURL, wrappedConfigURL: wrappedURL, now: t2)

        loaded = try XCTUnwrap(ClaudeStatusLineCLI.loadSnapshot(from: snapshotURL))
        XCTAssertEqual(loaded.fiveHour?.usedPercentage, 97)
        XCTAssertEqual(loaded.sevenDay?.usedPercentage, 53)
        XCTAssertEqual(loaded.sessionId, "sess-active")
        XCTAssertEqual(loaded.observedAt.timeIntervalSince1970, t1.timeIntervalSince1970, accuracy: 0.002)

        // 3. Same active session redraws on terminal resize without quota change -> observedAt stays at t1
        let t3 = t1.addingTimeInterval(40)
        ClaudeStatusLineCLI.run(stdinData: active97, snapshotURL: snapshotURL, wrappedConfigURL: wrappedURL, now: t3)
        loaded = try XCTUnwrap(ClaudeStatusLineCLI.loadSnapshot(from: snapshotURL))
        XCTAssertEqual(loaded.observedAt.timeIntervalSince1970, t1.timeIntervalSince1970, accuracy: 0.002)

        // 4. Active session progresses to 99% / 54% (with slight server reset-time jitter) -> updates cleanly
        let t4 = t1.addingTimeInterval(90)
        let active99 = makePayload(session: "sess-active", fivePct: 99, fiveResetsAt: fiveReset + 30, sevenPct: 54, sevenResetsAt: sevenReset)
        ClaudeStatusLineCLI.run(stdinData: active99, snapshotURL: snapshotURL, wrappedConfigURL: wrappedURL, now: t4)

        loaded = try XCTUnwrap(ClaudeStatusLineCLI.loadSnapshot(from: snapshotURL))
        XCTAssertEqual(loaded.fiveHour?.usedPercentage, 99)
        XCTAssertEqual(loaded.sevenDay?.usedPercentage, 54)
        XCTAssertEqual(loaded.observedAt.timeIntervalSince1970, t4.timeIntervalSince1970, accuracy: 0.002)

        // 5. After 5-hour window resets, a new turn starts the next 5-hour cycle at 2% -> replaces 99% while keeping 54% weekly
        let t5 = Date(timeIntervalSince1970: TimeInterval(fiveReset + 300))
        let nextFiveReset = fiveReset + 18_000
        let newCycle = makePayload(session: "sess-next", fivePct: 2, fiveResetsAt: nextFiveReset, sevenPct: 54, sevenResetsAt: sevenReset)
        ClaudeStatusLineCLI.run(stdinData: newCycle, snapshotURL: snapshotURL, wrappedConfigURL: wrappedURL, now: t5)

        loaded = try XCTUnwrap(ClaudeStatusLineCLI.loadSnapshot(from: snapshotURL))
        XCTAssertEqual(loaded.fiveHour?.usedPercentage, 2)
        XCTAssertEqual(loaded.fiveHour?.resetsAt?.timeIntervalSince1970 ?? 0, Double(nextFiveReset), accuracy: 1)
        XCTAssertEqual(loaded.sevenDay?.usedPercentage, 54)
        XCTAssertEqual(loaded.sessionId, "sess-next")

        // 6. Old idle terminal STILL holding expired 13:00 (74%) + stale 50% weekly redraws after reset -> ignored completely
        let t6 = t5.addingTimeInterval(60)
        ClaudeStatusLineCLI.run(stdinData: idle74, snapshotURL: snapshotURL, wrappedConfigURL: wrappedURL, now: t6)

        loaded = try XCTUnwrap(ClaudeStatusLineCLI.loadSnapshot(from: snapshotURL))
        XCTAssertEqual(loaded.fiveHour?.usedPercentage, 2)
        XCTAssertEqual(loaded.fiveHour?.resetsAt?.timeIntervalSince1970 ?? 0, Double(nextFiveReset), accuracy: 1)
        XCTAssertEqual(loaded.sevenDay?.usedPercentage, 54)
    }

    @MainActor
    func testStoreMergeStatusLinePreservesAPIMetadataAndRejectsRegression() {
        let now = Date(timeIntervalSince1970: 1_795_663_000)
        let fiveReset = Date(timeIntervalSince1970: 1_795_669_200)
        let sevenReset = Date(timeIntervalSince1970: 1_795_892_400)

        let apiSnap = UsageSnapshot(
            limits: [
                LimitItem(id: "s", kind: "session", title: "5h", percent: 85, severity: "normal", resetsAt: fiveReset),
                LimitItem(id: "w", kind: "weekly_all", title: "Week", percent: 52, severity: "normal", resetsAt: sevenReset),
                LimitItem(id: "ws", kind: "weekly_scoped", title: "Sonnet", percent: 15, severity: nil, resetsAt: sevenReset, scope: "Sonnet"),
            ],
            breakdown: [BreakdownRow(id: "claude_code", name: "Claude Code", percent: 90)],
            breakdownStart: now.addingTimeInterval(-86_400),
            extra: ExtraUsageInfo(enabled: false, used: 10, limit: 50, currency: "USD"),
            plan: "pro"
        )

        let freshStatusLine = UsageSnapshot(
            limits: [
                LimitItem(id: "sl-s", kind: "session", title: "5h", percent: 97, severity: nil, resetsAt: fiveReset),
                LimitItem(id: "sl-w", kind: "weekly_all", title: "Week", percent: 54, severity: nil, resetsAt: sevenReset),
            ],
            breakdown: [], breakdownStart: nil, extra: nil, plan: nil
        )
        let merged = Store.mergeStatusLineUsage(freshStatusLine, into: apiSnap, now: now)
        XCTAssertTrue(merged.progressed)
        XCTAssertEqual(merged.snapshot.session?.percent, 97)
        XCTAssertEqual(merged.snapshot.weekly?.percent, 54)
        XCTAssertEqual(merged.snapshot.plan, "pro")
        XCTAssertEqual(merged.snapshot.limits.count, 3)
        XCTAssertEqual(merged.snapshot.breakdown.count, 1)

        let staleStatusLine = UsageSnapshot(
            limits: [
                LimitItem(id: "sl-s", kind: "session", title: "5h", percent: 74, severity: nil, resetsAt: fiveReset),
                LimitItem(id: "sl-w", kind: "weekly_all", title: "Week", percent: 50, severity: nil, resetsAt: sevenReset),
            ],
            breakdown: [], breakdownStart: nil, extra: nil, plan: nil
        )
        let afterStale = Store.mergeStatusLineUsage(staleStatusLine, into: merged.snapshot, now: now)
        XCTAssertFalse(afterStale.progressed)
        XCTAssertEqual(afterStale.snapshot.session?.percent, 97)
        XCTAssertEqual(afterStale.snapshot.weekly?.percent, 54)
    }
}
