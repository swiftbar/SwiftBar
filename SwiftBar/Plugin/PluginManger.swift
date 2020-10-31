import Foundation
import ShellOut

class PluginManager {
    static let shared = PluginManager()
    let barItem = MenubarItem.defaultBarItem()
    var directoryObserver: DirectoryObserver?

    var plugins: [Plugin] = [] {
        didSet {
            pluginsDidChange()
        }
    }
    var menuBarItems: [PluginID: MenubarItem] = [:]
    var pluginDirectoryURL: URL? {
        guard let pluginDirectoryPath = App.pluginDirectoryPath, let url = URL(string: pluginDirectoryPath) else {return nil}
        return url
    }

    init() {
        configureDirectoryObserver()
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
    
    func getPluginList() -> [URL] {
        guard let pluginDirectoryPath = App.pluginDirectoryPath, let url = pluginDirectoryURL else {return []}
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: pluginDirectoryPath, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else {return []}
        return enumerator.compactMap{$0 as? URL}.filter{$0.lastPathComponent != ".DS_Store"}
    }

    func loadPlugins() {
        if directoryObserver?.url != pluginDirectoryURL {
            configureDirectoryObserver()
        }
        
        let pluginFiles = getPluginList()
        guard !pluginFiles.isEmpty else {
            plugins.removeAll()
            menuBarItems.removeAll()
            barItem.show()
            return
        }

        let newPlugins = pluginFiles.filter { file in
            !plugins.contains(where: {$0.file == file.absoluteString})
        }

        let removedPlugins = plugins.filter { plugin in
            !pluginFiles.contains(where: {$0.absoluteString == plugin.file})
        }

        removedPlugins.forEach { plugin in
            menuBarItems.removeValue(forKey: plugin.id)
            plugins.removeAll(where: {$0.id == plugin.id})
        }

        newPlugins.forEach{addPlugin(from: $0)}
    }

    func refreshAllPlugins() {
        plugins.forEach{$0.refresh()}
    }

    func refreshPlugin(named name: String) {
        guard let plugin = plugins.first(where: {$0.name.lowercased() == name.lowercased()}) else {return}
        plugin.refresh()
    }

    func refreshPlugin(with index: Int) {
        guard plugins.indices.contains(index) else {return}
        plugins[index].refresh()
    }

    func importPlugin(from url: URL) {
        let downloadTask = URLSession.shared.downloadTask(with: url) { fileURL, _, _ in
            guard let fileURL = fileURL, let pluginDirectoryURL = self.pluginDirectoryURL else { return }
            do {
                let targetURL = pluginDirectoryURL.appendingPathComponent(url.lastPathComponent)
                try shellOut(to: "chmod a+x \(fileURL.path)")
                try FileManager.default.moveItem(atPath: fileURL.path, toPath: targetURL.path)
            } catch {
                print ("file error: \(error)")
            }
        }
        downloadTask.resume()
    }

    func configureDirectoryObserver() {
        if let url = pluginDirectoryURL {
            directoryObserver = DirectoryObserver(url: url, block: { [weak self] in
                self?.directoryChanged()
            })
        }
    }
    func directoryChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.loadPlugins()
        }
    }
}
