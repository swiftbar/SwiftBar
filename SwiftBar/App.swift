import Cocoa
import SwiftUI

class App: NSObject {
    public static func refreshPlugins() {
        PluginManager.shared.plugins.forEach{$0.refresh()}
    }

    public static func openPluginFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: "")
    }

    public static func changePluginFolder() {
        let dialog = NSOpenPanel();

        dialog.title                   = "Choose a plugin folder"
        dialog.showsResizeIndicator    = true
        dialog.showsHiddenFiles        = false
        dialog.canChooseDirectories    = true
        dialog.canCreateDirectories    = true
        dialog.allowsMultipleSelection = false

        guard dialog.runModal() == .OK,
              let path = dialog.url?.path
        else {return}

        Preferences.shared.pluginDirectoryPath = path
        refreshPlugins()
    }

    public static func getPlugins() {
        let url = URL(string: "https://github.com/orgs/swiftbar/")!
        NSWorkspace.shared.open(url)
    }

    public static func openPreferences() {
        let panel = NSPanel(contentViewController: NSHostingController(rootView: PreferencesView().environmentObject(Preferences.shared)))
        NSApp.runModal(for: panel)
    }
}
