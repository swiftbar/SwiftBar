//
//  LaunchAtLogin.swift
//  SwiftBar
//
//  Modern implementation of LaunchAtLogin using ServiceManagement API
//  Compatible with macOS 13.0+ including macOS Sequoia
//
//  Based on https://github.com/sindresorhus/LaunchAtLogin-Modern
//

import SwiftUI
import ServiceManagement
import os.log

public enum ModernLaunchAtLogin {
    private static let logger = Logger(subsystem: "com.ameba.SwiftBar", category: "LaunchAtLogin")
    public static let observable = Observable()

    /**
    Bundle identifier of the login item helper that SwiftBar 2.0.x and earlier
    registered through `SMLoginItemSetEnabled` (via the LaunchAtLogin package).
    The helper is still embedded at `Contents/Library/LoginItems` so this
    identifier keeps resolving for status checks and unregistration.
    */
    static let legacyHelperIdentifier = "com.ameba.SwiftBar-LaunchAtLoginHelper"

    /// Serializes the `SMAppService` mutations made by the launch-time
    /// migration and the Preferences toggle, so a toggle flipped while the
    /// migration is in flight cannot be overwritten by a stale registration.
    private static let serviceQueue = DispatchQueue(label: "com.ameba.SwiftBar.LaunchAtLogin")

    /// Getter logic separated from the `SMAppService` calls so it can be unit
    /// tested: launch at login is on while either registration is enabled.
    static func launchAtLoginState(isMainAppEnabled: Bool, isLegacyEnabled: Bool) -> Bool {
        isMainAppEnabled || isLegacyEnabled
    }

    /**
    Toggle "launch at login" for your app or check whether it's enabled.
    */
    public static var isEnabled: Bool {
        get { 
            if #available(macOS 13.0, *) {
                // The legacy helper also launches SwiftBar at login, so the
                // toggle must report it while a failed or pending migration
                // leaves it registered (#571).
                return launchAtLoginState(
                    isMainAppEnabled: SMAppService.mainApp.status == .enabled,
                    isLegacyEnabled: SMAppService.loginItem(identifier: legacyHelperIdentifier).status == .enabled
                )
            } else {
                // Fallback for older macOS versions
                return false
            }
        }
        set {
            observable.objectWillChange.send()

            if #available(macOS 13.0, *) {
                serviceQueue.sync {
                    if newValue {
                        do {
                            if SMAppService.mainApp.status == .enabled {
                                try? SMAppService.mainApp.unregister()
                            }

                            try SMAppService.mainApp.register()
                        } catch {
                            logger.error("Failed to enable launch at login: \(error.localizedDescription)")
                        }
                    } else {
                        do {
                            // unregister() throws when the main app was never
                            // registered — the normal state for a legacy-only
                            // 2.0.x upgrade — so skip it rather than log a
                            // false failure.
                            if SMAppService.mainApp.status != .notRegistered {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            logger.error("Failed to disable launch at login: \(error.localizedDescription)")
                        }

                        // Runs even when the main app call fails or the main
                        // app was never registered: for users upgraded from
                        // SwiftBar 2.0.x the launch-at-login state may live
                        // only in the legacy helper registration (#571).
                        unregisterLegacyHelperIfEnabled()
                    }
                }
            } else {
                logger.warning("Launch at login requires macOS 13.0 or later")
            }
        }
    }

    /**
    Whether the app was launched at login.

    - Important: This property must only be checked in `NSApplicationDelegate#applicationDidFinishLaunching`.
    */
    public static var wasLaunchedAtLogin: Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        return event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}

private protocol LegacyLoginItemDisabling {
    static func disable(_ identifier: CFString)
}

/// `SMLoginItemSetEnabled` is deprecated since macOS 13, but it is the API
/// that created pre-2.1.0 registrations and the reliable way to clear them on
/// systems where `SMAppService` does not bridge to them. The deprecated call
/// lives in a deprecated witness and is reached through the protocol, which
/// contains the deprecation warning to this shim.
private enum LegacyLoginItemShim: LegacyLoginItemDisabling {
    @available(macOS, deprecated: 13.0)
    static func disable(_ identifier: CFString) {
        _ = SMLoginItemSetEnabled(identifier, false)
    }
}

