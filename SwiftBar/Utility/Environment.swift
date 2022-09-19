import Foundation

class Environment {
    static let shared = Environment()

    enum Variables: String {
        case swiftBar = "SWIFTBAR"
        case swiftBarVersion = "SWIFTBAR_VERSION"
        case swiftBarBuild = "SWIFTBAR_BUILD"
        case swiftBarPluginsPath = "SWIFTBAR_PLUGINS_PATH"
        case swiftBarPluginPath = "SWIFTBAR_PLUGIN_PATH"
        case swiftBarPluginCachePath = "SWIFTBAR_PLUGIN_CACHE_PATH"
        case swiftBarPluginDataPath = "SWIFTBAR_PLUGIN_DATA_PATH"
        case swiftBarLaunchTime = "SWIFTBAR_LAUNCH_TIME"
        case osVersionMajor = "OS_VERSION_MAJOR"
        case osVersionMinor = "OS_VERSION_MINOR"
        case osVersionPatch = "OS_VERSION_PATCH"
        case osAppearance = "OS_APPEARANCE"
        case osLastSleepTime = "OS_LAST_SLEEP_TIME"
        case osLastWakeTime = "OS_LAST_WAKE_TIME"
    }

    private var dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    var userLoginShell = "/bin/zsh"

    private var systemEnv: [Variables: String] = [
        .swiftBar: "1",
        .swiftBarVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
        .swiftBarBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
        .swiftBarPluginsPath: PreferencesStore.shared.pluginDirectoryPath ?? "",
        .osVersionMajor: String(ProcessInfo.processInfo.operatingSystemVersion.majorVersion),
        .osVersionMinor: String(ProcessInfo.processInfo.operatingSystemVersion.minorVersion),
        .osVersionPatch: String(ProcessInfo.processInfo.operatingSystemVersion.patchVersion),
    ]

    var systemEnvStr: [String: String] {
        Dictionary(uniqueKeysWithValues:
            systemEnv.map { key, value in (key.rawValue, value) })
    }

    init() {
        systemEnv[.swiftBarLaunchTime] = dateFormatter.string(from: NSDate.now)
    }

    func updateSleepTime(date: Date) {
        systemEnv[.osLastSleepTime] = dateFormatter.string(from: date)
    }

    func updateWakeTime(date: Date) {
        systemEnv[.osLastWakeTime] = dateFormatter.string(from: date)
    }
}
