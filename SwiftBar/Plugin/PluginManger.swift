import Foundation

class PluginManager {
    static let shared = PluginManager()
    let barItem = MenubarItem(title: "SwiftBar")
    var plugins: [Plugin] = []
    var menuBarItems: [PluginID: MenubarItem] = [:]
    var pluginsFolder: String = "" {
        didSet {
            loadPlugins()
        }
    }

    func addPlugin(from file: String) {

    }
    
    /// Scan pluginsFolder for all potential scripts
    func loadPlugins() {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: pluginsFolder, isDirectory: &isDir), isDir.boolValue else {
            plugins.removeAll()
            menuBarItems.removeAll()
            barItem.show()
            return
        }
        barItem.hide()
    }
}
