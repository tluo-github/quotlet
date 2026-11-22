import SQLite3
import XCTest
@testable import Quotlet

final class GeminiTests: XCTestCase {
    func testCLIOnlyInstallationAndSessionsWithoutIDEOrQuota() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("agy-only-\(UUID().uuidString)")
        let bin = root.appendingPathComponent(".local/bin")
        let home = root.appendingPathComponent(".gemini")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let agy = bin.appendingPathComponent("agy")
        try Data("#!/bin/sh\n".utf8).write(to: agy)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: agy.path)
        let path = CLICapabilityProber.findExecutable(named: "agy", searchDirectories:
            CLICapabilityProber.defaultSearchDirectories(home: root.path, envPath: ""))
        XCTAssertEqual(path, agy.path)
        let installed = LocalSnapshot(sessions: [], messages: [], antigravityCLIPath: path)
        XCTAssertTrue(installed.hasAntigravityCLI)
        XCTAssertTrue(installed.hasGemini)
        XCTAssertNil(installed.geminiLimits)
        XCTAssertFalse(installed.only(.claude).hasAntigravityCLI)

        func write(_ id: String, _ text: String) throws {
            let dir = home.appendingPathComponent("antigravity-cli/brain/\(id)/.system_generated/logs")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try text.write(to: dir.appendingPathComponent("transcript.jsonl"), atomically: true, encoding: .utf8)
        }
        try write("complete", """
        {"type":"USER_INPUT","created_at":"2026-11-22T09:00:00Z","content":"CLI only"}
        {"type":"PLANNER_RESPONSE","created_at":"2026-11-22T09:00:05Z","model":"gemini-4-neon-high","input_tokens":1500,"output_tokens":120,"cache_read_tokens":200}
        """)
        try write("pending", """
        {"type":"USER_INPUT","created_at":"2026-11-22T09:01:00Z","content":"Waiting for a response"}
        """)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("antigravity").path))
        XCTAssertNil(GeminiAPI.activeHub(in: home))
        let files = GeminiLogs.files(modifiedAfter: .distantPast, in: home)
        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files.allSatisfy(\.isCLI))
        let parsed = files.map { GeminiLogs.parse(url: $0.url, id: $0.id, isCLI: $0.isCLI) }
        let built = GeminiLogs.build(parsed, metas: GeminiLogs.conversationMetas(in: home), cutoff: .distantPast, limits: nil)
        XCTAssertEqual(built.sessions.count, 2)
        XCTAssertEqual(built.messages.count, 1)
        XCTAssertEqual(built.messages.first?.tokens.total, 1820)
        XCTAssertTrue(built.sessions.allSatisfy { $0.sourceLabel == "Antigravity CLI" })
        let pending = try XCTUnwrap(built.sessions.first { $0.id == "gemini-pending" })
        XCTAssertEqual(pending.title, "Waiting for a response")
        XCTAssertEqual(pending.requests, 0)
        XCTAssertEqual(pending.tokens.total, 0)
        XCTAssertTrue(LocalSnapshot(sessions: built.sessions, messages: built.messages).hasAntigravityCLI)
        XCTAssertTrue(GeminiLogs.build(parsed, metas: [:], cutoff: Date(timeIntervalSince1970: 1_800_000_000), limits: nil).sessions.isEmpty)
    }

    func testDiscoversCLIHubWithoutIDEDirectory() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("agy-hub-\(UUID().uuidString)")
        let daemon = home.appendingPathComponent("antigravity-cli/daemon")
        try FileManager.default.createDirectory(at: daemon, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let data = try JSONSerialization.data(withJSONObject: [
            "pid": Int(ProcessInfo.processInfo.processIdentifier), "httpsPort": 4321,
            "httpPort": 4322, "csrfToken": "fixture-token", "lsVersion": "test",
        ])
        try data.write(to: daemon.appendingPathComponent("hub_test.json"))
        let hub = try XCTUnwrap(GeminiAPI.activeHub(in: home))
        XCTAssertEqual(hub.httpsPort, 4321)
        XCTAssertEqual(hub.httpPort, 4322)
        XCTAssertEqual(hub.csrfToken, "fixture-token")
    }

    func testGeminiProQuotaParsingOrderingAndWindows() throws {
        let now = Date(timeIntervalSince1970: 1_795_149_600) // 2026-11-20T04:40:00Z
        let jsonString = """
        {
          "response": {
            "groups": [
              {
                "displayName": "Gemini Models",
                "description": "Models within this group: Gemini 4 Neon, Gemini 4 Hydrogen, Orchestrator (Neon), Gemini 3.8 Flash",
                "buckets": [
                  {
                    "bucketId": "gemini-weekly",
                    "displayName": "Weekly Limit Remaining",
                    "window": "weekly",
                    "remainingFraction": 0.99272054,
                    "resetTime": "2026-11-27T04:39:32Z"
                  },
                  {
                    "bucketId": "gemini-5h",
                    "displayName": "Five Hour Limit Remaining",
                    "window": "5h",
                    "remainingFraction": 0.9745219,
                    "resetTime": "2026-11-20T09:39:32Z"
                  }
                ]
              },
              {
                "displayName": "Claude and GPT models",
                "buckets": [
                  {
                    "bucketId": "3p-weekly",
                    "displayName": "Weekly Limit Remaining",
                    "window": "weekly",
                    "remainingFraction": 0.75,
                    "resetTime": "2026-11-27T04:40:00Z"
                  },
                  {
                    "bucketId": "3p-5h",
                    "displayName": "Five Hour Limit Remaining",
                    "window": "5h",
                    "remainingFraction": 0.9,
                    "resetTime": "2026-11-20T09:40:00Z"
                  }
                ]
              },
              {
                "displayName": "Gemini 4 Argon",
                "buckets": [
                  {
                    "bucketId": "gemini-argon-wtu-weekly",
                    "displayName": "Gemini 4 Argon Weekly Limit",
                    "window": "weekly",
                    "remainingFraction": 1,
                    "resetTime": "2026-11-27T04:40:00Z"
                  }
                ]
              }
            ]
          }
        }
        """
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(jsonString.utf8)) as? [String: Any])
        let buckets = GeminiAPI.parseQuotaBuckets(from: root)
        XCTAssertEqual(buckets.count, 5)

        let limits = GeminiLimits(plan: "Pro", buckets: buckets, observedAt: now)
        XCTAssertEqual(limits.planTitle, "Pro")

        let items = limits.limitItems(now: now)
        XCTAssertEqual(items.count, 5)

        // 排序：Gemini 主组（5h → 周） → Gemini 4 Argon（周） → Claude / GPT（5h → 周）
        XCTAssertEqual(items.map(\.id), [
            "gemini-gemini-5h",
            "gemini-gemini-weekly",
            "gemini-gemini-argon-wtu-weekly",
            "gemini-3p-5h",
            "gemini-3p-weekly",
        ])

        // 0: Gemini 5h
        XCTAssertEqual(items[0].kind, "session")
        XCTAssertNil(items[0].scope)
        XCTAssertEqual(items[0].windowLength, 5 * 3600)
        XCTAssertEqual(items[0].percentText, "2.5%")
        XCTAssertTrue(items[0].detail?.contains("Gemini 4 Neon") == true)

        // 1: Gemini weekly
        XCTAssertEqual(items[1].kind, "weekly_all")
        XCTAssertNil(items[1].scope)
        XCTAssertEqual(items[1].windowLength, 7 * 86400)
        XCTAssertEqual(items[1].percentText, "0.7%")

        // 2: Gemini 4 Argon weekly
        XCTAssertEqual(items[2].kind, "weekly_scoped")
        XCTAssertEqual(items[2].scope, "Gemini 4 Argon")
        XCTAssertEqual(items[2].windowLength, 7 * 86400)
        XCTAssertEqual(items[2].percentText, "0%")

        // 3: Claude / GPT 5h
        XCTAssertEqual(items[3].kind, "session_scoped")
        XCTAssertEqual(items[3].scope, "Claude / GPT")
        XCTAssertEqual(items[3].windowLength, 5 * 3600)
        XCTAssertEqual(items[3].percentText, "10%")

        // 4: Claude / GPT weekly
        XCTAssertEqual(items[4].kind, "weekly_scoped")
        XCTAssertEqual(items[4].scope, "Claude / GPT")
        XCTAssertEqual(items[4].windowLength, 7 * 86400)
        XCTAssertEqual(items[4].percentText, "25%")
    }

    func testExpiredBucketResetsToZero() {
        let now = Date()
        let past = now.addingTimeInterval(-3600)
        let b = GeminiLimits.Bucket(
            id: "gemini-5h",
            groupName: "Gemini Models",
            displayName: "Five Hour Limit Remaining",
            window: "5h",
            remainingFraction: 0.2,
            resetTime: past
        )
        let items = GeminiLimits(plan: "Pro", buckets: [b], observedAt: now).limitItems(now: now)
        XCTAssertEqual(items.first?.percent, 0)
        XCTAssertNil(items.first?.resetsAt)
    }

    func testPlanParsingFromLoadCodeAssist() {
        let pro: [String: Any] = [
            "response": [
                "currentTier": ["id": "free-tier", "name": "Antigravity"],
                "paidTier": ["id": "g1-pro-tier", "name": "Google AI Pro"],
            ]
        ]
        XCTAssertEqual(GeminiLimits.parsePlan(fromLoadCodeAssist: pro), "Pro")

        let ultra: [String: Any] = [
            "response": [
                "paidTier": ["id": "g1-ultra-tier", "name": "Google AI Ultra"],
            ]
        ]
        XCTAssertEqual(GeminiLimits.parsePlan(fromLoadCodeAssist: ultra), "Ultra")

        let free: [String: Any] = [
            "response": [
                "currentTier": ["id": "free-tier", "name": "Antigravity"],
            ]
        ]
        XCTAssertEqual(GeminiLimits.parsePlan(fromLoadCodeAssist: free), "Free")
    }

    func testTranscriptDurationAndTokenParsing() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("transcript.jsonl")
        let content = """
        {"step_index":0,"type":"USER_INPUT","created_at":"2026-11-20T04:00:00Z","content":"Hello Gemini"}
        {"step_index":1,"type":"PLANNER_RESPONSE","created_at":"2026-11-20T04:00:01Z","model":"gemini-4-neon-high","input_tokens":2000,"cache_read_tokens":5000,"output_tokens":300,"tool_calls":[{"name":"read_file"}]}
        {"step_index":2,"type":"GENERIC","created_at":"2026-11-20T04:00:07Z","content":"file content"}
        {"step_index":3,"type":"PLANNER_RESPONSE","created_at":"2026-11-20T04:00:08Z","model":"gemini-4-neon-high","input_tokens":1000,"cache_read_tokens":8000,"output_tokens":450,"content":"Done!"}
        {"step_index":4,"type":"USER_INPUT","created_at":"2026-11-20T04:05:00Z","content":"Thanks"}
        """
        try content.write(to: file, atomically: true, encoding: .utf8)

        let parsed = GeminiLogs.parse(url: file, id: "conv-1")
        XCTAssertEqual(parsed.firstPrompt, "Hello Gemini")
        XCTAssertEqual(parsed.messages.count, 2)

        // 第一条带 tool_calls，耗时由下一条 GENERIC 的 created_at 结算：04:00:07 - 04:00:01 = 6s
        XCTAssertEqual(parsed.messages[0].tokens.input, 2000)
        XCTAssertEqual(parsed.messages[0].tokens.cacheRead, 5000)
        XCTAssertEqual(parsed.messages[0].tokens.output, 300)
        XCTAssertEqual(parsed.messages[0].duration ?? -1, 6.0, accuracy: 0.01)

        // 第二条后接 USER_INPUT（包含人工阅读等待），不计入耗时
        XCTAssertEqual(parsed.messages[1].tokens.output, 450)
        XCTAssertNil(parsed.messages[1].duration)
    }

    func testAdviceRecommendsGeminiWhenClaudeAndCodexAreTight() {
        let now = Date()
        let reset = now.addingTimeInterval(3600)
        let claude = [
            LimitItem(id: "c-5h", kind: "session", title: "5h", percent: 50, severity: nil, resetsAt: reset),
            LimitItem(id: "c-wk", kind: "weekly_all", title: "wk", percent: 99, severity: nil, resetsAt: reset),
        ]
        let codex = [
            LimitItem(id: "x-5h", kind: "session", title: "5h", percent: 67, severity: nil, resetsAt: reset),
            LimitItem(id: "x-wk", kind: "weekly_all", title: "wk", percent: 98, severity: nil, resetsAt: reset),
        ]
        let gemini = [
            LimitItem(id: "g-5h", kind: "session", title: "5h", percent: 2.5, severity: nil, resetsAt: reset),
            LimitItem(id: "g-wk", kind: "weekly_all", title: "wk", percent: 0.7, severity: nil, resetsAt: reset),
        ]
        let advice = Advice.make(claude: claude, codex: codex, gemini: gemini, now: now, threshold: 90)
        XCTAssertNotNil(advice)
        XCTAssertTrue(advice?.title.contains("Gemini") == true)
        XCTAssertTrue(advice?.reason.contains("Claude") == true)
        XCTAssertTrue(advice?.reason.contains("Codex") == true)
    }

    func testGeminiModelNameFormatting() {
        XCTAssertEqual(Fmt.modelName("gemini-4-neon-high"), "Gemini 4 Neon (High)")
        XCTAssertEqual(Fmt.modelName("gemini-3.8-flash-high"), "Gemini 3.8 Flash (High)")
        XCTAssertEqual(Fmt.modelName("gemini-2.5-pro"), "Gemini 2.5 Pro")
    }

    func testGeminiPricingCalculation() {
        let tokens = TokenCount(input: 1_000_000, output: 1_000_000, cacheRead: 1_000_000, cacheWrite: 0)
        let cost = Pricing.cost(model: "gemini-3.8-flash-high", tokens: tokens)
        XCTAssertNotNil(cost)
        if let cost {
            XCTAssertEqual(cost, 0.39375, accuracy: 0.0001)
        }
        // 内部预览代号不估算价格
        XCTAssertNil(Pricing.cost(model: "gemini-4-neon-high", tokens: tokens))
    }

    func testScansBothAntigravityIDEAndCLIDirectoriesAndWALMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gemini-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        func writeTranscript(appDir: String, id: String, prompt: String, ts: String) throws -> URL {
            let logDir = root.appendingPathComponent("\(appDir)/brain/\(id)/.system_generated/logs")
            try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
            let file = logDir.appendingPathComponent("transcript.jsonl")
            let content = """
            {"step_index":0,"type":"USER_INPUT","created_at":"\(ts)","content":"\(prompt)"}
            {"step_index":1,"type":"PLANNER_RESPONSE","created_at":"\(ts)","model":"gemini-4-neon-high","input_tokens":1500,"cache_read_tokens":200,"output_tokens":120,"content":"OK"}
            """
            try content.write(to: file, atomically: true, encoding: .utf8)
            return file
        }

        _ = try writeTranscript(
            appDir: "antigravity",
            id: "ide-conv-1",
            prompt: "<USER_REQUEST>\\nIDE 会话\\n</USER_REQUEST>\\n<ADDITIONAL_METADATA>meta</ADDITIONAL_METADATA>",
            ts: "2026-11-21T09:00:00Z"
        )
        _ = try writeTranscript(
            appDir: "antigravity-cli",
            id: "cli-conv-1",
            prompt: "<USER_REQUEST>\\n阅读一下这个项目\\n</USER_REQUEST>\\n<ADDITIONAL_METADATA>meta</ADDITIONAL_METADATA>",
            ts: "2026-11-21T09:37:15Z"
        )
        _ = try writeTranscript(
            appDir: "antigravity-cli",
            id: "cli-conv-untitled",
            prompt: "<USER_REQUEST>\\nReply with exactly: AGY_OK\\n</USER_REQUEST>\\n<ADDITIONAL_METADATA>meta</ADDITIONAL_METADATA>",
            ts: "2026-11-21T09:40:00Z"
        )

        // 在 antigravity-cli 的 SQLite 库中启用 WAL 并写入一条记录（保持打开连接以验证未 checkpoint 时也能读取）
        let cliDBPath = root.appendingPathComponent("antigravity-cli/conversation_summaries.db")
        var writerDB: OpaquePointer?
        XCTAssertEqual(sqlite3_open(cliDBPath.path, &writerDB), SQLITE_OK)
        defer { if let writerDB { sqlite3_close(writerDB) } }
        let initSQL = """
        PRAGMA journal_mode=WAL;
        CREATE TABLE conversation_summaries (conversation_id text PRIMARY KEY, title text, workspace_uris text);
        INSERT INTO conversation_summaries VALUES ('cli-conv-1', '阅读项目文档', '["file:///Users/dev/Code/sample-asr"]');
        INSERT INTO conversation_summaries VALUES ('cli-conv-untitled', '', '["file:///Users/dev/Code/quotlet"]');
        """
        XCTAssertEqual(sqlite3_exec(writerDB, initSQL, nil, nil, nil), SQLITE_OK)

        let files = GeminiLogs.files(modifiedAfter: Date.distantPast, in: root)
        XCTAssertEqual(files.count, 3)

        let byId = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        XCTAssertEqual(byId["ide-conv-1"]?.isCLI, false)
        XCTAssertEqual(byId["cli-conv-1"]?.isCLI, true)
        XCTAssertEqual(byId["cli-conv-untitled"]?.isCLI, true)

        let metas = GeminiLogs.conversationMetas(in: root)
        XCTAssertEqual(metas["cli-conv-1"]?.title, "阅读项目文档")
        XCTAssertEqual(metas["cli-conv-1"]?.project, "sample-asr")
        XCTAssertEqual(metas["cli-conv-1"]?.cwd, "/Users/dev/Code/sample-asr")

        let parsed = files.map { GeminiLogs.parse(url: $0.url, id: $0.id, isCLI: $0.isCLI) }
        let built = GeminiLogs.build(parsed, metas: metas, cutoff: Date.distantPast, limits: nil)
        XCTAssertEqual(built.sessions.count, 3)

        let sessionsById = Dictionary(uniqueKeysWithValues: built.sessions.map { ($0.id, $0) })
        XCTAssertEqual(sessionsById["gemini-cli-conv-1"]?.title, "阅读项目文档")
        XCTAssertEqual(sessionsById["gemini-cli-conv-1"]?.project, "sample-asr")
        XCTAssertEqual(sessionsById["gemini-cli-conv-1"]?.isAntigravityCLI, true)
        XCTAssertEqual(sessionsById["gemini-cli-conv-1"]?.sourceLabel, "Antigravity CLI")

        // 数据库 title 为空时，回退标题应自动剥离 <USER_REQUEST> 标签
        XCTAssertEqual(sessionsById["gemini-cli-conv-untitled"]?.title, "Reply with exactly: AGY_OK")
        XCTAssertEqual(sessionsById["gemini-cli-conv-untitled"]?.sourceLabel, "Antigravity CLI")
        XCTAssertEqual(sessionsById["gemini-ide-conv-1"]?.title, "IDE 会话")
        XCTAssertEqual(sessionsById["gemini-ide-conv-1"]?.isAntigravityCLI, false)
        XCTAssertEqual(sessionsById["gemini-ide-conv-1"]?.sourceLabel, "Gemini")
    }

    func testGeminiTranscriptTracksLiveActivityPhases() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("transcript.jsonl")
        let generating = """
        {"step_index":0,"type":"USER_INPUT","created_at":"2026-11-21T09:00:00Z","content":"Hi"}
        """
        try generating.write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(GeminiLogs.parse(url: file, id: "conv-live", isCLI: true).activity?.phase, .generating)

        let tools = generating + "\n" + """
        {"step_index":1,"type":"PLANNER_RESPONSE","created_at":"2026-11-21T09:00:02Z","model":"gemini-4-neon-high","input_tokens":500,"output_tokens":50,"tool_calls":[{"name":"run_command"}]}
        """
        try tools.write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(GeminiLogs.parse(url: file, id: "conv-live", isCLI: true).activity?.phase, .tools)

        let afterTool = tools + "\n" + """
        {"step_index":2,"type":"GENERIC","created_at":"2026-11-21T09:00:05Z","content":"ok"}
        """
        try afterTool.write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(GeminiLogs.parse(url: file, id: "conv-live", isCLI: true).activity?.phase, .generating)

        let done = afterTool + "\n" + """
        {"step_index":3,"type":"PLANNER_RESPONSE","created_at":"2026-11-21T09:00:09Z","model":"gemini-4-neon-high","input_tokens":800,"output_tokens":100,"content":"All set"}
        """
        try done.write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(GeminiLogs.parse(url: file, id: "conv-live", isCLI: true).activity?.phase, .idle)
    }
}
