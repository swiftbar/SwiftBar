import Dispatch
import Foundation

enum EnvironmentVariables: String {
    case swiftBar = "SWIFTBAR"
    case swiftBarVersion = "SWIFTBAR_VERSION"
    case swiftBarBuild = "SWIFTBAR_BUILD"
    case swiftPluginsPath = "SWIFTBAR_PLUGINS_PATH"
    case swiftPluginPath = "SWIFTBAR_PLUGIN_PATH"
    case osVersionMajor = "OS_VERSION_MAJOR"
    case osVersionMinor = "OS_VERSION_MINOR"
    case osVersionPatch = "OS_VERSION_PATCH"
    case osAppearance = "OS_APPEARANCE"
}

private let systemEnv: [EnvironmentVariables: String] = [
    .swiftBar: "1",
    .swiftBarVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
    .swiftBarBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
    .swiftPluginsPath: Preferences.shared.pluginDirectoryPath ?? "",
    .osVersionMajor: String(ProcessInfo.processInfo.operatingSystemVersion.majorVersion),
    .osVersionMinor: String(ProcessInfo.processInfo.operatingSystemVersion.minorVersion),
    .osVersionPatch: String(ProcessInfo.processInfo.operatingSystemVersion.patchVersion),
]

private var systemEnvStr: [String: String] {
    Dictionary(uniqueKeysWithValues:
        systemEnv.map { key, value in (key.rawValue, value) })
}

func getEnvExportString(env: [String: String]) -> String {
    let dict = systemEnvStr.merging(env) { current, _ in current }
    return "export \(dict.map { "\($0.key)='\($0.value)'" }.joined(separator: " "))"
}

@discardableResult func runScript(to command: String,
                                  process: Process = Process(),
                                  env: [String: String] = [:],
                                  runInBash: Bool = true,
                                  onOutputUpdate: @escaping (String?) -> Void = { _ in }) throws -> String
{
    let swiftbarEnv = systemEnvStr.merging(env) { current, _ in current }
    process.environment = swiftbarEnv.merging(ProcessInfo.processInfo.environment) { current, _ in current }
    return try process.launchScript(with: command, runInBash: runInBash, onOutputUpdate: onOutputUpdate)
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
    @discardableResult func launchScript(with script: String, outputHandle: FileHandle? = nil, errorHandle: FileHandle? = nil, runInBash: Bool = true, onOutputUpdate: @escaping (String?) -> Void) throws -> String {
        if !runInBash {
            executableURL = URL(fileURLWithPath: script)
        } else {
            executableURL = URL(fileURLWithPath: "/bin/bash")
            arguments = ["-c", "-l", script]
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
                outputHandle?.write(data)
                onOutputUpdate(String(data: data, encoding: .utf8))
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handler in
            let data = handler.availableData
            outputQueue.async {
                errorData.append(data)
                errorHandle?.write(data)
            }
        }

        try! run()

        waitUntilExit()

        if let handle = outputHandle, !handle.isStandard {
            handle.closeFile()
        }

        if let handle = errorHandle, !handle.isStandard {
            handle.closeFile()
        }

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
