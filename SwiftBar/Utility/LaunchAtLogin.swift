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

    /**
    Toggle "launch at login" for your app or check whether it's enabled.
    */
    public static var isEnabled: Bool {
        get { 
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
                // Fallback for older macOS versions
                return false
            }
        }
        set {
            observable.objectWillChange.send()

            if #available(macOS 13.0, *) {
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
                        try SMAppService.mainApp.unregister()
                    } catch {
                        logger.error("Failed to disable launch at login: \(error.localizedDescription)")
                    }

                    // Runs even when the main app call fails or the main app
                    // was never registered: for users upgraded from SwiftBar
                    // 2.0.x the launch-at-login state may live only in the
                    // legacy helper registration (#571).
                    unregisterLegacyHelperIfEnabled()
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

        let legacyHelper = SMAppService.loginItem(identifier: legacyHelperIdentifier)
        let outcome = migrateLegacyLoginItem(
            isLegacyEnabled: legacyHelper.status == .enabled,
            isMainAppEnabled: { SMAppService.mainApp.status == .enabled },
            registerMain: SMAppService.mainApp.register,
            unregisterLegacy: legacyHelper.unregister
        )

        if outcome == .migrated {
            // Refresh an already-open Preferences toggle, which reads
            // SMAppService.mainApp.status through `observable`.
            DispatchQueue.main.async {
                observable.objectWillChange.send()
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

    /// Migration logic separated from the `SMAppService` calls so it can be unit tested.
    @discardableResult
    static func migrateLegacyLoginItem(
        isLegacyEnabled: Bool,
        isMainAppEnabled: () -> Bool,
        registerMain: () throws -> Void,
        unregisterLegacy: () throws -> Void
    ) -> LegacyMigrationOutcome {
        guard isLegacyEnabled else { return .notNeeded }

        // Register the replacement before dropping the legacy registration so
        // a failure can never silently lose launch at login: on error the
        // legacy helper stays registered (still enabled, still launching the
        // app) and the migration retries on the next launch.
        if !isMainAppEnabled() {
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
            guard isMainAppEnabled() else {
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