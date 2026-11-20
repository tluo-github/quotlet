import Foundation
import XCTest
@testable import Quotlet

final class ThroughputTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func message(end: Double, duration: Double?, output: Int, source: Source = .codex, model: String = "test") -> MessageUsage {
        MessageUsage(ts: now.addingTimeInterval(end), model: model, tokens: TokenCount(output: output), source: source, duration: duration)
    }

    func testParallelRequestsAddAndIdleRemainsZero() {
        let snapshot = LocalSnapshot(sessions: [], messages: [
            message(end: -2, duration: 10, output: 1000),
            message(end: -4, duration: 4, output: 200, source: .claude)
        ])
        let points = Throughput(snapshot: snapshot, now: now).points(seconds: 20)
        XCTAssertEqual(points.first!.total, 0)
        XCTAssertEqual(points.first { $0.date == now.addingTimeInterval(-6) }!.measured, 150)
        XCTAssertEqual(points.last!.total, 0)
        // 每秒桶的积分等于所有请求的输出，且不包含输入、缓存 token。
        XCTAssertEqual(points.reduce(0) { $0 + $1.measured }, 1200, accuracy: 0.001)
    }

    func testShortRepliesPreserveTokenTotal() {
        let snapshot = LocalSnapshot(sessions: [], messages: [message(end: -0.1, duration: 0.25, output: 10)])
        let points = Throughput(snapshot: snapshot, now: now).points(seconds: 5)
        XCTAssertEqual(points.reduce(0) { $0 + $1.total }, 10, accuracy: 0.001)
    }

    func testEstimateUsesSameSourceAndModelAndExpires() {
        var activity = LiveActivity(id: "active", source: .codex, model: "test")
        activity.update(.generating, at: now.addingTimeInterval(-3))
        let snapshot = LocalSnapshot(sessions: [], messages: [
            message(end: -20, duration: 10, output: 1000),
            message(end: -10, duration: 5, output: 1000),
            message(end: -9, duration: 1, output: 9000, source: .claude),
            message(end: -8, duration: 1, output: 8000, model: "other")
        ], liveActivities: [activity])
        let speed = Throughput(snapshot: snapshot, now: now)
        XCTAssertEqual(speed.generating, 1)
        XCTAssertEqual(speed.estimatedSpeed, 2000.0 / 15, accuracy: 0.001)
        XCTAssertEqual(speed.points(seconds: 5).last!.estimated, 2000.0 / 15, accuracy: 0.001)
        let stale = Throughput(snapshot: snapshot, now: now.addingTimeInterval(120))
        XCTAssertEqual(stale.generating, 0)
        XCTAssertEqual(stale.estimatedSpeed, 0)
    }

    func testToolsUnknownTimingAndUnfinalizedUsageDoNotInventSpeed() {
        var activity = LiveActivity(id: "tool", source: .codex, model: "test")
        activity.update(.tools, at: now.addingTimeInterval(-1))
        var unfinished = message(end: -1, duration: 1, output: 100)
        unfinished.isFinal = false
        let snapshot = LocalSnapshot(sessions: [], messages: [
            message(end: -1, duration: nil, output: 500),
            message(end: -1, duration: .nan, output: 500),
            message(end: -1, duration: -1, output: 500), unfinished
        ], liveActivities: [activity])
        let speed = Throughput(snapshot: snapshot, now: now)
        XCTAssertEqual(speed.tools, 1)
        XCTAssertEqual(speed.generating, 0)
        XCTAssertFalse(speed.hasEstimate)
        XCTAssertTrue(speed.points(seconds: 5).allSatisfy { $0.total == 0 })
    }

    func testGlobalReadingCombinesGeneratingAndRecentlyFinishedSources() {
        var codex = LiveActivity(id: "codex", source: .codex, model: "test")
        codex.update(.generating, at: now.addingTimeInterval(-3))
        var claude = LiveActivity(id: "claude", source: .claude, model: "test")
        claude.update(.generating, at: now.addingTimeInterval(-2))
        let snapshot = LocalSnapshot(sessions: [], messages: [
            message(end: -11, duration: 2, output: 40, source: .claude),
            message(end: -10, duration: 5, output: 500),
            message(end: 0, duration: 1, output: 30, source: .gemini)
        ], liveActivities: [codex, claude])
        let speed = Throughput(snapshot: snapshot, now: now)
        let readings = Dictionary(uniqueKeysWithValues: speed.readings.map { ($0.source, $0) })
        XCTAssertEqual(readings[.codex]?.speed, 100)
        XCTAssertEqual(readings[.claude]?.speed, 20)
        XCTAssertEqual(readings[.gemini]?.speed, 30)
        XCTAssertEqual(speed.currentSpeed, 150)
        XCTAssertFalse(speed.currentIsPartial)
        XCTAssertTrue(speed.readings.allSatisfy(\.detected))
    }

    func testGlobalReadingDoesNotAddSpeedsFromDifferentMoments() {
        let snapshot = LocalSnapshot(sessions: [], messages: [
            message(end: -3, duration: 1, output: 100, source: .codex),
            message(end: -1, duration: 1, output: 20, source: .claude)
        ])
        let speed = Throughput(snapshot: snapshot, now: now)
        XCTAssertEqual(speed.currentSpeed, 20)
        XCTAssertEqual(speed.readings.first { $0.source == .codex }?.speed, 0)
    }

    func testUnknownActiveSourceMarksGlobalTotalAsPartial() {
        var codex = LiveActivity(id: "codex", source: .codex, model: "new-model")
        codex.update(.generating, at: now.addingTimeInterval(-3))
        var claude = LiveActivity(id: "claude", source: .claude, model: "test")
        claude.update(.generating, at: now.addingTimeInterval(-1))
        let snapshot = LocalSnapshot(sessions: [], messages: [
            message(end: -5, duration: 2, output: 40, source: .claude)
        ], liveActivities: [codex, claude])
        let speed = Throughput(snapshot: snapshot, now: now)
        XCTAssertEqual(speed.currentSpeed, 20)
        XCTAssertTrue(speed.currentIsPartial)
        XCTAssertTrue(speed.readings.first { $0.source == .codex }!.isPartial)
        XCTAssertFalse(speed.readings.first { $0.source == .gemini }!.detected)
    }

    func testCodexTimingDeduplicationAndPhases() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("throughput-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let lines = [
            #"{"timestamp":"2026-11-20T00:00:00Z","type":"session_meta","payload":{"id":"test"}}"#,
            #"{"timestamp":"2026-11-20T00:00:00Z","type":"turn_context","payload":{"model":"test"}}"#,
            #"{"timestamp":"2026-11-20T00:00:01Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"timestamp":"2026-11-20T00:00:11Z","type":"event_msg","payload":{"type":"token_usage_record"}}"#,
            #"{"timestamp":"2026-11-20T00:00:12Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":1100},"last_token_usage":{"input_tokens":100,"output_tokens":1000}}}}"#,
            #"{"timestamp":"2026-11-20T00:00:12Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":1100},"last_token_usage":{"input_tokens":100,"output_tokens":1000}}}}"#,
            #"{"timestamp":"2026-11-20T00:00:13Z","type":"response_item","payload":{"type":"function_call","name":"test"}}"#
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        let parsed = CodexLogs.parse(url: file)
        XCTAssertEqual(parsed.messages.count, 1)
        XCTAssertEqual(parsed.messages.first?.duration, 10)
        XCTAssertEqual(parsed.messages.first?.ts, SessionScanner.date("2026-11-20T00:00:11Z"))
        XCTAssertEqual(parsed.activity?.phase, .tools)
        let end = #"{"timestamp":"2026-11-20T00:00:14Z","type":"event_msg","payload":{"type":"task_complete"}}"#
        try (lines.joined(separator: "\n") + "\n" + end + "\n").write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(CodexLogs.parse(url: file).activity?.phase, .idle)
    }
}
