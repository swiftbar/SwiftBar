import Dispatch
import Foundation
import os

let sharedEnv = Environment.shared

struct UTF8ChunkDecoder {
    private var pendingBytes: [UInt8] = []

    mutating func decode(_ data: Data) -> String {
        pendingBytes.append(contentsOf: data)

        let completeBytesEnd = incompleteSequenceStart() ?? pendingBytes.endIndex
        let decoded = String(decoding: pendingBytes[..<completeBytesEnd], as: UTF8.self)
        pendingBytes = Array(pendingBytes[completeBytesEnd...])
        return decoded
    }

    mutating func finish() -> String {
        defer { pendingBytes.removeAll() }
        return String(decoding: pendingBytes, as: UTF8.self)
    }

    private func incompleteSequenceStart() -> Int? {
        guard !pendingBytes.isEmpty else { return nil }

        var sequenceStart = pendingBytes.index(before: pendingBytes.endIndex)
        while sequenceStart > pendingBytes.startIndex,
              pendingBytes[sequenceStart] & 0b1100_0000 == 0b1000_0000
        {
            sequenceStart = pendingBytes.index(before: sequenceStart)
        }

        let expectedLength: Int
        switch pendingBytes[sequenceStart] {
        case 0b1100_0010 ... 0b1101_1111:
            expectedLength = 2
        case 0b1110_0000 ... 0b1110_1111:
            expectedLength = 3
        case 0b1111_0000 ... 0b1111_0100:
            expectedLength = 4
        default:
            return nil
        }

        let actualLength = pendingBytes.distance(from: sequenceStart, to: pendingBytes.endIndex)
        guard actualLength < expectedLength else { return nil }
        guard pendingBytes[pendingBytes.index(after: sequenceStart)...]
            .allSatisfy({ $0 & 0b1100_0000 == 0b1000_0000 })
        else {
            return nil
        }
        return sequenceStart
    }
}

func getEnvExportString(env: [String: String]) -> String {
    let dict = sharedEnv.systemEnvStr.merging(env) { current, _ in current }
    let shell = sharedEnv.userLoginShell.lowercased()

    // Check for tcsh/csh
    if shell.contains("tcsh") || shell.contains("csh") {
        // tcsh/csh uses: setenv VAR value
        return dict.map { "setenv \($0.key) \($0.value.quoteIfNeeded())" }.joined(separator: "; ")
    }

    // Check for fish
    if shell.contains("fish") {
        // fish uses: set -x VAR value
        return dict.map { "set -x \($0.key) \($0.value.quoteIfNeeded())" }.joined(separator: "; ")
    }

    // Default to bash/zsh/sh syntax: export VAR=value
    return "export \(dict.map { "\($0.key)=\($0.value.quoteIfNeeded())" }.joined(separator: " "))"
}

func buildTerminalCommand(script: String, args: [String] = [], env: [String: String] = [:]) -> String {
    let command = ([script.escaped()] + args.map { $0.quoteIfNeeded() }).joined(separator: " ")
    return "\(getEnvExportString(env: env)); \(command)"
}

/// Launches a script and returns its stdout/stderr output.
///
/// - Parameter workingDirectory: If non-nil, sets `Process.currentDirectoryURL`
///   so the script runs with this as its working directory (used by packaged plugins).
@discardableResult func runScript(to command: String,
                                  args: [String] = [],
                                  process: Process = Process(),
                                  env: [String: String] = [:],
                                  workingDirectory: String? = nil,
                                  runInBash: Bool = true,
                                  streamOutput: Bool = false,
                                  stdinPipe: Pipe? = nil,
                                  onOutputUpdate: @escaping (String?) -> Void = { _ in }) throws -> (out: String, err: String?)
{
    let swiftbarEnv = sharedEnv.systemEnvStr.merging(env) { _, new in new }
    process.environment = swiftbarEnv.merging(ProcessInfo.processInfo.environment) { current, _ in current }
    if let workingDirectory {
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
    }
    return try process.launchScript(with: command, args: args, runInBash: runInBash, streamOutput: streamOutput, stdinPipe: stdinPipe, onOutputUpdate: onOutputUpdate)
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
    @discardableResult func launchScript(with script: String, args: [String], runInBash: Bool = true, streamOutput: Bool, stdinPipe: Pipe? = nil, onOutputUpdate: @escaping (String?) -> Void) throws -> (out: String, err: String?) {
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

        guard let executableURL, FileManager.default.fileExists(atPath: executableURL.path) else {
            return (out: "", err: nil)
        }

        var outputData = Data()
        var errorData = Data()

        let outputPipe = Pipe()
        standardOutput = outputPipe

        let errorPipe = Pipe()
        standardError = errorPipe

        // Set up stdin pipe if provided
        if let stdinPipe = stdinPipe {
            standardInput = stdinPipe
        }

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
        var outputDecoder = UTF8ChunkDecoder()

        outputPipe.fileHandleForReading.readabilityHandler = { handler in
            let data = handler.availableData
            outputQueue.async {
                outputData.append(data)
                let decoded = data.isEmpty ? outputDecoder.finish() : outputDecoder.decode(data)
                if !decoded.isEmpty {
                    onOutputUpdate(decoded)
                }
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
