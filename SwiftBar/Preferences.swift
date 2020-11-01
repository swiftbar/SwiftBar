import Combine
import Cocoa


class Preferences: ObservableObject {
    static let shared = Preferences()
    enum PreferencesKeys: String {
        case PluginDirectory
        case LaunchAtLogin
        case DisabledPlugins
    }

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
            Preferences.setValue(value: Array(Set(disabledPlugins)), key: .DisabledPlugins)
        }
    }

    init() {
        pluginDirectoryPath = Preferences.getValue(key: .PluginDirectory) as? String
        launchAtLogin = Preferences.getValue(key: .LaunchAtLogin) as? Bool ?? false
        disabledPlugins = Preferences.getValue(key: .DisabledPlugins) as? [PluginID] ?? []
    }

    private static func setValue(value: Any?, key: PreferencesKeys) {
        UserDefaults.standard.setValue(value, forKey: key.rawValue)
        UserDefaults.standard.synchronize()
    }

    private static func getValue(key: PreferencesKeys) -> Any? {
        UserDefaults.standard.value(forKey: key.rawValue)
    }
}
