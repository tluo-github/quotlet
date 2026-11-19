import Foundation
import Security
import XCTest
@testable import Quotlet

final class PermissionDefaultsTests: XCTestCase {
    func testBackgroundKeychainAccessDisablesLegacyPromptsAndRestoresPreviousState() {
        var previous: DarwinBoolean = false
        XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&previous), errSecSuccess)
        var ran = false
        let result = KeychainAccess.perform(allowInteraction: false) {
            var allowed: DarwinBoolean = true
            XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&allowed), errSecSuccess)
            XCTAssertFalse(allowed.boolValue)
            ran = true
            return errSecInteractionNotAllowed
        }
        XCTAssertTrue(ran)
        XCTAssertEqual(result, errSecInteractionNotAllowed)
        var restored: DarwinBoolean = false
        XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&restored), errSecSuccess)
        XCTAssertEqual(restored.boolValue, previous.boolValue)
    }

    func testExplicitKeychainActionCanAllowInteraction() {
        let result = KeychainAccess.perform(allowInteraction: true) {
            var allowed: DarwinBoolean = false
            XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&allowed), errSecSuccess)
            XCTAssertTrue(allowed.boolValue)
            return errSecSuccess
        }
        XCTAssertEqual(result, errSecSuccess)
    }

    func testFreshInstallDefaultsToLocalStatsAndEnabledQuotaNotifications() {
        let suite = "QuotletTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        Notifier.registerDefaults(defaults)

        XCTAssertFalse(UsageAPI.isEnabled(defaults: defaults))
        XCTAssertTrue(defaults.bool(forKey: Notifier.Key.low))
        XCTAssertTrue(defaults.bool(forKey: Notifier.Key.full))
        XCTAssertTrue(defaults.bool(forKey: Notifier.Key.reset))
        XCTAssertEqual(defaults.integer(forKey: Notifier.Key.threshold), 90)
        defaults.set(true, forKey: UsageAPI.enabledKey)
        XCTAssertTrue(UsageAPI.isEnabled(defaults: defaults))
        defaults.set(false, forKey: UsageAPI.enabledKey)
        XCTAssertFalse(UsageAPI.isEnabled(defaults: defaults))
    }

    func testNotificationDefaultsPreserveAnExplicitPreference() {
        let suite = "QuotletTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: Notifier.Key.low)
        Notifier.registerDefaults(defaults)
        XCTAssertFalse(defaults.bool(forKey: Notifier.Key.low))
        XCTAssertTrue(defaults.bool(forKey: Notifier.Key.full))
    }

    func testDisabledAPINeverLoadsCredentialsOrFetchesEvenWhenInteractionIsRequested() async {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: UsageAPI.enabledKey)
        defaults.set(false, forKey: UsageAPI.enabledKey)
        defer {
            if let previous { defaults.set(previous, forKey: UsageAPI.enabledKey) }
            else { defaults.removeObject(forKey: UsageAPI.enabledKey) }
        }
        for interaction in [false, true] {
            XCTAssertThrowsError(try CredentialStore.load(allowInteraction: interaction)) { error in
                guard case UsageError.disabled = error else { return XCTFail("Unexpected error: \(error)") }
            }
            for fallback in [false, true] {
                do {
                    _ = try await UsageAPI.fetch(allowFallback: fallback, allowInteraction: interaction)
                    XCTFail("A disabled API must not fetch usage")
                } catch UsageError.disabled { }
                catch { XCTFail("Unexpected error: \(error)") }
            }
        }
    }
}
