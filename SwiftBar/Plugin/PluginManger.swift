import Cocoa
import Combine
import Foundation
import os
import ShellOut
import UserNotifications

class PluginManager {
    static let shared = PluginManager()
    let prefs = Preferences.shared
    lazy var barItem: MenubarItem = {
        MenubarItem.defaultBarItem()
    }()

    var directoryObserver: DirectoryObserver?

    private var plugins: [Plugin] = [] {
        didSet {
            pluginsDidChange()
        }
    }

    var sortedPlugins: [Plugin] {
        plugins
            .sorted(by: {
                guard let first = prefs.pluginsOrder.firstIndex(of: $0.id) else {
                    return false
                }
                guard let second = prefs.pluginsOrder.firstIndex(of: $1.id) else {
                    return true
                }
                return first < second
            })
    }

    var enabledPlugins: [Plugin] {
        sortedPlugins.filter { $0.enabled }
    }

    var menuBarItems: [PluginID: MenubarItem] = [:]
    var pluginDirectoryURL: URL? {
        prefs.pluginDirectoryResolvedURL
    }

    var disablePluginCancellable: AnyCancellable?
    var osAppearanceChangeCancellable: AnyCancellable?

    let pluginInvokeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 20
        return queue
    }()

    let menuUpdateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInteractive
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    init() {
        disablePluginCancellable = prefs.disabledPluginsPublisher
            .receive(on: RunLoop.main)
            .sink(receiveValue: { [weak self] _ in
                os_log("Recieved plugin enable/disable notification", log: Log.plugin)
                self?.pluginsDidChange()
            })

        osAppearanceChangeCancellable = DistributedNotificationCenter.default().publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification")).sink { [weak self] _ in
            self?.menuBarItems.values.forEach { $0.updateMenu() }
        }
    }

    func pluginsDidChange() {
        os_log("Plugins did change, updating menu bar...", log: Log.plugin)
        enabledPlugins.forEach { plugin in
            guard menuBarItems[plugin.id] == nil else { return }
            menuBarItems[plugin.id] = MenubarItem(title: plugin.name, plugin: plugin)
        }
        menuBarItems.keys.forEach { pluginID in
            guard !enabledPlugins.contains(where: { $0.id == pluginID }) else { return }
            menuBarItems.removeValue(forKey: pluginID)
        }
        enabledPlugins.isEmpty ? barItem.show() : barItem.hide()
    }

    func disablePlugin(plugin: Plugin) {
        os_log("Disabling plugin \n%{public}@", log: Log.plugin, plugin.description)
        plugin.disable()
    }

    func enablePlugin(plugin: Plugin) {
        os_log("Enabling plugin \n%{public}@", log: Log.plugin, plugin.description)
        plugin.enable()
    }

    func disableAllPlugins() {
        os_log("Disabling all plugins.", log: Log.plugin)
        plugins.forEach { $0.disable() }
    }

    func enableAllPlugins() {
        os_log("Enabling all plugins.", log: Log.plugin)
        plugins.forEach { $0.enable() }
    }

    func getPluginList() -> [URL] {
        guard let url = pluginDirectoryURL else { return [] }
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        func filter(url: URL) -> (files: [URL], dirs: [URL]) {
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            else { return ([], []) }
            var dirs: [URL] = []
            let files = enumerator.compactMap { $0 as? URL }.filter { origURL in
                let url = origURL.resolvingSymlinksInPath()
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
                    dirs.append(url)
                    return false
                }
                return true
            }
            return (files, dirs)
        }
        var (files, dirs) = filter(url: url)
        if !dirs.isEmpty {
            files.append(contentsOf: dirs.map { filter(url: $0) }.flatMap(\.files))
        }
        return Array(Set(files))
    }

    func loadPlugins() {
        if directoryObserver?.url != pluginDirectoryURL {
            configureDirectoryObserver()
        }

        let pluginFiles = getPluginList()
        guard pluginFiles.count < 50 else {
            AppShared.changePluginFolder()
            return
        }
        guard !pluginFiles.isEmpty else {
            plugins.removeAll()
            menuBarItems.removeAll()
            barItem.show()
            return
        }

        let newPluginsFiles = pluginFiles.filter { file in
            !plugins.contains(where: { $0.file == file.path })
        }
        let newPlugins = newPluginsFiles.map { loadPlugin(fileURL: $0) }

        let removedPlugins = plugins.filter { plugin in
            !pluginFiles.contains(where: { $0.path == plugin.file })
        }

        removedPlugins.forEach { plugin in
            menuBarItems.removeValue(forKey: plugin.id)
            plugins.removeAll(where: { $0.id == plugin.id })
            prefs.pluginsOrder.removeAll(where: { $0 == plugin.id })
        }

        prefs.pluginsOrder.append(contentsOf: newPlugins.map(\.id))
        plugins.append(contentsOf: newPlugins)
    }

    func loadPlugin(fileURL: URL) -> Plugin {
        StreamablePlugin(fileURL: fileURL) ?? ExecutablePlugin(fileURL: fileURL)
    }

    func refreshAllPlugins() {
        os_log("Refreshing all plugins.", log: Log.plugin)
        plugins.forEach { $0.refresh() }
    }

    func rebuildAllMenus() {
        menuBarItems.values.forEach { $0.updateMenu() }
    }

    func refreshPlugin(named name: String) {
        guard let plugin = plugins.first(where: { $0.name.lowercased() == name.lowercased() }) else { return }
        plugin.refresh()
    }

    func refreshPlugin(with index: Int) {
        guard plugins.indices.contains(index) else { return }
        plugins[index].refresh()
    }

    enum ImportPluginError: Error {
        case badURL
        case importFail
    }

    func importPlugin(from url: URL, completionHandler: ((Result<Any, ImportPluginError>) -> Void)? = nil) {
        os_log("Starting plugin import from %{public}@", log: Log.plugin, url.absoluteString)
        let downloadTask = URLSession.shared.downloadTask(with: url) { fileURL, _, _ in
            guard let fileURL = fileURL, let pluginDirectoryURL = self.pluginDirectoryURL else {
                completionHandler?(.failure(.badURL))
                return
            }
            do {
                let targetURL = pluginDirectoryURL.appendingPathComponent(url.lastPathComponent)
                try runScript(to: "chmod +x \(fileURL.path.escaped())")
                try FileManager.default.moveItem(atPath: fileURL.path, toPath: targetURL.path)
                completionHandler?(.success(true))
            } catch {
                completionHandler?(.failure(.importFail))
                os_log("Failed to import plugin from %{public}@ \n%{public}@", log: Log.plugin, type: .error, url.absoluteString, error.localizedDescription)
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

extension PluginManager {
    func showNotification(pluginID: PluginID, title: String?, subtitle: String?, body: String?, silent: Bool = false) {
        guard let plugin = plugins.first(where: { $0.id == pluginID }),
              plugin.enabled else { return }

        let content = UNMutableNotificationContent()
        content.title = title ?? ""
        content.subtitle = subtitle ?? ""
        content.body = body ?? ""
        content.sound = silent ? nil : .default
        content.threadIdentifier = pluginID

        let uuidString = UUID().uuidString
        let request = UNNotificationRequest(identifier: uuidString,
                                            content: content, trigger: nil)

        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        notificationCenter.delegate = delegate
        notificationCenter.add(request)
    }
}
