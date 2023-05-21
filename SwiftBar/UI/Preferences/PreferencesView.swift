import Preferences
import SwiftUI

extension Preferences.PaneIdentifier {
    static let general = Self("general")
    static let plugins = Self("plugins")
    static let shortcutPlugins = Self("shortcutPlugins")
    static let advanced = Self("advanced")
    static let about = Self("about")

    var image: NSImage {
        switch self {
        case .general:
            if #available(OSX 11.0, *) {
                return NSImage(systemSymbolName: "gear", accessibilityDescription: nil)!
            } else {
                return NSImage(named: "AppIcon")!
            }
        case .plugins:
            if #available(OSX 11.0, *) {
                return NSImage(systemSymbolName: "curlybraces", accessibilityDescription: nil)!
            } else {
                return NSImage(named: "AppIcon")!
            }
        case .shortcutPlugins:
            if #available(OSX 11.0, *) {
                return NSImage(systemSymbolName: "flowchart", accessibilityDescription: nil)!
            } else {
                return NSImage(named: "AppIcon")!
            }
        case .advanced:
            if #available(OSX 11.0, *) {
                return NSImage(systemSymbolName: "gearshape.2", accessibilityDescription: nil)!
            } else {
                return NSImage(named: "AppIcon")!
            }
        case .about:
            if #available(OSX 11.0, *) {
                return NSImage(systemSymbolName: "info", accessibilityDescription: nil)!
            } else {
                return NSImage(named: "AppIcon")!
            }

        default:
            return NSImage(named: "AppIcon")!
        }
    }
}

var preferencePanes: [PreferencePaneConvertible] = {
    var panes: [PreferencePaneConvertible] = [
        Preferences.Pane(
            identifier: .general,
            title: Localizable.Preferences.General.localized,
            toolbarIcon: Preferences.PaneIdentifier.general.image
        ) { GeneralPreferencesView().environmentObject(PreferencesStore.shared) },
        Preferences.Pane(
            identifier: .plugins,
            title: Localizable.Preferences.Plugins.localized,
            toolbarIcon: Preferences.PaneIdentifier.plugins.image
        ) { PluginsPreferencesView(pluginManager: PluginManager.shared).environmentObject(PreferencesStore.shared) },
    ]

    if #available(macOS 12, *) {
        panes.append(
            Preferences.Pane(
                identifier: .shortcutPlugins,
                title: Localizable.Preferences.ShortcutPlugins.localized,
                toolbarIcon: Preferences.PaneIdentifier.shortcutPlugins.image
            ) { ShortcutPluginsPreferencesView(pluginManager: PluginManager.shared).environmentObject(PreferencesStore.shared) }
        )
    }

    panes.append(
        Preferences.Pane(
            identifier: .advanced,
            title: Localizable.Preferences.Advanced.localized,
            toolbarIcon: Preferences.PaneIdentifier.advanced.image
        ) { AdvancedPreferencesView().environmentObject(PreferencesStore.shared) }
    )

    panes.append(
        Preferences.Pane(
            identifier: .about,
            title: Localizable.Preferences.About.localized,
            toolbarIcon: Preferences.PaneIdentifier.about.image
        ) { AboutSettingsView() }
    )

    return panes
}()
