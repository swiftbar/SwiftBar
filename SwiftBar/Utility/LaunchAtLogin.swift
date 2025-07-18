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
                do {
                    if newValue {
                        if SMAppService.mainApp.status == .enabled {
                            try? SMAppService.mainApp.unregister()
                        }

                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    logger.error("Failed to \(newValue ? "enable" : "disable") launch at login: \(error.localizedDescription)")
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