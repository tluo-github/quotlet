import Foundation
import XCTest
@testable import Quotlet

final class ClaudeQuotaEstimatorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(session: Double, weekly: Double, resetOffset: TimeInterval = 0,
                          plan: String = "pro") -> UsageSnapshot {
        UsageSnapshot(limits: [
            LimitItem(id: "session", kind: "session", title: "5h", percent: session, severity: nil,
                      resetsAt: start.addingTimeInterval(18_000 + resetOffset)),
            LimitItem(id: "weekly", kind: "weekly_all", title: "Week", percent: weekly, severity: nil,
                      resetsAt: start.addingTimeInterval(604_800 + resetOffset)),
        ], breakdown: [], breakdownStart: nil, extra: nil, plan: plan)
    }

    private func message(_ seconds: TimeInterval, tokens: Int, source: Source = .claude) -> MessageUsage {
        MessageUsage(ts: start.addingTimeInterval(seconds), model: "test",
                     tokens: TokenCount(output: tokens), source: source)
    }

    func testCalibratesEachWindowAndCountsOnlyNewClaudeTokens() {
        var estimator = ClaudeQuotaEstimator()
        estimator.observe(snapshot(session: 20, weekly: 40), at: start, messages: [])
        let messages = [message(100, tokens: 1000), message(400, tokens: 500),
                        message(400, tokens: 50_000, source: .codex)]
        let actual = snapshot(session: 22, weekly: 40.5)
        estimator.observe(actual, at: start.addingTimeInterval(300), messages: messages)
        let result = estimator.display(actual, messages: messages, now: start.addingTimeInterval(500))
        XCTAssertEqual(result.session!.percent, 23, accuracy: 0.001)
        XCTAssertEqual(result.weekly!.percent, 40.75, accuracy: 0.001)
        XCTAssertTrue(result.session!.isEstimated)
        XCTAssertEqual(result.session?.percentText, "23.0%")
        XCTAssertEqual(result.weekly?.percentText, "40.8%")
        XCTAssertEqual(actual.session!.percent, 22)
        XCTAssertFalse(actual.session!.isEstimated)
    }

    func testWaitsForCalibrationAndForNewTokens() {
        var estimator = ClaudeQuotaEstimator()
        let first = snapshot(session: 20, weekly: 40)
        estimator.observe(first, at: start, messages: [])
        let messages = [message(100, tokens: 1000)]
        XCTAssertFalse(estimator.display(first, messages: messages, now: start.addingTimeInterval(200)).session!.isEstimated)
        let next = snapshot(session: 22, weekly: 41)
        estimator.observe(next, at: start.addingTimeInterval(300), messages: messages)
        XCTAssertFalse(estimator.display(next, messages: messages, now: start.addingTimeInterval(400)).session!.isEstimated)
    }

    func testAccumulatesTokensAcrossRoundedUnchangedReadings() {
        var estimator = ClaudeQuotaEstimator()
        let first = snapshot(session: 20, weekly: 40)
        estimator.observe(first, at: start, messages: [])
        let messages = [message(100, tokens: 500), message(400, tokens: 500), message(700, tokens: 1000)]
        estimator.observe(first, at: start.addingTimeInterval(300), messages: messages)
        let next = snapshot(session: 21, weekly: 41)
        estimator.observe(next, at: start.addingTimeInterval(600), messages: messages)
        let result = estimator.display(next, messages: messages, now: start.addingTimeInterval(800))
        XCTAssertEqual(result.session!.percent, 22, accuracy: 0.001)
    }

    func testServerCorrectsEstimateAndExcludesLateHistoricalRecords() {
        var estimator = ClaudeQuotaEstimator()
        estimator.observe(snapshot(session: 20, weekly: 40), at: start, messages: [])
        let second = snapshot(session: 22, weekly: 41)
        estimator.observe(second, at: start.addingTimeInterval(300), messages: [message(100, tokens: 1000)])
        let messages = [message(100, tokens: 1000), message(200, tokens: 10_000), message(400, tokens: 500)]
        let result = estimator.display(second, messages: messages, now: start.addingTimeInterval(500))
        XCTAssertEqual(result.session!.percent, 23, accuracy: 0.001)
        let corrected = snapshot(session: 22.5, weekly: 41.1)
        estimator.observe(corrected, at: start.addingTimeInterval(600), messages: messages)
        let after = estimator.display(corrected, messages: messages, now: start.addingTimeInterval(600))
        XCTAssertEqual(after.session!.percent, 22.5)
        XCTAssertFalse(after.session!.isEstimated)
    }

    func testClearsCalibrationOnResetPlanChangeAndServerDecrease() {
        for next in [snapshot(session: 1, weekly: 1, resetOffset: 18_000),
                     snapshot(session: 22, weekly: 41, plan: "max"),
                     snapshot(session: 19, weekly: 39)] {
            var estimator = ClaudeQuotaEstimator()
            estimator.observe(snapshot(session: 20, weekly: 40), at: start, messages: [])
            estimator.observe(snapshot(session: 22, weekly: 41), at: start.addingTimeInterval(300),
                              messages: [message(100, tokens: 1000)])
            estimator.observe(next, at: start.addingTimeInterval(600), messages: [message(100, tokens: 1000)])
            let result = estimator.display(next, messages: [message(700, tokens: 500)], now: start.addingTimeInterval(800))
            XCTAssertEqual(result.session!.percent, next.session!.percent)
            XCTAssertFalse(result.session!.isEstimated)
        }
    }

    func testDoesNotLearnFromRemoteOnlyUsageOrExtrapolatePastReset() {
        var estimator = ClaudeQuotaEstimator()
        estimator.observe(snapshot(session: 20, weekly: 40), at: start, messages: [])
        let remote = snapshot(session: 22, weekly: 41)
        estimator.observe(remote, at: start.addingTimeInterval(300), messages: [])
        let messages = [message(400, tokens: 1000)]
        XCTAssertFalse(estimator.display(remote, messages: messages, now: start.addingTimeInterval(500)).session!.isEstimated)
        let next = snapshot(session: 24, weekly: 42)
        estimator.observe(next, at: start.addingTimeInterval(600), messages: messages)
        let afterReset = estimator.display(next, messages: messages + [message(19_000, tokens: 1000)],
                                          now: start.addingTimeInterval(20_000))
        XCTAssertFalse(afterReset.session!.isEstimated)
        XCTAssertEqual(afterReset.session!.percent, 24)
    }

    func testCapsEstimateAtOneHundredPercent() {
        var estimator = ClaudeQuotaEstimator()
        estimator.observe(snapshot(session: 90, weekly: 90), at: start, messages: [])
        let next = snapshot(session: 95, weekly: 95)
        estimator.observe(next, at: start.addingTimeInterval(300), messages: [message(100, tokens: 1000)])
        let result = estimator.display(next, messages: [message(400, tokens: 100_000)], now: start.addingTimeInterval(500))
        XCTAssertEqual(result.session!.percent, 100)
        XCTAssertEqual(result.weekly!.percent, 100)
    }
}
