import Combine
import Foundation
import os

enum PluginType: String {
    case Executable
    case Streamable
    case Shortcut
    case Ephemeral

    static var debugable: [Self] {
        [.Executable, .Streamable]
    }

    static var runnableInTerminal: [Self] {
        [.Executable, .Streamable]
    }

    static var disableable: [Self] {
        [.Executable, .Streamable, .Shortcut]
    }
}

enum PluginState {
    case Loading
    case Streaming
    case Success
    case Failed
    case Disabled
}

enum PluginRefreshReason: String {
    case FirstLaunch
    case Schedule
    case MenuAction
    case RefreshAllMenu
    case RefreshAllURLScheme
    case URLScheme
    case Shortcut
    case DebugView
    case NotificationAction
    case PluginSettings
    case MenuOpen
    case WakeFromSleep

    static func manualReasons() -> [Self] {
        [
            .MenuAction,
            .RefreshAllMenu,
            .RefreshAllURLScheme,
            .URLScheme,
            .Shortcut,
            .NotificationAction,
            .PluginSettings,
            .DebugView,
            .MenuOpen,
        ]
    }
}

typealias PluginID = String

protocol Plugin: AnyObject {
    var id: PluginID { get }
    var type: PluginType { get }
    var name: String { get }
    var file: String { get }
    var enabled: Bool { get }
    var metadata: PluginMetadata? { get set }
    var contentUpdatePublisher: PassthroughSubject<String?, Never> { get set }
    var updateInterval: Double { get }
    var lastUpdated: Date? { get set }
    var lastState: PluginState { get set }
    var lastRefreshReason: PluginRefreshReason { get set }
    var content: String? { get set }
    var error: Error? { get set }
    var debugInfo: PluginDebugInfo { get set }
    var refreshEnv: [String: String] { get set }
    func refresh(reason: PluginRefreshReason)
    func enable()
    func disable()
    func start()
    func terminate()
    func invoke() -> String?
    func makeScriptExecutable(file: String)
    func refreshPluginMetadata()
}

extension Plugin {
    var description: String {
        """
        id: \(id)
        type: \(type)
        name: \(name)
        path: \(file)
        """
    }

    var isStale: Bool {
        // Check if plugin has timed updates and hasn't updated within 2x the interval
        guard updateInterval > 0,
              updateInterval < 60 * 60 * 24 * 100, // Not a "never" update plugin
              let lastUpdated
        else {
            return false
        }

        let timeSinceLastUpdate = Date().timeIntervalSince(lastUpdated)
        return timeSinceLastUpdate > (updateInterval * 2)
    }

    var prefs: PreferencesStore {
        PreferencesStore.shared
    }

    var enabled: Bool {
        !prefs.disabledPlugins.contains(id)
    }

    func makeScriptExecutable(file: String) {
        guard prefs.makePluginExecutable else { return }
        _ = try? runScript(to: "chmod", args: ["+x", "\(file.escaped())"])
    }

    func refreshPluginMetadata() {
        os_log("Refreshing plugin metadata \n%{public}@", log: Log.plugin, file)
        let url = URL(fileURLWithPath: file)
        if let script = try? String(contentsOf: url) {
            metadata = PluginMetadata.parser(script: script)
        }
        if let md = PluginMetadata.parser(fileURL: url) {
            metadata = md
        }
    }

    var cacheDirectory: URL? {
        AppShared.cacheDirectory?.appendingPathComponent(id)
    }

    var cacheDirectoryPath: String {
        cacheDirectory?.path ?? ""
    }

    var dataDirectory: URL? {
        AppShared.dataDirectory?.appendingPathComponent(id)
    }

    var dataDirectoryPath: String {
        dataDirectory?.path ?? ""
    }

    func createSupportDirs() {
        if let cacheURL = cacheDirectory {
            try? FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true, attributes: nil)
        }
        if let dataURL = dataDirectory {
            try? FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true, attributes: nil)
        }
    }

    var env: [String: String] {
        var pluginEnv = [
            Environment.Variables.swiftBarPluginPath.rawValue: file,
            Environment.Variables.osAppearance.rawValue: AppShared.isDarkTheme ? "Dark" : "Light",
            Environment.Variables.swiftBarPluginCachePath.rawValue: cacheDirectoryPath,
            Environment.Variables.swiftBarPluginDataPath.rawValue: dataDirectoryPath,
            Environment.Variables.swiftBarPluginRefreshReason.rawValue: lastRefreshReason.rawValue,
        ]
        metadata?.environment.forEach { k, v in
            pluginEnv[k] = v
        }

        for (k, v) in refreshEnv {
            pluginEnv[k] = v
        }
        refreshEnv.removeAll()
        return pluginEnv
    }
}
