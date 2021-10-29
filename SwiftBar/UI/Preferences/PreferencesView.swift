import Preferences
import SwiftUI

extension Preferences.PaneIdentifier {
    static let general = Self("general")
    static let plugins = Self("plugins")

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
                return NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)!
            } else {
                return NSImage(named: "AppIcon")!
            }
        default:
            return NSImage(named: "AppIcon")!
        }
    }
}

let preferencePanes: [PreferencePaneConvertible] = [
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
