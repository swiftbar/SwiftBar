import Cocoa
import Combine
import Foundation
import os
import SwiftUI
import UserNotifications

extension URL {
    /// Whether this URL represents a SwiftBar packaged plugin directory (`.swiftbar` bundle).
    var isSwiftBarPackage: Bool {
        lastPathComponent.hasSuffix(".swiftbar")
    }
}

struct PluginFileState: Equatable {
    let size: UInt64
    let modificationDate: Date?
}

enum PluginFileSkipReason: String {
    case notRegularFile = "not a regular file"
    case emptyFile = "empty file"
    case notExecutable = "not executable while auto-make-executable is disabled"
}

/// Returns the packaged plugin directory for a file URL, if the URL is inside
/// (or is itself) a `.swiftbar` bundle. Handles both direct paths and symlinks,
/// so that packaged plugins are treated as a single atomic unit during sync.
func packagedPluginDirectory(for fileURL: URL) -> URL? {
    if fileURL.isSwiftBarPackage {
        return fileURL
    }

    let parentDirectory = fileURL.deletingLastPathComponent()
    if parentDirectory.isSwiftBarPackage {
        return parentDirectory
    }

    let resolvedFileURL = fileURL.resolvingSymlinksInPath()
    if resolvedFileURL.isSwiftBarPackage {
        return resolvedFileURL
    }

    let resolvedParentDirectory = resolvedFileURL.deletingLastPathComponent()
    return resolvedParentDirectory.isSwiftBarPackage ? resolvedParentDirectory : nil
}

/// Returns a canonical path used to identify a plugin across sync cycles.
/// For packaged plugins this is the bundle directory path; for regular plugins
/// it is the symlink-resolved file path.
func pluginSyncPath(for fileURL: URL) -> String {
    packagedPluginDirectory(for: fileURL)?.path ?? fileURL.resolvingSymlinksInPath().path
}

func pluginSyncPath(for plugin: Plugin) -> String {
    pluginSyncPath(for: URL(fileURLWithPath: plugin.file))
}

