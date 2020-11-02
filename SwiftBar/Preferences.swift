import Combine
import Cocoa


class Preferences: ObservableObject {
    static let shared = Preferences()
    enum PreferencesKeys: String {
        case PluginDirectory
        case LaunchAtLogin
        case DisabledPlugins
        case Terminal
    }
    let disabledPluginsPublisher = PassthroughSubject<Any, Never>()

    @Published var pluginDirectoryPath: String? {
        didSet {
            Preferences.setValue(value: pluginDirectoryPath, key: .PluginDirectory)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            Preferences.setValue(value: launchAtLogin, key: .LaunchAtLogin)
        }
    }

    @Published var disabledPlugins: [PluginID] {
        didSet {
            let unique = Array(Set(disabledPlugins))
            Preferences.setValue(value: unique, key: .DisabledPlugins)
            disabledPluginsPublisher.send("")
        }
    }

    @Published var terminal: ShellOptions {
        didSet {
            Preferences.setValue(value: terminal.rawValue, key: .Terminal)
        }
    }

    init() {
//        Preferences.removeAll()
        pluginDirectoryPath = Preferences.getValue(key: .PluginDirectory) as? String
        launchAtLogin = Preferences.getValue(key: .LaunchAtLogin) as? Bool ?? false
        disabledPlugins = Preferences.getValue(key: .DisabledPlugins) as? [PluginID] ?? []
        terminal = .Terminal
        if let savedTerminal = Preferences.getValue(key: .Terminal) as? String,
           let shell = ShellOptions(rawValue: savedTerminal) {
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
