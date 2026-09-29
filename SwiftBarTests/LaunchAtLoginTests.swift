import Foundation
import Testing

@testable import SwiftBar

struct LaunchAtLoginMigrationTests {
    struct TestError: Error {}

    @Test func migration_skipsWhenLegacyHelperIsNotEnabled() {
        var registerCalls = 0
        var unregisterCalls = 0

        let outcome = ModernLaunchAtLogin.migrateLegacyLoginItem(
            isLegacyEnabled: false,
            isMainAppEnabled: { false },
            registerMain: { registerCalls += 1 },
            unregisterLegacy: { unregisterCalls += 1 }
        )

        #expect(outcome == .notNeeded)
        #expect(registerCalls == 0)
        #expect(unregisterCalls == 0)
    }

    @Test func migration_registersMainAppBeforeUnregisteringLegacyHelper() {
        var calls: [String] = []
        var mainAppEnabled = false

        let outcome = ModernLaunchAtLogin.migrateLegacyLoginItem(
            isLegacyEnabled: true,
            isMainAppEnabled: { mainAppEnabled },
            registerMain: {
                calls.append("registerMain")
                mainAppEnabled = true
            },
            unregisterLegacy: { calls.append("unregisterLegacy") }
        )

        #expect(outcome == .migrated)
        #expect(calls == ["registerMain", "unregisterLegacy"])
    }

    @Test func migration_skipsRegistrationWhenMainAppIsAlreadyEnabled() {
        var registerCalls = 0
        var unregisterCalls = 0

        let outcome = ModernLaunchAtLogin.migrateLegacyLoginItem(
            isLegacyEnabled: true,
            isMainAppEnabled: { true },
            registerMain: { registerCalls += 1 },
            unregisterLegacy: { unregisterCalls += 1 }
        )

        #expect(outcome == .migrated)
        #expect(registerCalls == 0)
        #expect(unregisterCalls == 1)
    }

    /// A failed main app registration must leave the legacy helper in place:
    /// launch at login keeps working through it and the migration retries on
    /// the next launch because the helper still reports as enabled.
    @Test func migration_keepsLegacyHelperWhenMainAppRegistrationFails() {
        var unregisterCalls = 0

        let outcome = ModernLaunchAtLogin.migrateLegacyLoginItem(
            isLegacyEnabled: true,
            isMainAppEnabled: { false },
            registerMain: { throw TestError() },
            unregisterLegacy: { unregisterCalls += 1 }
        )

        #expect(outcome == .registrationFailed)
        #expect(unregisterCalls == 0)
    }

    /// `register()` returning without throwing does not guarantee an enabled
    /// registration — the main app can land in `.requiresApproval` for a user
    /// who once disabled SwiftBar in System Settings. The legacy helper must
    /// stay registered until the replacement actually takes effect.
    @Test func migration_keepsLegacyHelperWhileRegistrationIsPendingApproval() {
        var registerCalls = 0
        var unregisterCalls = 0

        let outcome = ModernLaunchAtLogin.migrateLegacyLoginItem(
            isLegacyEnabled: true,
            isMainAppEnabled: { false },
            registerMain: { registerCalls += 1 },
            unregisterLegacy: { unregisterCalls += 1 }
        )

        #expect(outcome == .pendingApproval)
        #expect(registerCalls == 1)
        #expect(unregisterCalls == 0)
    }

    @Test func migration_reportsFailedLegacyHelperUnregistration() {
        var registerCalls = 0
        var mainAppEnabled = false

        let outcome = ModernLaunchAtLogin.migrateLegacyLoginItem(
            isLegacyEnabled: true,
            isMainAppEnabled: { mainAppEnabled },
            registerMain: {
                registerCalls += 1
                mainAppEnabled = true
            },
            unregisterLegacy: { throw TestError() }
        )

        #expect(outcome == .unregistrationFailed)
        #expect(registerCalls == 1)
    }
}

struct LaunchAtLoginDisableTests {
    struct TestError: Error {}

    @Test func disable_skipsLegacyHelperWhenNotEnabled() {
        var unregisterCalls = 0

        let unregistered = ModernLaunchAtLogin.unregisterLegacyHelper(
            isLegacyEnabled: false,
            unregisterLegacy: { unregisterCalls += 1 }
        )

        #expect(!unregistered)
        #expect(unregisterCalls == 0)
    }

    @Test func disable_unregistersEnabledLegacyHelper() {
        var unregisterCalls = 0

        let unregistered = ModernLaunchAtLogin.unregisterLegacyHelper(
            isLegacyEnabled: true,
            unregisterLegacy: { unregisterCalls += 1 }
        )

        #expect(unregistered)
        #expect(unregisterCalls == 1)
    }

    @Test func disable_reportsFailedLegacyHelperUnregistration() {
        let unregistered = ModernLaunchAtLogin.unregisterLegacyHelper(
            isLegacyEnabled: true,
            unregisterLegacy: { throw TestError() }
        )

        #expect(!unregistered)
    }
}

struct LaunchAtLoginBundleTests {
    /// Requires the hosted test bundle: `Bundle.main` is the SwiftBar app, so
    /// the helper embedded by the "Launch At Login" build phase is present.
    ///
    /// The identifier must match the helper embedded in the app bundle,
    /// otherwise `SMAppService.loginItem(identifier:)` cannot resolve it and
    /// stale registrations from SwiftBar 2.0.x would survive unregistration.
    @Test func legacyHelperIdentifier_matchesEmbeddedHelperBundle() throws {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems/LaunchAtLoginHelper.app")
        let helperBundle = try #require(Bundle(url: helperURL))

        #expect(helperBundle.bundleIdentifier == ModernLaunchAtLogin.legacyHelperIdentifier)
    }
}
