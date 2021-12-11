import Dispatch
import Foundation
import os

enum EnvironmentVariables: String {
    case swiftBar = "SWIFTBAR"
    case swiftBarVersion = "SWIFTBAR_VERSION"
    case swiftBarBuild = "SWIFTBAR_BUILD"
    case swiftBarPluginsPath = "SWIFTBAR_PLUGINS_PATH"
    case swiftBarPluginPath = "SWIFTBAR_PLUGIN_PATH"
    case swiftBarPluginCachePath = "SWIFTBAR_PLUGIN_CACHE_PATH"
    case swiftBarPluginDataPath = "SWIFTBAR_PLUGIN_DATA_PATH"
    case osVersionMajor = "OS_VERSION_MAJOR"
    case osVersionMinor = "OS_VERSION_MINOR"
    case osVersionPatch = "OS_VERSION_PATCH"
    case osAppearance = "OS_APPEARANCE"
}

private let systemEnv: [EnvironmentVariables: String] = [
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

func getEnvExportString(env: [String: String]) -> String {
    let dict = systemEnvStr.merging(env) { current, _ in current }
    return "export \(dict.map { "\($0.key)='\($0.value)'" }.joined(separator: " "))"
}

@discardableResult func runScript(to command: String,
                                  args: [String] = [],
                                  process: Process = Process(),
                                  env: [String: String] = [:],
                                  runInBash: Bool = true,
                                  streamOutput: Bool = false,
                                  onOutputUpdate: @escaping (String?) -> Void = { _ in }) throws -> String
{
    let swiftbarEnv = systemEnvStr.merging(env) { current, _ in current }
    process.environment = swiftbarEnv.merging(ProcessInfo.processInfo.environment) { current, _ in current }
    return try process.launchScript(with: command, args: args, runInBash: runInBash, streamOutput: streamOutput, onOutputUpdate: onOutputUpdate)
}

// Code below is adopted from https://github.com/JohnSundell/ShellOut

/// Error type thrown by the `shellOut()` function, in case the given command failed
public struct ShellOutError: Swift.Error {
    /// The termination status of the command that was run
    public let terminationStatus: Int32
    /// The error message as a UTF8 string, as returned through `STDERR`
    public var message: String { errorData.shellOutput() }
    /// The raw error buffer data, as returned through `STDERR`
    public let errorData: Data
    /// The raw output buffer data, as retuned through `STDOUT`
    public let outputData: Data
    /// The output of the command as a UTF8 string, as returned through `STDOUT`
    public var output: String { outputData.shellOutput() }
}

// MARK: - Private

private extension Process {
    @discardableResult func launchScript(with script: String, args: [String], runInBash: Bool = true, streamOutput: Bool, onOutputUpdate: @escaping (String?) -> Void) throws -> String {
        if !runInBash {
            executableURL = URL(fileURLWithPath: script)
            arguments = args
        } else {
            executableURL = URL(fileURLWithPath: delegate.prefs.shell.path)
            arguments = ["-c", "-l", "\(script.escaped()) \(args.joined(separator: " "))"]
        }
        
        guard let executableURL = executableURL, FileManager.default.fileExists(atPath: executableURL.path) else {
            return ""
        }
        
        guard streamOutput else { //horrible hack, code below this guard doesn't work reliably and I can't fugire out why.
            let pipe = Pipe()
            standardOutput = pipe
            standardError = pipe
            launch()
            waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output: String = String(data: data, encoding: .utf8) ?? "HUI: FUCK"
            return output
        }
        
        let outputQueue = DispatchQueue(label: "bash-output-queue")
        
        var outputData = Data()
        var errorData = Data()
        
        let outputPipe = Pipe()
        standardOutput = outputPipe
        
        let errorPipe = Pipe()
        standardError = errorPipe
        
        outputPipe.fileHandleForReading.readabilityHandler = { handler in
            let data = handler.availableData
            outputQueue.async {
                outputData.append(data)
                onOutputUpdate(String(data: data, encoding: .utf8))
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { handler in
            let data = handler.availableData
            outputQueue.async {
                errorData.append(data)
            }
        }
        
        do {
            try run()
        } catch {
            os_log("Failed to launch plugin", log: Log.plugin, type: .error)
            throw ShellOutError(terminationStatus: terminationStatus, errorData: errorData, outputData: outputData)
        }
        
        waitUntilExit()
        
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        
        return try outputQueue.sync {
            if terminationStatus != 0 {
                throw ShellOutError(
                    terminationStatus: terminationStatus,
                    errorData: errorData,
                    outputData: outputData
                )
            }
            
            return outputData.shellOutput()
        }
    }
}

private extension FileHandle {
    var isStandard: Bool {
        self === FileHandle.standardOutput ||
        self === FileHandle.standardError ||
        self === FileHandle.standardInput
    }
}

private extension Data {
    func shellOutput() -> String {
        guard let output = String(data: self, encoding: .utf8) else {
            return ""
        }
        
        guard !output.hasSuffix("\n") else {
            let endIndex = output.index(before: output.endIndex)
            return String(output[..<endIndex])
        }
        
        return output
    }
}
