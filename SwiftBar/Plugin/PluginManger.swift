import Cocoa
import Combine
import Foundation
import os
import SwiftUI
import UserNotifications

class PluginManager: ObservableObject {
    static let shared = PluginManager()
    let prefs = PreferencesStore.shared
    lazy var barItem: MenubarItem = .defaultBarItem()

    #if !MAC_APP_STORE
        var directoryObserver: DirectoryObserver?
    #endif

    @Published var plugins: [Plugin] = [] {
        didSet {
            pluginsDidChange()
        }
    }

    var enabledPlugins: [Plugin] {
        plugins.filter(\.enabled)
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
        queue.maxConcurrentOperationCount = 10
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
            self?.menuBarItems.values.forEach { $0.updateMenu(content: $0.plugin?.content) }
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

        enabledPlugins.isEmpty && !prefs.stealthMode ? barItem.show() : barItem.hide()
    }

    func getPluginByNameOrID(identifier: String) -> Plugin? {
        plugins.first(where: { $0.id.lowercased() == identifier.lowercased() }) ??
            plugins.first(where: { $0.name.lowercased() == identifier.lowercased() })
    }

    func disablePlugin(plugin: Plugin) {
        os_log("Disabling plugin \n%{public}@", log: Log.plugin, plugin.description)
        plugin.disable()
    }

    func enablePlugin(plugin: Plugin) {
        os_log("Enabling plugin \n%{public}@", log: Log.plugin, plugin.description)
        plugin.enable()
    }

    func togglePlugin(plugin: Plugin) {
        plugin.enabled ? disablePlugin(plugin: plugin) : enablePlugin(plugin: plugin)
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
        #if !MAC_APP_STORE
            if directoryObserver?.url != pluginDirectoryURL {
                configureDirectoryObserver()
            }
        #endif

        let pluginFiles = getPluginList()
        guard pluginFiles.count < 50 else {
            let alert = NSAlert()
            alert.messageText = Localizable.App.FolderHasToManyFilesMessage.localized
            alert.runModal()

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

        let removedPlugins = plugins.filter { plugin in
            !pluginFiles.contains(where: { $0.path == plugin.file })
        }

        removedPlugins.forEach { plugin in
            menuBarItems.removeValue(forKey: plugin.id)
            prefs.disabledPlugins.removeAll(where: { $0 == plugin.id })
            plugins.removeAll(where: { $0.id == plugin.id })
        }

        plugins.append(contentsOf: newPluginsFiles.map { loadPlugin(fileURL: $0) })
    }

    func loadPlugin(fileURL: URL) -> Plugin {
        StreamablePlugin(fileURL: fileURL) ?? ExecutablePlugin(fileURL: fileURL)
    }

    func refreshAllPlugins() {
        #if MAC_APP_STORE
            loadPlugins()
        #endif
        os_log("Refreshing all enabled plugins.", log: Log.plugin)
        menuBarItems.values.forEach { $0.dimOnManualRefresh() }
        pluginInvokeQueue.cancelAllOperations() // clean up the update queue to avoid duplication
        enabledPlugins.forEach { $0.refresh() }
    }

    func startAllPlugins() {
        os_log("Starting all enabled plugins.", log: Log.plugin)
        pluginInvokeQueue.cancelAllOperations() // clean up the update queue to avoid duplication
        enabledPlugins.forEach { $0.start() }
    }

    func terminateAllPlugins() {
        os_log("Stoping all enabled plugins.", log: Log.plugin)
        enabledPlugins.forEach { $0.terminate() }
        pluginInvokeQueue.cancelAllOperations()
    }

    func rebuildAllMenus() {
        menuBarItems.values.forEach { $0.updateMenu(content: $0.plugin?.content) }
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
                try FileManager.default.moveItem(atPath: fileURL.path, toPath: targetURL.path)
                try runScript(to: "chmod", args: ["+x", "\(targetURL.path.escaped())"])
                completionHandler?(.success(true))
            } catch {
                completionHandler?(.failure(.importFail))
                os_log("Failed to import plugin from %{public}@ \n%{public}@", log: Log.plugin, type: .error, url.absoluteString, error.localizedDescription)
            }
        }
        downloadTask.resume()
    }

    #if !MAC_APP_STORE
        func configureDirectoryObserver() {
            if let url = pluginDirectoryURL {
                directoryObserver = DirectoryObserver(url: url, block: { [weak self] in
                    self?.directoryChanged()
                })
            }
        }
    #endif

    func directoryChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.loadPlugins()
        }
    }
}

extension PluginManager {
    func showNotification(plugin: Plugin, title: String?, subtitle: String?, body: String?, href: String?, commandParams: String?, silent: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title ?? ""
        content.subtitle = subtitle ?? ""
        content.body = body ?? ""
        content.sound = silent ? nil : .default
        content.threadIdentifier = plugin.id

        content.userInfo[SystemNotificationName.pluginID] = plugin.id

        if let urlString = href,
           let url = URL(string: urlString), url.host != nil, url.scheme != nil
        {
            content.userInfo[SystemNotificationName.url] = urlString
        }

        if let commandParams = commandParams {
            content.userInfo[SystemNotificationName.command] = commandParams
        }

        let uuidString = UUID().uuidString
        let request = UNNotificationRequest(identifier: uuidString,
                                            content: content, trigger: nil)

        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        notificationCenter.delegate = delegate
        notificationCenter.add(request)
    }
}
