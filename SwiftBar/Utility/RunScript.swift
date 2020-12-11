import Foundation
import ShellOut

fileprivate let systemEnv: [String:String] = [
    "SWIFTBAR":"1",
    "SWIFTBAR_VERSION": (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""),
    "SWIFTBAR_BUILD": (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""),
    "SWIFTBAR_PLUGINS_PATH": Preferences.shared.pluginDirectoryPath ?? "",
    "OS_VERSION_MAJOR": String(ProcessInfo.processInfo.operatingSystemVersion.majorVersion),
    "OS_VERSION_MINOR": String(ProcessInfo.processInfo.operatingSystemVersion.minorVersion),
    "OS_VERSION_PATCH": String(ProcessInfo.processInfo.operatingSystemVersion.patchVersion)
]

@discardableResult func runScript(to command: String, env: [String:String] = [:]) throws -> String {
    let process = Process()
    process.environment = systemEnv.merging(env){ (current, _) in current }
    return try shellOut(to: command, process: process)
}
