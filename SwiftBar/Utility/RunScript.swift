import Foundation
import ShellOut

fileprivate let systemEnv: [String:String] = [
    "SwiftBar":"1",
    "SwiftBarVersion": (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""),
    "SwiftBarBuild": (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "")
]

@discardableResult func runScript(to command: String, env: [String:String] = [:]) throws -> String {
    let process = Process()
    process.environment = systemEnv.merging(env){ (current, _) in current }
    return try shellOut(to: command, process: process)
}
