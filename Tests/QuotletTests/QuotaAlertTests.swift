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
