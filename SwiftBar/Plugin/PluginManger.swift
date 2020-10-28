import Foundation

class PluginManager {
    static let shared = PluginManager()
    let barItem = MenubarItem.defaultBarItem()
    var plugins: [Plugin] = [] {
        didSet {
            pluginsDidChange()
        }
    }
    var menuBarItems: [PluginID: MenubarItem] = [:]

    init() {
        loadPlugins()
    }

    func pluginsDidChange() {
        plugins.forEach{ plugin in
            guard menuBarItems[plugin.id] == nil else {return}
            menuBarItems[plugin.id] = MenubarItem(title: plugin.name, plugin: plugin)
        }
        menuBarItems.keys.forEach{ pluginID in
            guard !plugins.contains(where: {$0.id == pluginID}) else {return}
            menuBarItems.removeValue(forKey: pluginID)
        }
        plugins.isEmpty ? barItem.show():barItem.hide()
    }

    func addPlugin(from fileURL: URL) {
        plugins.append(ExecutablePlugin(fileURL: fileURL))
    }

    func disablePlugin(plugin: Plugin) {
        plugins.removeAll(where: {$0.id == plugin.id})
    }
    
    /// Scan pluginsFolder for all potential scripts
    func loadPlugins() {
        guard let pluginDirectoryPath = App.pluginDirectoryPath, let url = URL(string: pluginDirectoryPath) else {return}
        plugins.removeAll()
        menuBarItems.removeAll()
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: pluginDirectoryPath, isDirectory: &isDir), isDir.boolValue else {
            barItem.show()
            return
        }

        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
        while let element = enumerator?.nextObject() as? URL {
            guard element.lastPathComponent != ".DS_Store" else {continue}
            addPlugin(from: element)
        }
        print(plugins)
    }
}