extension ModernLaunchAtLogin {
    /**
    Migrates a launch-at-login registration made by SwiftBar 2.0.x and earlier.

    Old versions enabled launch at login by registering the embedded
    `LaunchAtLoginHelper.app` through `SMLoginItemSetEnabled`. That registration
    lives in the background task management database independently of
    `SMAppService.mainApp`: it keeps launching SwiftBar at login even after the
    toggle (which only manages the main app registration) is turned off, and it
    appears in System Settings under "Allow in the Background" as
    "Ameba Labs, LLC" instead of "SwiftBar". Replacing it with a main app
    registration preserves the user's intent, makes the toggle authoritative,
    and lists the item as "SwiftBar" in "Open at Login".
    */
    public static func migrateLegacyLoginItem() {
        guard #available(macOS 13.0, *) else { return }

        // On the serial queue: keeps the XPC calls off the calling thread and
        // serializes the migration with the Preferences toggle, so a toggle
        // flipped while the migration is in flight cannot be overwritten.
        serviceQueue.async {
            let legacyHelper = SMAppService.loginItem(identifier: legacyHelperIdentifier)
            let outcome = migrateLegacyLoginItem(
                isLegacyEnabled: legacyHelper.status == .enabled,
                mainAppRegistration: {
                    switch SMAppService.mainApp.status {
                    case .enabled: .enabled
                    case .requiresApproval: .requiresApproval
                    default: .notRegistered
                    }
                },
                registerMain: SMAppService.mainApp.register,
                unregisterLegacy: {
                    // Defense in depth: also clear the legacy registration
                    // through the API that created it, even when the
                    // SMAppService unregistration throws (see
                    // disableLegacyLoginItem()).
                    defer { disableLegacyLoginItem() }
                    try legacyHelper.unregister()
                }
            )

            if outcome == .migrated {
                // The displayed state does not change (the getter already
                // counted the legacy helper), but nudge an open Preferences
                // toggle to re-read it now that the backing registration is
                // the main app.
                DispatchQueue.main.async {
                    observable.objectWillChange.send()
                }
            }
        }
    }

    /// What `migrateLegacyLoginItem` did, so tests can assert the failure paths.
    enum LegacyMigrationOutcome: Equatable {
        case notNeeded
        case migrated
        case registrationFailed
        case pendingApproval
        case unregistrationFailed
    }

    /// `SMAppService.Status` reduced to the cases the migration distinguishes,
    /// keeping the logic testable without ServiceManagement types.
    enum MainAppRegistration: Equatable {
        case enabled
        case requiresApproval
        case notRegistered
    }

    /// Migration logic separated from the `SMAppService` calls so it can be unit tested.
    @discardableResult
    static func migrateLegacyLoginItem(
        isLegacyEnabled: Bool,
        mainAppRegistration: () -> MainAppRegistration,
        registerMain: () throws -> Void,
        unregisterLegacy: () throws -> Void
    ) -> LegacyMigrationOutcome {
        guard isLegacyEnabled else { return .notNeeded }

        // Register the replacement before dropping the legacy registration so
        // a failure can never silently lose launch at login: on error the
        // legacy helper stays registered (still enabled, still launching the
        // app) and the migration retries on the next launch.
        switch mainAppRegistration() {
        case .enabled:
            break
        case .requiresApproval:
            // Registering again would repost the "Background Items Added"
            // notification on every launch without changing anything; the
            // user has to approve SwiftBar in System Settings first.
            logger.notice("Launch at login migration pending: main app registration requires approval in System Settings")
            return .pendingApproval
        case .notRegistered:
            do {
                try registerMain()
            } catch {
                logger.error("Failed to register main app while migrating legacy login item: \(error.localizedDescription)")
                return .registrationFailed
            }

            // register() returning is not proof of an enabled registration:
            // for a user who once disabled SwiftBar in System Settings the
            // main app lands in .requiresApproval. Keep the legacy helper
            // until the replacement is actually enabled; the migration
            // retries on the next launch.
            guard mainAppRegistration() == .enabled else {
                logger.notice("Launch at login migration pending: main app registration requires approval in System Settings")
                return .pendingApproval
            }
        }

        do {
            try unregisterLegacy()
        } catch {
            logger.error("Failed to unregister legacy login item helper: \(error.localizedDescription)")
            return .unregistrationFailed
        }

        return .migrated
    }

