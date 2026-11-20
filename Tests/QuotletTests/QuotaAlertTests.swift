import Foundation
import XCTest
@testable import Quotlet

final class QuotaAlertTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func limits(_ percent: Double, estimated: Bool = false) -> [LimitItem] {
        ["session", "weekly_all"].map {
            LimitItem(id: $0, kind: $0, title: $0, percent: percent, severity: nil,
                      resetsAt: now.addingTimeInterval(1000), isEstimated: estimated)
        }
    }

    func testBothWindowsWarnFromEstimatedAndConfirmedUsage() {
        for estimated in [false, true] {
            for item in limits(90, estimated: estimated) {
                XCTAssertTrue(Notifier.shouldWarn(item: item, threshold: 90, lowEnabled: true, fullEnabled: true, now: now))
                XCTAssertFalse(Notifier.shouldWarn(item: item, threshold: 95, lowEnabled: true, fullEnabled: true, now: now))
                XCTAssertFalse(Notifier.shouldWarn(item: item, threshold: 90, lowEnabled: true, fullEnabled: true,
                                                  now: now.addingTimeInterval(2000)))
            }
        }
    }

    func testNotificationIdentityDeduplicatesEstimatesAndSeparatesProvidersAndWindows() {
        let actual = limits(90)
        let estimated = limits(91, estimated: true)
        XCTAssertEqual(Notifier.windowKey(provider: "Claude", item: actual[0]),
                       Notifier.windowKey(provider: "Claude", item: estimated[0]))
        XCTAssertNotEqual(Notifier.windowKey(provider: "Claude", item: actual[0]),
                          Notifier.windowKey(provider: "Codex", item: actual[0]))
        XCTAssertNotEqual(Notifier.windowKey(provider: "Claude", item: actual[0]),
                          Notifier.windowKey(provider: "Claude", item: actual[1]))
    }

    func testLowAlertStillWorksAtFullWhenFullAlertsAreDisabled() {
        let item = limits(100, estimated: true)[0]
        XCTAssertTrue(Notifier.shouldWarn(item: item, threshold: 90, lowEnabled: true, fullEnabled: false, now: now))
        XCTAssertFalse(Notifier.shouldWarn(item: item, threshold: 90, lowEnabled: true, fullEnabled: true, now: now))
    }

    func testRepeatedRefreshesWithDriftingResetOnlyAlertOnce() {
        var sent: [String] = []
        // 本机日志中同一个 Codex 周期实际出现的重置时间偏移。
        let offsets: [TimeInterval] = [0, 49, 98, 87, 139, 44, 197, 46, 6, 0]
        for (index, offset) in offsets.enumerated() {
            var item = limits(Double(90 + index), estimated: index.isMultiple(of: 2))[0]
            item = LimitItem(id: item.id, kind: item.kind, title: item.title, percent: item.percent,
                             severity: nil, resetsAt: now.addingTimeInterval(18_000 + offset), isEstimated: item.isEstimated)
            let key = Notifier.recordAlert(provider: "Codex", item: item, event: .low, sent: &sent,
                                           now: now.addingTimeInterval(Double(index) * 300))
            XCTAssertEqual(key != nil, index == 0)
        }
        XCTAssertEqual(sent.count, 1)
    }

    func testSavedAlertsDeduplicateAfterRestartAndAllowFullAlert() {
        let item = limits(90)[0]
        // 沿用旧版本已保存的 key，升级和重启后也不重复提醒。
        var sent = [Notifier.windowKey(provider: "Codex", item: item) + "|low"]
        let corrected = LimitItem(id: item.id, kind: item.kind, title: item.title, percent: 100,
                                  severity: nil, resetsAt: item.resetsAt!.addingTimeInterval(-197))
        XCTAssertNil(Notifier.recordAlert(provider: "Codex", item: corrected, event: .low, sent: &sent, now: now))
        XCTAssertNotNil(Notifier.recordAlert(provider: "Codex", item: corrected, event: .full, sent: &sent, now: now))
        XCTAssertNil(Notifier.recordAlert(provider: "Codex", item: item, event: .full, sent: &sent, now: now))
        XCTAssertEqual(sent.count, 2)
    }

    func testAlertDeduplicationKeepsProvidersWindowsAndScopesSeparate() {
        let item = limits(90)[0]
        var sent: [String] = []
        XCTAssertNotNil(Notifier.recordAlert(provider: "Codex", item: item, event: .low, sent: &sent, now: now))
        XCTAssertNotNil(Notifier.recordAlert(provider: "Claude", item: item, event: .low, sent: &sent, now: now))
        XCTAssertNotNil(Notifier.recordAlert(provider: "Codex", item: limits(90)[1], event: .low, sent: &sent, now: now))
        let scoped = LimitItem(id: "scoped", kind: item.kind, title: item.title, percent: 90,
                               severity: nil, resetsAt: item.resetsAt, scope: "Opus")
        XCTAssertNotNil(Notifier.recordAlert(provider: "Codex", item: scoped, event: .low, sent: &sent, now: now))
    }

    func testNewCycleCanAlertAfterPreviousReset() {
        let item = limits(90)[0]
        var sent: [String] = []
        XCTAssertNotNil(Notifier.recordAlert(provider: "Codex", item: item, event: .low, sent: &sent, now: now))
        let next = LimitItem(id: item.id, kind: item.kind, title: item.title, percent: 90,
                             severity: nil, resetsAt: item.resetsAt!.addingTimeInterval(18_000))
        XCTAssertNotNil(Notifier.recordAlert(provider: "Codex", item: next, event: .low, sent: &sent,
                                             now: now.addingTimeInterval(1100)))
        // 即使新旧重置时间接近，旧周期过期后也不能吞掉新周期的提醒。
        var shortCycleSent = [Notifier.windowKey(provider: "Codex", item: item) + "|low"]
        let shortNext = LimitItem(id: item.id, kind: item.kind, title: item.title, percent: 90,
                                  severity: nil, resetsAt: item.resetsAt!.addingTimeInterval(120))
        XCTAssertNotNil(Notifier.recordAlert(provider: "Codex", item: shortNext, event: .low, sent: &shortCycleSent,
                                             now: now.addingTimeInterval(1100)))
    }

    func testLargeResetCorrectionsDoNotRepeatAndStillAllowNextCycle() {
        for event in [Notifier.AlertEvent.low, .full] {
            var sent: [String] = []
            let offsets: [TimeInterval] = [0, 900, -1200, 1800, 3600]
            for (index, offset) in offsets.enumerated() {
                let item = LimitItem(id: "session", kind: "session", title: "5h", percent: 100,
                                     severity: nil, resetsAt: now.addingTimeInterval(18_000 + offset))
                XCTAssertEqual(Notifier.recordAlert(provider: "Codex", item: item, event: event, sent: &sent,
                                                    now: now.addingTimeInterval(Double(index) * 300)) != nil,
                               index == 0)
            }
            // 保存后的记录用于重启；在最初的重置时刻之后、修正后的时刻之前也不重复。
            var restored = sent
            let current = LimitItem(id: "session", kind: "session", title: "5h", percent: 100,
                                    severity: nil, resetsAt: now.addingTimeInterval(21_600))
            XCTAssertNil(Notifier.recordAlert(provider: "Codex", item: current, event: event, sent: &restored,
                                              now: now.addingTimeInterval(18_100)))
            let next = LimitItem(id: "session", kind: "session", title: "5h", percent: 100,
                                 severity: nil, resetsAt: now.addingTimeInterval(39_600))
            XCTAssertNotNil(Notifier.recordAlert(provider: "Codex", item: next, event: event, sent: &restored,
                                                 now: now.addingTimeInterval(21_700)))
        }
    }

    func testMissingAndKnownResetTimesStayInSameCycle() {
        let unknown = LimitItem(id: "session", kind: "session", title: "5h", percent: 95,
                                severity: nil, resetsAt: nil)
        let known = LimitItem(id: "session", kind: "session", title: "5h", percent: 95,
                              severity: nil, resetsAt: now.addingTimeInterval(18_000))
        for firstUnknown in [true, false] {
            var sent: [String] = []
            XCTAssertNotNil(Notifier.recordAlert(provider: "Codex", item: firstUnknown ? unknown : known,
                                                 event: .low, sent: &sent, now: now))
            for item in [known, unknown, known] {
                XCTAssertNil(Notifier.recordAlert(provider: "Codex", item: item, event: .low, sent: &sent, now: now))
            }
            XCTAssertEqual(sent, [Notifier.windowKey(provider: "Codex", item: known) + "|low"])
            let next = LimitItem(id: "session", kind: "session", title: "5h", percent: 95,
                                 severity: nil, resetsAt: now.addingTimeInterval(36_000))
            XCTAssertNotNil(Notifier.recordAlert(provider: "Codex", item: next, event: .low, sent: &sent,
                                                 now: now.addingTimeInterval(18_100)))
        }
    }

    func testCorrectionBelowThresholdPreservesBothAlertsAndMigratesOldKeys() {
        let first = limits(100)[0]
        var sent = [Notifier.windowKey(provider: "Codex", item: first) + "|low",
                    Notifier.windowKey(provider: "Codex", item: first) + "|full",
                    "Codex|session||0|low"]
        let corrected = LimitItem(id: first.id, kind: first.kind, title: first.title, percent: 20,
                                  severity: nil, resetsAt: now.addingTimeInterval(2000))
        Notifier.updateAlertWindow(provider: "Codex", item: corrected, sent: &sent, now: now)
        XCTAssertEqual(sent.count, 2)
        XCTAssertNil(Notifier.recordAlert(provider: "Codex", item: corrected, event: .low, sent: &sent,
                                          now: now.addingTimeInterval(1100)))
        XCTAssertNil(Notifier.recordAlert(provider: "Codex", item: corrected, event: .full, sent: &sent,
                                          now: now.addingTimeInterval(1100)))
    }

    func testMissingResetTimeStillDeduplicates() {
        let item = LimitItem(id: "no-reset", kind: "session", title: "5h", percent: 90,
                             severity: nil, resetsAt: nil)
        var sent: [String] = []
        XCTAssertNotNil(Notifier.recordAlert(provider: "Codex", item: item, event: .low, sent: &sent, now: now))
        XCTAssertNil(Notifier.recordAlert(provider: "Codex", item: item, event: .low, sent: &sent, now: now))
    }

    func testRecommendationWorksInBothDirectionsIncludingEstimates() {
        let codex = Advice.make(claude: limits(92, estimated: true), codex: limits(12), now: now, threshold: 90)
        XCTAssertTrue(codex!.title.contains("Codex"))
        XCTAssertTrue(codex!.badge.contains("88%"))
        let claude = Advice.make(claude: limits(12), codex: limits(92), now: now, threshold: 90)
        XCTAssertTrue(claude!.title.contains("Claude"))
        XCTAssertNil(Advice.make(claude: limits(92), codex: limits(75), now: now, threshold: 90))
        XCTAssertNil(Advice.make(claude: limits(92), codex: limits(12),
                                now: now.addingTimeInterval(2000), threshold: 90))
    }
}
