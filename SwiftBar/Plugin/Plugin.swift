import Combine
import Foundation
import os

enum PluginType: String {
    case Executable
    case Streamable
}

enum PluginState {
    case Loading
    case Streaming
    case Success
    case Failed
    case Disabled
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
    var content: String? { get set }
    var error: ShellOutError? { get set }
    var debugInfo: PluginDebugInfo { get set }
    func refresh()
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
        ]
        metadata?.environment.forEach { k, v in
            pluginEnv[k] = v
        }
        return pluginEnv
    }
}