private func packagedPluginFileState(for packageURL: URL, fileManager: FileManager = .default) -> PluginFileState? {
    let resolvedPackageURL = packageURL.resolvingSymlinksInPath()
    guard PackagedPlugin.findMainExecutable(in: resolvedPackageURL) != nil,
          let enumerator = fileManager.enumerator(at: resolvedPackageURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    else {
        return nil
    }

    var totalSize: UInt64 = 0
    var latestModificationDate = (try? fileManager.attributesOfItem(atPath: resolvedPackageURL.path)[.modificationDate] as? Date) ?? nil
    var hasRegularFile = false

    for case let entryURL as URL in enumerator {
        let resolvedEntryURL = entryURL.resolvingSymlinksInPath()
        guard let attributes = try? fileManager.attributesOfItem(atPath: resolvedEntryURL.path),
              let fileType = attributes[.type] as? FileAttributeType
        else {
            continue
        }

        if fileType == .typeDirectory {
            continue
        }

        hasRegularFile = true

        if let fileSize = attributes[.size] as? NSNumber {
            totalSize += fileSize.uint64Value
        }

        if let modificationDate = attributes[.modificationDate] as? Date,
           latestModificationDate.map({ modificationDate > $0 }) ?? true
        {
            latestModificationDate = modificationDate
        }
    }

    guard hasRegularFile else {
        return nil
    }

    return PluginFileState(size: totalSize, modificationDate: latestModificationDate)
}

func pluginFileState(for fileURL: URL, fileManager: FileManager = .default) -> PluginFileState? {
    if let packageDirectory = packagedPluginDirectory(for: fileURL) {
        return packagedPluginFileState(for: packageDirectory, fileManager: fileManager)
    }

    let resolvedFileURL = fileURL.resolvingSymlinksInPath()

    guard let attributes = try? fileManager.attributesOfItem(atPath: resolvedFileURL.path),
          let fileType = attributes[.type] as? FileAttributeType,
          fileType == .typeRegular,
          let fileSize = attributes[.size] as? NSNumber
    else {
        return nil
    }

    return PluginFileState(
        size: fileSize.uint64Value,
        modificationDate: attributes[.modificationDate] as? Date
    )
}

func pluginFileSkipReason(for fileURL: URL, makePluginExecutable: Bool, fileManager: FileManager = .default) -> PluginFileSkipReason? {
    guard let state = pluginFileState(for: fileURL, fileManager: fileManager) else {
        return .notRegularFile
    }

    guard state.size > 0 else {
        return .emptyFile
    }

    if !makePluginExecutable, !fileManager.isExecutableFile(atPath: fileURL.path) {
        return .notExecutable
    }

    return nil
}

func shouldLoadPluginFile(at fileURL: URL, makePluginExecutable: Bool, fileManager: FileManager = .default) -> Bool {
    if let skipReason = pluginFileSkipReason(for: fileURL, makePluginExecutable: makePluginExecutable, fileManager: fileManager) {
        os_log("Skipping plugin candidate %{public}@ (%{public}@)", log: Log.plugin, type: .info, fileURL.path, skipReason.rawValue)
        return false
    }

    return true
}

func shouldShowDefaultBarItem(hasVisiblePlugins: Bool, stealthMode: Bool) -> Bool {
    !stealthMode && !hasVisiblePlugins
}

struct FilePluginSyncResult {
    let removedPluginIDs: Set<PluginID>
    let modifiedPluginIDs: Set<PluginID>
    let loadedPlugins: [Plugin]
    let freshFileStates: [String: PluginFileState]
}

func syncFilePlugins(existingFilePlugins: [Plugin], freshFilePlugins: [URL], previousFileStates: [String: PluginFileState], discoveredFilePlugins: [URL]? = nil, fileManager: FileManager = .default, loadPlugin: (URL) -> Plugin?) -> FilePluginSyncResult {
    let discoveredFilePlugins = discoveredFilePlugins ?? freshFilePlugins
    let discoveredPluginPaths = Set(discoveredFilePlugins.map { pluginSyncPath(for: $0) })
    let existingPluginPaths = Set(existingFilePlugins.map { pluginSyncPath(for: $0) })

    // 1. Build fresh file state map from current disk contents
    let freshFileStates = Dictionary(uniqueKeysWithValues: freshFilePlugins.compactMap { fileURL in
        let syncPath = pluginSyncPath(for: fileURL)
        return pluginFileState(for: fileURL, fileManager: fileManager).map { (syncPath, $0) }
    })

    // 2. Find removed plugins (present in existing but absent from fresh list)
    let removedPlugins = existingFilePlugins.filter { plugin in
        !discoveredPluginPaths.contains(pluginSyncPath(for: plugin))
    }

    // 3. Find modified plugins (state on disk differs from previously recorded state)
    let modifiedPlugins = existingFilePlugins.filter { plugin in
        let syncPath = pluginSyncPath(for: plugin)
        guard let freshState = freshFileStates[syncPath] else { return false }
        return previousFileStates[syncPath] != freshState
    }
    let modifiedPluginPaths = Set(modifiedPlugins.map { pluginSyncPath(for: $0) })

    // 4. Determine which files need (re)loading: new files + modified files
    let filesToLoad = Set(
        freshFilePlugins
            .filter { fileURL in
                let syncPath = pluginSyncPath(for: fileURL)
                return !existingPluginPaths.contains(syncPath) || modifiedPluginPaths.contains(syncPath)
            }
            .map { pluginSyncPath(for: $0) }
    )

    let loadedPlugins = freshFilePlugins
        .filter { filesToLoad.contains(pluginSyncPath(for: $0)) }
        .compactMap(loadPlugin)

    return FilePluginSyncResult(
        removedPluginIDs: Set(removedPlugins.map(\.id)),
        modifiedPluginIDs: Set(modifiedPlugins.map(\.id)),
        loadedPlugins: loadedPlugins,
        freshFileStates: freshFileStates
    )
}

func mergePluginsPreservingOrder(existingPlugins: [Plugin], removedPluginIDs: Set<PluginID>, reloadedFilePlugins: [Plugin], newShortcutPlugins: [ShortcutPlugin]) -> [Plugin] {
    let reloadedPluginsBySyncPath = Dictionary(uniqueKeysWithValues: reloadedFilePlugins.map { (pluginSyncPath(for: $0), $0) })
    let reloadedPluginSyncPaths = Set(reloadedFilePlugins.map { pluginSyncPath(for: $0) })
    var consumedReloadedFiles = Set<String>()
    var mergedPlugins: [Plugin] = []

    // Only file-backed plugins (Executable/Streamable) are eligible for in-place replacement.
    for plugin in existingPlugins where !removedPluginIDs.contains(plugin.id) {
        let syncPath = pluginSyncPath(for: plugin)
        guard (plugin.type == .Executable || plugin.type == .Streamable),
              reloadedPluginSyncPaths.contains(syncPath),
              let replacementPlugin = reloadedPluginsBySyncPath[syncPath]
        else {
            mergedPlugins.append(plugin)
            continue
        }

        mergedPlugins.append(replacementPlugin)
        consumedReloadedFiles.insert(syncPath)
    }

    let appendedFilePlugins = reloadedFilePlugins.filter { !consumedReloadedFiles.contains(pluginSyncPath(for: $0)) }
    mergedPlugins.append(contentsOf: appendedFilePlugins)
    mergedPlugins.append(contentsOf: newShortcutPlugins)

    return mergedPlugins
}

class PluginManager: ObservableObject {
    static let shared = PluginManager()
    let prefs = PreferencesStore.shared
    lazy var barItem: MenubarItem = .defaultBarItem()

    #if !MAC_APP_STORE
        var directoryObserver: DirectoryObserver?
    #endif

    @Published var plugins: [Plugin] = [] {
        didSet {
            shortcutPlugins = plugins.filter { $0.type == .Shortcut }.compactMap { $0 as? ShortcutPlugin }

            pluginsDidChange()
        }
    }

    @Published var shortcutPlugins: [ShortcutPlugin] = []
    var filePluginStates: [String: PluginFileState] = [:]
    var directoryChangeWorkItem: DispatchWorkItem?
    private var isUpdatingDefaultBarItemVisibility = false
    private static let directoryChangeDebounceInterval: TimeInterval = 0.5

    var filePlugins: [Plugin] {
        plugins.filter { $0.type == .Streamable || $0.type == .Executable }
    }

    var ephemeralPlugins: [EphemeralPlugin] {
        plugins.filter { $0.type == .Ephemeral }.compactMap { $0 as? EphemeralPlugin }
    }

    var enabledPlugins: [Plugin] {
        plugins.filter(\.enabled)
    }

    var menuBarItems: [PluginID: MenubarItem] = [:]
    var pluginDirectoryURL: URL? {
        prefs.pluginDirectoryResolvedURL
    }

    var ignoreFileContent: String? {
        guard let url = pluginDirectoryURL,
              case let ignoreFile = url.appendingPathComponent(".swiftbarignore"),
              FileManager.default.fileExists(atPath: ignoreFile.path),
              let content = try? String(contentsOfFile: ignoreFile.path)
        else { return nil }
        return content
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
            self?.menuBarItems.values.forEach { item in
                // this is not ideal, but should work in most cases — we should not reload plugins with active background webviews
                guard item.plugin?.metadata?.persistentWebView != true else {
                    return
                }
                item.updateMenu(content: item.plugin?.content)
            }
        }
    }

    func pluginsDidChange() {
        os_log("Plugins did change, updating menu bar...", log: Log.plugin)
        let enabledIDs = Set(enabledPlugins.map(\.id))

        for plugin in enabledPlugins {
            if let existingMenuBarItem = menuBarItems[plugin.id] {
                if existingMenuBarItem.plugin !== plugin {
                    existingMenuBarItem.replacePlugin(plugin)
                }
                continue
            }
            menuBarItems[plugin.id] = MenubarItem(title: plugin.name, plugin: plugin, visibilityDidChange: { [weak self] _ in
                self?.updateDefaultBarItemVisibility()
            })
        }
        for pluginID in menuBarItems.keys {
            guard !enabledIDs.contains(pluginID) else { continue }
            menuBarItems.removeValue(forKey: pluginID)
        }

        updateDefaultBarItemVisibility()
    }

    func updateDefaultBarItemVisibility() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updateDefaultBarItemVisibility()
            }
            return
        }

        guard !isUpdatingDefaultBarItemVisibility else { return }
        isUpdatingDefaultBarItemVisibility = true
        defer { isUpdatingDefaultBarItemVisibility = false }

        let hasVisiblePlugins = enabledPlugins.contains { plugin in
            menuBarItems[plugin.id]?.barItem.isVisible == true
        }

        shouldShowDefaultBarItem(hasVisiblePlugins: hasVisiblePlugins, stealthMode: prefs.stealthMode) ? barItem.show() : barItem.hide()
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

        // Track processed directories by their resolved paths to avoid duplicates
        var processedDirs = Set<String>()

        func filter(url: URL) -> (files: [URL], dirs: [URL]) {
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            else { return ([], []) }
            var dirs: [URL] = []
            var files: [URL] = []
            for case let origURL as URL in enumerator {
                let resolvedURL = origURL.resolvingSymlinksInPath()
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: resolvedURL.path, isDirectory: &isDir) else {
                    continue
                }
                if isDir.boolValue {
                    // Treat .swiftbar directories as packaged plugin files and skip their contents
                    if origURL.isSwiftBarPackage {
                        files.append(origURL)
                        enumerator.skipDescendants()
                        continue
                    }
                    // Only add directory if we haven't processed its resolved path yet
                    if !processedDirs.contains(resolvedURL.path) {
                        processedDirs.insert(resolvedURL.path)
                        dirs.append(origURL)
                    }
                    continue
                }
                // Exclude .json files (used for plugin variable storage)
                if origURL.pathExtension.lowercased() == "json" {
                    continue
                }
                files.append(origURL)
            }
            return (files, dirs)
        }

        func filterFilesAndDirs(files: [URL], dirs: [URL], ignoreContent: String) -> (filteredFiles: [URL], filteredDirs: [URL]) {
            let lines = ignoreContent.split(separator: "\n").map(String.init)
            var ignorePatterns: [String] = []

            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedLine.isEmpty, !trimmedLine.starts(with: "#") {
                    ignorePatterns.append(trimmedLine)
                }
            }

            func shouldBeIgnored(url: URL, patterns: [String], baseURL: URL) -> Bool {
                // Get relative path from plugin directory
                let relativePath = url.path.replacingOccurrences(of: baseURL.path + "/", with: "")
                let filename = url.lastPathComponent

                for pattern in patterns {
                    // Direct filename match
                    if filename == pattern || relativePath == pattern {
                        return true
                    }

                    // Convert glob pattern to regex
                    let escapedPattern = NSRegularExpression.escapedPattern(for: pattern)
                        .replacingOccurrences(of: "\\*\\*/", with: "(.*/)?") // ** matches any directory depth
                        .replacingOccurrences(of: "\\*", with: "[^/]*") // * matches within directory
                        .replacingOccurrences(of: "\\?", with: "[^/]") // ? matches single character

                    // Try to match against both filename and relative path
                    if let regex = try? NSRegularExpression(pattern: "^\(escapedPattern)$", options: []) {
                        let filenameRange = NSRange(location: 0, length: filename.utf16.count)
                        let pathRange = NSRange(location: 0, length: relativePath.utf16.count)

                        if regex.firstMatch(in: filename, options: [], range: filenameRange) != nil ||
                            regex.firstMatch(in: relativePath, options: [], range: pathRange) != nil
                        {
                            return true
                        }
                    }
                }
                return false
            }

            let filteredFiles = files.filter { !shouldBeIgnored(url: $0, patterns: ignorePatterns, baseURL: url) }
            let filteredDirs = dirs.filter { !shouldBeIgnored(url: $0, patterns: ignorePatterns, baseURL: url) }

            return (filteredFiles, filteredDirs)
        }

        var (files, dirs) = filter(url: url)
        if let ignoreFileContent {
            (files, dirs) = filterFilesAndDirs(files: files, dirs: dirs, ignoreContent: ignoreFileContent)
        }

        // Only process directories that weren't filtered out by ignore patterns
        if !dirs.isEmpty {
            for dir in dirs {
                let (subFiles, subDirs) = filter(url: dir)
                if let ignoreFileContent {
                    let (filteredSubFiles, _) = filterFilesAndDirs(files: subFiles, dirs: subDirs, ignoreContent: ignoreFileContent)
                    files.append(contentsOf: filteredSubFiles)
                } else {
                    files.append(contentsOf: subFiles)
                }
            }
        }

        // Deduplicate files based on resolved paths
        var uniqueFiles: [URL] = []
        var seenPaths = Set<String>()

        for file in files {
            let resolvedPath = file.resolvingSymlinksInPath().path
            if !seenPaths.contains(resolvedPath) {
                seenPaths.insert(resolvedPath)
                uniqueFiles.append(file)
            }
        }

        return uniqueFiles
    }

    func getLoadablePluginList(from pluginCandidates: [URL]) -> [URL] {
        pluginCandidates.filter { url in
            if url.isSwiftBarPackage {
                guard PackagedPlugin.findMainExecutable(in: url) != nil else {
                    os_log("Skipping packaged plugin candidate %{public}@ (missing plugin.* entry point)", log: Log.plugin, type: .info, url.path)
                    return false
                }
                return true
            }
            return shouldLoadPluginFile(at: url, makePluginExecutable: prefs.makePluginExecutable)
        }
    }

    func loadShortcutPlugins() -> [ShortcutPlugin] {
        prefs.shortcutsPlugins.map { ShortcutPlugin($0) }
    }

    func unloadPlugins(_ pluginsToUnload: [Plugin], clearDisabledState: Bool) {
        let pluginIDs = Set(pluginsToUnload.map(\.id))

        for plugin in pluginsToUnload {
            plugin.terminate()
            menuBarItems.removeValue(forKey: plugin.id)

            if clearDisabledState {
                prefs.disabledPlugins.removeAll(where: { $0 == plugin.id })
            }
        }

        plugins.removeAll(where: { pluginIDs.contains($0.id) })
    }

    func loadPlugins() {
        #if !MAC_APP_STORE
            if directoryObserver?.url != pluginDirectoryURL {
                configureDirectoryObserver()
            }
        #endif
        let freshShortcutPlugins = loadShortcutPlugins()
        let discoveredFilePlugins = getPluginList()
        let freshFilePlugins = getLoadablePluginList(from: discoveredFilePlugins)
        guard discoveredFilePlugins.count < 50 else {
            let alert = NSAlert()
            alert.messageText = Localizable.App.FolderHasToManyFilesMessage.localized
            alert.runModal()

            AppShared.changePluginFolder()
            return
        }
        guard !freshFilePlugins.isEmpty || !freshShortcutPlugins.isEmpty else {
            plugins.removeAll()
            shortcutPlugins.removeAll()
            menuBarItems.removeAll()
            filePluginStates.removeAll()
            // Preserve the original escape hatch: if everything is gone, show SwiftBar
            // even in stealth mode so the user can recover.
            barItem.show()
            return
        }

        let newShortcutPlugins = freshShortcutPlugins.filter { plugin in
            !plugins.contains(where: { $0.id == plugin.id })
        }

        let removedShortcutPlugins = shortcutPlugins.filter { plugin in
            !freshShortcutPlugins.contains(where: { $0.id == plugin.id })
        }

        let fileSyncResult = syncFilePlugins(
            existingFilePlugins: filePlugins,
            freshFilePlugins: freshFilePlugins,
            previousFileStates: filePluginStates,
            discoveredFilePlugins: discoveredFilePlugins,
            loadPlugin: loadPlugin(fileURL:)
        )

        let removedFilePlugins = filePlugins.filter { fileSyncResult.removedPluginIDs.contains($0.id) }
        let modifiedFilePlugins = filePlugins.filter { fileSyncResult.modifiedPluginIDs.contains($0.id) }

        for plugin in modifiedFilePlugins {
            plugin.terminate()
        }

        for plugin in removedFilePlugins + removedShortcutPlugins {
            plugin.terminate()
            menuBarItems.removeValue(forKey: plugin.id)
            prefs.disabledPlugins.removeAll(where: { $0 == plugin.id })
        }

        let removedPluginIDs = fileSyncResult.removedPluginIDs.union(removedShortcutPlugins.map(\.id))
        plugins = mergePluginsPreservingOrder(
            existingPlugins: plugins,
            removedPluginIDs: removedPluginIDs,
            reloadedFilePlugins: fileSyncResult.loadedPlugins,
            newShortcutPlugins: newShortcutPlugins
        )
        filePluginStates = fileSyncResult.freshFileStates
    }

    func loadPlugin(fileURL: URL) -> Plugin? {
        // Check if this is a packaged plugin (.swiftbar directory)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir),
           isDir.boolValue,
           fileURL.isSwiftBarPackage
        {
            if let packagedPlugin = PackagedPlugin(packageDirectory: fileURL) {
                return packagedPlugin
            }
            os_log("Failed to load packaged plugin at %{public}@", log: Log.plugin, type: .error, fileURL.path)
            return nil
        }
        return StreamablePlugin(fileURL: fileURL) ?? ExecutablePlugin(fileURL: fileURL)
    }

    func refreshAllPlugins(reason: PluginRefreshReason) {
        #if MAC_APP_STORE
            loadPlugins()
        #endif
        os_log("Refreshing all enabled plugins.", log: Log.plugin)
        menuBarItems.values.forEach { $0.dimOnManualRefresh() }
        pluginInvokeQueue.cancelAllOperations() // clean up the update queue to avoid duplication
        enabledPlugins.forEach { $0.refresh(reason: reason) }
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

    func refreshPlugin(with index: Int, reason: PluginRefreshReason) {
        guard plugins.indices.contains(index) else { return }
        plugins[index].refresh(reason: reason)
    }

    func addShortcutPlugin(plugin: PersistentShortcutPlugin) {
        prefs.shortcutsPlugins.append(plugin)
        loadPlugins()
    }

    func removeShortcutPlugin(plugin: PersistentShortcutPlugin) {
        prefs.shortcutsPlugins.removeAll(where: { $0.id == plugin.id })
        loadPlugins()
    }

    func setEphemeralPlugin(pluginId: PluginID, content: String, exitAfter: Double = 0) {
        if let plugin = ephemeralPlugins.first(where: { $0.id == pluginId }) {
            guard !content.isEmpty else {
                plugins.removeAll(where: { $0.id == pluginId && $0.type == .Ephemeral })
                return
            }
            plugin.content = content
            plugin.updateInterval = exitAfter
            return
        }

        plugins.append(EphemeralPlugin(id: pluginId, content: content, exitAfter: exitAfter))
    }

    enum ImportPluginError: Error {
        case badURL
        case importFail
    }

    private func installImportedPlugin(from sourceURL: URL, moveItem: Bool, completionHandler: ((Result<Any, ImportPluginError>) -> Void)? = nil) {
        guard let pluginDirectoryURL = pluginDirectoryURL else {
            completionHandler?(.failure(.badURL))
            return
        }

        let targetURL = pluginDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)
        if sourceURL.resolvingSymlinksInPath().path == targetURL.resolvingSymlinksInPath().path {
            completionHandler?(.success(true))
            return
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
            completionHandler?(.failure(.badURL))
            return
        }

        do {
            if moveItem {
                try FileManager.default.moveItem(at: sourceURL, to: targetURL)
            } else {
                try FileManager.default.copyItem(at: sourceURL, to: targetURL)
            }

            if !isDirectory.boolValue {
                try runScript(to: "chmod", args: ["+x", "\(targetURL.path.escaped())"])
            }

            completionHandler?(.success(true))
        } catch {
            completionHandler?(.failure(.importFail))
            os_log("Failed to import plugin from %{public}@ \n%{public}@", log: Log.plugin, type: .error, sourceURL.absoluteString, error.localizedDescription)
        }
    }

    func importPlugin(from url: URL, completionHandler: ((Result<Any, ImportPluginError>) -> Void)? = nil) {
        os_log("Starting plugin import from %{public}@", log: Log.plugin, url.absoluteString)
        if url.isFileURL {
            let accessedSecurityScopedResource = url.startAccessingSecurityScopedResource()
            defer {
                if accessedSecurityScopedResource {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            installImportedPlugin(from: url, moveItem: false, completionHandler: completionHandler)
            return
        }

        let downloadTask = URLSession.shared.downloadTask(with: url) { fileURL, _, _ in
            guard let fileURL else {
                completionHandler?(.failure(.badURL))
                return
            }

            let renamedDownloadURL = fileURL.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: renamedDownloadURL.path) {
                    try FileManager.default.removeItem(at: renamedDownloadURL)
                }
                try FileManager.default.moveItem(at: fileURL, to: renamedDownloadURL)
                self.installImportedPlugin(from: renamedDownloadURL, moveItem: true, completionHandler: completionHandler)
            } catch {
                completionHandler?(.failure(.importFail))
                os_log("Failed to prepare imported plugin from %{public}@ \n%{public}@", log: Log.plugin, type: .error, url.absoluteString, error.localizedDescription)
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
        directoryChangeWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.loadPlugins()
        }

        directoryChangeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.directoryChangeDebounceInterval, execute: workItem)
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

        if let commandParams {
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
