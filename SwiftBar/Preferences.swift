import Cocoa
import Combine

class Preferences: ObservableObject {
    static let shared = Preferences()
    enum PreferencesKeys: String {
        case PluginDirectory
        case DisabledPlugins
        case Terminal
        case HideSwiftBarIcon
        case MakePluginExecutable
        case PluginsOrder
        case PluginDeveloperMode
        case DisableBashWrapper
        case StreamablePluginDebugOutput
    }

    let disabledPluginsPublisher = PassthroughSubject<Any, Never>()

    @Published var pluginDirectoryPath: String? {
        didSet {
            Preferences.setValue(value: pluginDirectoryPath, key: .PluginDirectory)
        }
    }

    var pluginDirectoryResolvedURL: URL? {
        guard let path = pluginDirectoryPath as NSString? else { return nil }
        return URL(fileURLWithPath: path.expandingTildeInPath).resolvingSymlinksInPath()
    }

    var pluginDirectoryResolvedPath: String? {
        pluginDirectoryResolvedURL?.path
    }

    @Published var disabledPlugins: [PluginID] {
        didSet {
            let unique = Array(Set(disabledPlugins))
            Preferences.setValue(value: unique, key: .DisabledPlugins)
            disabledPluginsPublisher.send("")
        }
    }

    @Published var pluginsOrder: [PluginID] {
        didSet {
            Preferences.setValue(value: pluginsOrder, key: .PluginsOrder)
        }
    }

    @Published var terminal: ShellOptions {
        didSet {
            Preferences.setValue(value: terminal.rawValue, key: .Terminal)
        }
    }

    @Published var swiftBarIconIsHidden: Bool {
        didSet {
            Preferences.setValue(value: swiftBarIconIsHidden, key: .HideSwiftBarIcon)
            delegate.pluginManager.rebuildAllMenus()
        }
    }

    var makePluginExecutable: Bool {
        guard let out = Preferences.getValue(key: .MakePluginExecutable) as? Bool else {
            Preferences.setValue(value: true, key: .MakePluginExecutable)
            return true
        }
        return out
    }

    var pluginDeveloperMode: Bool {
        Preferences.getValue(key: .PluginDeveloperMode) as? Bool ?? false
    }

    var disableBashWrapper: Bool {
        Preferences.getValue(key: .DisableBashWrapper) as? Bool ?? false
    }

    var streamablePluginDebugOutput: Bool {
        Preferences.getValue(key: .StreamablePluginDebugOutput) as? Bool ?? false
    }

    init() {
        pluginDirectoryPath = Preferences.getValue(key: .PluginDirectory) as? String
        disabledPlugins = Preferences.getValue(key: .DisabledPlugins) as? [PluginID] ?? []
        pluginsOrder = Preferences.getValue(key: .PluginsOrder) as? [PluginID] ?? []
        terminal = .Terminal
        swiftBarIconIsHidden = Preferences.getValue(key: .HideSwiftBarIcon) as? Bool ?? false
        if let savedTerminal = Preferences.getValue(key: .Terminal) as? String,
           let shell = ShellOptions(rawValue: savedTerminal)
        {
            terminal = shell
        }
    }

    static func removeAll() {
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
    }

    private static func setValue(value: Any?, key: PreferencesKeys) {
        UserDefaults.standard.setValue(value, forKey: key.rawValue)
        UserDefaults.standard.synchronize()
    }

    private static func getValue(key: PreferencesKeys) -> Any? {
        UserDefaults.standard.value(forKey: key.rawValue)
    }
}
