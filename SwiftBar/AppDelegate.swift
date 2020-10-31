import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    let pluginManager = PluginManager.shared

    func applicationDidFinishLaunching(_ aNotification: Notification) {

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
                    break
            }
        }
    }
}
