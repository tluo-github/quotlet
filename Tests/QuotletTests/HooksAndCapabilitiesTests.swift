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
        XCTAssertEqual(targets, ["Claude Code", "Gemini CLI"])
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
}
