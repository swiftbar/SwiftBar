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
            mainAppRegistration: { .notRegistered },
            registerMain: { registerCalls += 1 },
            unregisterLegacy: { unregisterCalls += 1 }
        )

        #expect(outcome == .notNeeded)
        #expect(registerCalls == 0)
        #expect(unregisterCalls == 0)
    }

    @Test func migration_registersMainAppBeforeUnregisteringLegacyHelper() {
        var calls: [String] = []
        var mainApp = ModernLaunchAtLogin.MainAppRegistration.notRegistered

        let outcome = ModernLaunchAtLogin.migrateLegacyLoginItem(
            isLegacyEnabled: true,
            mainAppRegistration: { mainApp },
            registerMain: {
                calls.append("registerMain")
                mainApp = .enabled
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
            mainAppRegistration: { .enabled },
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
            mainAppRegistration: { .notRegistered },
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
        var mainApp = ModernLaunchAtLogin.MainAppRegistration.notRegistered

        let outcome = ModernLaunchAtLogin.migrateLegacyLoginItem(
            isLegacyEnabled: true,
            mainAppRegistration: { mainApp },
            registerMain: {
                registerCalls += 1
                mainApp = .requiresApproval
            },
            unregisterLegacy: { unregisterCalls += 1 }
        )

        #expect(outcome == .pendingApproval)
        #expect(registerCalls == 1)
        #expect(unregisterCalls == 0)
    }

    /// Once the main app already sits in `.requiresApproval`, registering
    /// again cannot help and would repost the "Background Items Added"
    /// notification on every launch.
    @Test func migration_doesNotReregisterWhileApprovalIsPending() {
        var registerCalls = 0
        var unregisterCalls = 0

        let outcome = ModernLaunchAtLogin.migrateLegacyLoginItem(
            isLegacyEnabled: true,
            mainAppRegistration: { .requiresApproval },
            registerMain: { registerCalls += 1 },
            unregisterLegacy: { unregisterCalls += 1 }
        )

        #expect(outcome == .pendingApproval)
        #expect(registerCalls == 0)
        #expect(unregisterCalls == 0)
    }

    @Test func migration_reportsFailedLegacyHelperUnregistration() {
        var registerCalls = 0
        var mainApp = ModernLaunchAtLogin.MainAppRegistration.notRegistered

        let outcome = ModernLaunchAtLogin.migrateLegacyLoginItem(
            isLegacyEnabled: true,
            mainAppRegistration: { mainApp },
            registerMain: {
                registerCalls += 1
                mainApp = .enabled
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

struct LaunchAtLoginStateTests {
    /// The toggle must report launch at login as ON while only the legacy
    /// helper registration is enabled — e.g. when the startup migration
    /// failed or is pending approval — otherwise Preferences shows OFF while
    /// the helper still launches SwiftBar at login (#571).
    @Test func state_reportsEnabledWhenOnlyLegacyHelperIsEnabled() {
        #expect(ModernLaunchAtLogin.launchAtLoginState(isMainAppEnabled: false, isLegacyEnabled: true))
    }

    @Test func state_reportsEnabledWhenMainAppIsEnabled() {
        #expect(ModernLaunchAtLogin.launchAtLoginState(isMainAppEnabled: true, isLegacyEnabled: false))
    }

    @Test func state_reportsDisabledWhenNeitherRegistrationIsEnabled() {
        #expect(!ModernLaunchAtLogin.launchAtLoginState(isMainAppEnabled: false, isLegacyEnabled: false))
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
