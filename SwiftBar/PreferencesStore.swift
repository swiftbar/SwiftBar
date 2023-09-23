import Cocoa
import Combine

enum TerminalOptions: String, CaseIterable {
    case Terminal
    case iTerm
}

enum ShellOptions: String, CaseIterable {
    case Bash = "bash"
    case Zsh = "zsh"
    case Default = "default"

    var path: String {
        switch self {
        case .Bash:
            return "/bin/bash"
        case .Zsh:
            return "/bin/zsh"
        case .Default:
            return Environment.shared.userLoginShell
        }
    }
}

class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()
    enum PreferencesKeys: String {
        case PluginDirectory
        case ShortcutsFolder
        case DisabledPlugins
        case Terminal
        case Shell
        case HideSwiftBarIcon
        case MakePluginExecutable
        case PluginDeveloperMode
        case DisableBashWrapper
        case StreamablePluginDebugOutput
        case PluginDebugMode
        case StealthMode
        case IncludeBetaUpdates
        case DimOnManualRefresh
        case CollectCrashReports
        case DebugLoggingEnabled
        case ShortcutPlugins
        case PluginRepositoryURL
        case PluginSourceCodeURL
    }

    let disabledPluginsPublisher = PassthroughSubject<Any, Never>()

    @Published var pluginDirectoryPath: String? {
        didSet {
            PreferencesStore.setValue(value: pluginDirectoryPath, key: .PluginDirectory)
        }
    }

    @Published var shortcutsFolder: String {
        didSet {
            PreferencesStore.setValue(value: shortcutsFolder, key: .ShortcutsFolder)
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
            PreferencesStore.setValue(value: unique, key: .DisabledPlugins)
            disabledPluginsPublisher.send("")
        }
    }

    @Published var terminal: TerminalOptions {
        didSet {
            PreferencesStore.setValue(value: terminal.rawValue, key: .Terminal)
        }
    }

    @Published var shell: ShellOptions {
        didSet {
            PreferencesStore.setValue(value: shell.rawValue, key: .Shell)
        }
    }

    @Published var swiftBarIconIsHidden: Bool {
        didSet {
            PreferencesStore.setValue(value: swiftBarIconIsHidden, key: .HideSwiftBarIcon)
            delegate.pluginManager.rebuildAllMenus()
        }
    }

    @Published var includeBetaUpdates: Bool {
        didSet {
            PreferencesStore.setValue(value: includeBetaUpdates, key: .IncludeBetaUpdates)
        }
    }

    @Published var collectCrashReports: Bool {
        didSet {
            PreferencesStore.setValue(value: collectCrashReports, key: .CollectCrashReports)
        }
    }

    @Published var dimOnManualRefresh: Bool {
        didSet {
            PreferencesStore.setValue(value: dimOnManualRefresh, key: .DimOnManualRefresh)
        }
    }

    @Published var shortcutsPlugins: [PersistentShortcutPlugin] {
        didSet {
            PreferencesStore.setValue(value: try? PropertyListEncoder().encode(shortcutsPlugins), key: .ShortcutPlugins)
        }
    }

    var makePluginExecutable: Bool {
        guard let out = PreferencesStore.getValue(key: .MakePluginExecutable) as? Bool else {
            PreferencesStore.setValue(value: true, key: .MakePluginExecutable)
            return true
        }
        return out
    }

    var pluginDeveloperMode: Bool {
        PreferencesStore.getValue(key: .PluginDeveloperMode) as? Bool ?? false
    }

    var pluginDebugMode: Bool {
        PreferencesStore.getValue(key: .PluginDebugMode) as? Bool ?? false
    }

    var disableBashWrapper: Bool {
        PreferencesStore.getValue(key: .DisableBashWrapper) as? Bool ?? false
    }

    var streamablePluginDebugOutput: Bool {
        PreferencesStore.getValue(key: .StreamablePluginDebugOutput) as? Bool ?? false
    }

    @Published var stealthMode: Bool {
        didSet {
            PreferencesStore.setValue(value: stealthMode, key: .StealthMode)
        }
    }

    var debugLoggingEnabled: Bool {
        PreferencesStore.getValue(key: .DebugLoggingEnabled) as? Bool ?? false
    }

    var pluginRepositoryURL: URL {
        guard let str = PreferencesStore.getValue(key: .PluginRepositoryURL) as? String,
              let url = URL(string: str)
        else {
            return URL(string: "https://xbarapp.com/docs/plugins/")!
        }
        return url
    }

    var pluginSourceCodeURL: URL {
        guard let str = PreferencesStore.getValue(key: .PluginSourceCodeURL) as? String,
              let url = URL(string: str)
        else {
            return URL(string: "https://github.com/matryer/xbar-plugins/blob/master/")!
        }
        return url
    }

    init() {
        pluginDirectoryPath = PreferencesStore.getValue(key: .PluginDirectory) as? String
        shortcutsFolder = PreferencesStore.getValue(key: .ShortcutsFolder) as? String ?? ""
        disabledPlugins = PreferencesStore.getValue(key: .DisabledPlugins) as? [PluginID] ?? []
        terminal = .Terminal
        shell = .Bash
        swiftBarIconIsHidden = PreferencesStore.getValue(key: .HideSwiftBarIcon) as? Bool ?? false
        includeBetaUpdates = PreferencesStore.getValue(key: .IncludeBetaUpdates) as? Bool ?? false
        collectCrashReports = PreferencesStore.getValue(key: .CollectCrashReports) as? Bool ?? true
        dimOnManualRefresh = PreferencesStore.getValue(key: .DimOnManualRefresh) as? Bool ?? true
        stealthMode = PreferencesStore.getValue(key: .StealthMode) as? Bool ?? false
        shortcutsPlugins = {
            guard let data = PreferencesStore.getValue(key: .ShortcutPlugins) as? Data,
                  let plugins = try? PropertyListDecoder().decode([PersistentShortcutPlugin].self, from: data) else { return [] }
            return plugins
        }()
        if let savedTerminal = PreferencesStore.getValue(key: .Terminal) as? String,
           let value = TerminalOptions(rawValue: savedTerminal)
        {
            terminal = value
        }
        if let savedShell = PreferencesStore.getValue(key: .Shell) as? String,
           let value = ShellOptions(rawValue: savedShell)
        {
            shell = value
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
