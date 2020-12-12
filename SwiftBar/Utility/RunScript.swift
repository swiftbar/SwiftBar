import Foundation
import ShellOut

enum EnvironmentVariables: String {
    case swiftBar = "SWIFTBAR"
    case swiftBarVersion = "SWIFTBAR_VERSION"
    case swiftBarBuild = "SWIFTBAR_BUILD"
    case swiftPluginsPath = "SWIFTBAR_PLUGINS_PATH"
    case swiftPluginPath = "SWIFTBAR_PLUGIN_PATH"
    case osVersionMajor = "OS_VERSION_MAJOR"
    case osVersionMinor = "OS_VERSION_MINOR"
    case osVersionPatch = "OS_VERSION_PATCH"
}

fileprivate let systemEnv: [EnvironmentVariables:String] = [
    .swiftBar: "1",
    .swiftBarVersion: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""),
    .swiftBarBuild: (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""),
    .swiftPluginsPath: Preferences.shared.pluginDirectoryPath ?? "",
    .osVersionMajor: String(ProcessInfo.processInfo.operatingSystemVersion.majorVersion),
    .osVersionMinor: String(ProcessInfo.processInfo.operatingSystemVersion.minorVersion),
    .osVersionPatch: String(ProcessInfo.processInfo.operatingSystemVersion.patchVersion)
]

fileprivate var systemEnvStr: [String:String] {
    Dictionary(uniqueKeysWithValues:
                systemEnv.map { key, value in (key.rawValue, value) })
}

@discardableResult func runScript(to command: String, env: [String:String] = [:]) throws -> String {
    let process = Process()
    let swiftbarEnv = systemEnvStr.merging(env){ (current, _) in current }
    process.environment = swiftbarEnv.merging(ProcessInfo.processInfo.environment){ (current, _) in current }
    return try shellOut(to: command, process: process)
}
