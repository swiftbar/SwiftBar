import Cocoa
import os

class AppDelegate: NSObject, NSApplicationDelegate {
    var pluginManager: PluginManager!
    let prefs = Preferences.shared
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        //Check if plugin folder exists
        var isDir: ObjCBool = false
        if let pluginDirectoryPath = prefs.pluginDirectoryPath,
           (!FileManager.default.fileExists(atPath: pluginDirectoryPath, isDirectory: &isDir) || !isDir.boolValue) {
            prefs.pluginDirectoryPath = nil
        }
        
        //Instance of Plugin Manager must be created after app launch
        pluginManager = PluginManager.shared
        
        while Preferences.shared.pluginDirectoryPath == nil {
            let alert = NSAlert()
            alert.messageText = "Set SwiftBar Plugins Location"
            alert.informativeText = "Select a folder to store the SwiftBar plugins"
            alert.addButton(withTitle: "Ok")
            alert.addButton(withTitle: "Quit SwiftBar")
            let modalResult = alert.runModal()

            switch modalResult {
            case .alertFirstButtonReturn:
                App.changePluginFolder()
            default:
                NSApplication.shared.terminate(self)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch url.host?.lowercased() {
                case "refreshallplugins":
                    pluginManager.refreshAllPlugins()
                case "refreshplugin":
                    if let name = url.queryParameters?["name"] {
                        pluginManager.refreshPlugin(named: name)
                        return
                    }
                    if let indexStr = url.queryParameters?["index"], let index = Int(indexStr) {
                        pluginManager.refreshPlugin(with: index)
                        return
                    }
                case "addplugin":
                    if let src = url.queryParameters?["src"], let url = URL(string: src) {
                        pluginManager.importPlugin(from: url)
                    }
                default:
                    os_log("Unsupported URL scheme \n %{public}@", log: Log.plugin, type: .error, url.absoluteString)
                    break
            }
        }
    }
}
