import Foundation
import Testing

@testable import SwiftBar

struct LaunchAtLoginMigrationTests {
    struct TestError: Error {}

    @Test func migration_skipsWhenLegacyHelperIsNotEnabled() {
        var unregisterCalls = 0
        var registerCalls = 0

        ModernLaunchAtLogin.migrateLegacyLoginItem(
            isLegacyEnabled: false,
            unregisterLegacy: { unregisterCalls += 1 },
            registerMain: { registerCalls += 1 }
        )

        #expect(unregisterCalls == 0)
        #expect(registerCalls == 0)
    }

    @Test func migration_unregistersLegacyHelperThenRegistersMainApp() {
        var calls: [String] = []

        ModernLaunchAtLogin.migrateLegacyLoginItem(
            isLegacyEnabled: true,
            unregisterLegacy: { calls.append("unregisterLegacy") },
            registerMain: { calls.append("registerMain") }
        )

        #expect(calls == ["unregisterLegacy", "registerMain"])
    }

    @Test func migration_registersMainAppEvenIfUnregisteringLegacyHelperFails() {
        var registerCalls = 0

        ModernLaunchAtLogin.migrateLegacyLoginItem(
            isLegacyEnabled: true,
            unregisterLegacy: { throw TestError() },
            registerMain: { registerCalls += 1 }
        )

        #expect(registerCalls == 1)
    }

    @Test func migration_swallowsMainAppRegistrationFailure() {
        var unregisterCalls = 0

        ModernLaunchAtLogin.migrateLegacyLoginItem(
            isLegacyEnabled: true,
            unregisterLegacy: { unregisterCalls += 1 },
            registerMain: { throw TestError() }
        )

        #expect(unregisterCalls == 1)
    }

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