    /// Drops the launch-at-login registration made by SwiftBar 2.0.x and
    /// earlier, if one is still active. See `migrateLegacyLoginItem()`.
    @available(macOS 13.0, *)
    private static func unregisterLegacyHelperIfEnabled() {
        let legacyHelper = SMAppService.loginItem(identifier: legacyHelperIdentifier)
        unregisterLegacyHelper(
            isLegacyEnabled: legacyHelper.status == .enabled,
            unregisterLegacy: legacyHelper.unregister
        )

        // Defense in depth, unconditionally: also clear the registration
        // through the API that created it. SMAppService reads and removes
        // SMLoginItemSetEnabled registrations on current systems (verified
        // live against the BTM database), but this keeps the removal robust
        // on systems where that bridge may not hold.
        disableLegacyLoginItem()
    }

    /// Clears the pre-2.1.0 registration through `SMLoginItemSetEnabled`,
    /// the API that created it. The result is intentionally ignored: this
    /// backs up the `SMAppService` unregistration, it does not replace it.
    static func disableLegacyLoginItem() {
        (LegacyLoginItemShim.self as LegacyLoginItemDisabling.Type)
            .disable(legacyHelperIdentifier as CFString)
    }

    /// Disable-path logic separated from the `SMAppService` calls so it can be
    /// unit tested. Returns whether the legacy helper was unregistered.
    @discardableResult
    static func unregisterLegacyHelper(
        isLegacyEnabled: Bool,
        unregisterLegacy: () throws -> Void
    ) -> Bool {
        guard isLegacyEnabled else { return false }

        do {
            try unregisterLegacy()
            return true
        } catch {
            logger.error("Failed to unregister legacy login item helper: \(error.localizedDescription)")
            return false
        }
    }
}

extension ModernLaunchAtLogin {
    public final class Observable: ObservableObject {
        public var isEnabled: Bool {
            get { ModernLaunchAtLogin.isEnabled }
            set {
                ModernLaunchAtLogin.isEnabled = newValue
            }
        }
    }
}

extension ModernLaunchAtLogin {
    /**
    This package comes with a `ModernLaunchAtLogin.Toggle` view which is like the built-in `Toggle` but with a predefined binding and label. Clicking the view toggles "launch at login" for your app.

    ```
    struct ContentView: View {
        var body: some View {
            ModernLaunchAtLogin.Toggle()
        }
    }
    ```

    The default label is `"Launch at login"`, but it can be overridden for localization and other needs:

    ```
    struct ContentView: View {
        var body: some View {
            ModernLaunchAtLogin.Toggle {
                Text("Launch at login")
            }
        }
    }
    ```
    */
    public struct Toggle<Label: View>: View {
        @ObservedObject private var launchAtLogin = ModernLaunchAtLogin.observable
        private let label: Label

        /**
        Creates a toggle that displays a custom label.

        - Parameters:
            - label: A view that describes the purpose of the toggle.
        */
        public init(@ViewBuilder label: () -> Label) {
            self.label = label()
        }

        public var body: some View {
            if #available(macOS 13.0, *) {
                SwiftUI.Toggle(isOn: $launchAtLogin.isEnabled) { label }
            } else {
                SwiftUI.Toggle(isOn: .constant(false)) { label }
                    .disabled(true)
                    .help("Launch at login requires macOS 13.0 or later")
            }
        }
    }
}

extension ModernLaunchAtLogin.Toggle<Text> {
    /**
    Creates a toggle that generates its label from a localized string key.

    This initializer creates a ``Text`` view on your behalf with the provided `titleKey`.

    - Parameters:
        - titleKey: The key for the toggle's localized title, that describes the purpose of the toggle.
    */
    public init(_ titleKey: LocalizedStringKey) {
        label = Text(titleKey)
    }

    /**
    Creates a toggle that generates its label from a string.

    This initializer creates a `Text` view on your behalf with the provided `title`.

    - Parameters:
        - title: A string that describes the purpose of the toggle.
    */
    public init(_ title: some StringProtocol) {
        label = Text(title)
    }

    /**
    Creates a toggle with the default title of `Launch at login`.
    */
    public init() {
        self.init("Launch at login")
    }
}