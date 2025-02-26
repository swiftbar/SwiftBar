import Dispatch
import Foundation
import os

let sharedEnv = Environment.shared

func getEnvExportString(env: [String: String]) -> String {
    let dict = sharedEnv.systemEnvStr.merging(env) { current, _ in current }
    return "export \(dict.map { "\($0.key)='\($0.value)'" }.joined(separator: " "))"
}

@discardableResult func runScript(to command: String,
                                  args: [String] = [],
                                  process: Process = Process(),
                                  env: [String: String] = [:],
                                  runInBash: Bool = true,
                                  streamOutput: Bool = false,
                                  onOutputUpdate: @escaping (String?) -> Void = { _ in }) throws -> (out: String, err: String?)
{
    let swiftbarEnv = sharedEnv.systemEnvStr.merging(env) { current, _ in current }
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
    @discardableResult func launchScript(with script: String, args: [String], runInBash: Bool = true, streamOutput: Bool, onOutputUpdate: @escaping (String?) -> Void) throws -> (out: String, err: String?) {
        if !runInBash {
            executableURL = URL(fileURLWithPath: script)
            arguments = args
        } else {
            let shell = delegate.prefs.shell
            executableURL = URL(fileURLWithPath: shell.path)
            // When executing in a shell, we need to properly escape arguments to handle special characters
            let escapedArgs = args.map { $0.quoteIfNeeded() }
            arguments = ["-c", "\(script.escaped()) \(escapedArgs.joined(separator: " "))"]
            if shell.path.hasSuffix("bash") || shell.path.hasSuffix("zsh") {
                arguments?.insert("-l", at: 1)
            }
        }

        guard let executableURL = executableURL, FileManager.default.fileExists(atPath: executableURL.path) else {
            return (out: "", err: nil)
        }

        var outputData = Data()
        var errorData = Data()

        let outputPipe = Pipe()
        standardOutput = outputPipe

        let errorPipe = Pipe()
        standardError = errorPipe

        guard streamOutput else { // horrible hack, code below this guard doesn't work reliably and I can't fugire out why.
            do {
                try run()
            } catch {
                os_log("Failed to launch plugin", log: Log.plugin, type: .error)
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                throw ShellOutError(terminationStatus: terminationStatus, errorData: errorData, outputData: data)
            }

            outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            waitUntilExit()

            if terminationStatus != 0 {
                throw ShellOutError(
                    terminationStatus: terminationStatus,
                    errorData: errorData,
                    outputData: outputData
                )
            }
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let err = String(data: errorData, encoding: .utf8)
            return (out: output, err: err)
        }

        let outputQueue = DispatchQueue(label: "bash-output-queue")

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
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let err = String(data: errorData, encoding: .utf8)
            return (out: output, err: err)
//            return outputData.shellOutput()
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
