import Combine
import Foundation
import os

/// Each invocation owns its parser. Pipe reads may split a separator anywhere,
/// and an old process must never share this buffer with its replacement.
struct StreamContentParser {
    let useTrailingSeparator: Bool
    private var pendingLine = ""
    private var block = ""

    mutating func consume(_ chunk: String) -> [String] {
        pendingLine += chunk
        var completedBlocks: [String] = []
        var changedLeadingBlock = false
        while let newline = pendingLine.firstIndex(where: { $0 == "\n" || $0 == "\r\n" }) {
            var line = String(pendingLine[..<newline])
            pendingLine.removeSubrange(...newline)
            if line.last == "\r" { line.removeLast() }
            if line == "~~~" {
                if useTrailingSeparator { completedBlocks.append(block) }
                block = ""
                changedLeadingBlock = !useTrailingSeparator
            } else {
                block += line + "\n"
                changedLeadingBlock = true
            }
        }
        if !useTrailingSeparator {
            // Hold possible separator fragments until their line is complete.
            let hasPartialText = !pendingLine.isEmpty && !"~~~".hasPrefix(pendingLine)
            if changedLeadingBlock || hasPartialText {
                completedBlocks.append(block + (hasPartialText ? pendingLine : ""))
            }
        }
        return completedBlocks
    }
}

private final class StreamInvocation {
    let process = Process()
    let stdin = Pipe()
    var parser: StreamContentParser

    init(useTrailingSeparator: Bool) {
        parser = StreamContentParser(useTrailingSeparator: useTrailingSeparator)
    }
}

class StreamablePlugin: Plugin {
    var id: PluginID
    let type: PluginType = .Streamable
    let name: String
    let file: String
    var refreshEnv: [String: String] = [:]

    private var _metadata: PluginMetadata?
    private let metadataQueue = DispatchQueue(label: "com.ameba.SwiftBar.StreamablePlugin.metadata", attributes: .concurrent)
    var metadata: PluginMetadata? {
        get { metadataQueue.sync { _metadata } }
        set {
            metadataQueue.async(flags: .barrier) { [weak self] in self?._metadata = newValue }
        }
    }

    var lastUpdated: Date?
    var lastState: PluginState
    var lastRefreshReason: PluginRefreshReason = .FirstLaunch
    var operation: Operation?
    var updateInterval = 0.0
    var contentUpdatePublisher = PassthroughSubject<String?, Never>()

    private let contentStorage = LockedValue<String?>("")
    var content: String? {
        get { contentStorage.current }
        set {
            let oldValue = contentStorage.exchange(newValue)
            guard newValue != oldValue else { return }
            lastUpdated = Date()
            contentUpdatePublisher.send(newValue)
        }
    }

    var error: Error?
    var debugInfo = PluginDebugInfo()
    let invokeQueue: OperationQueue
    let prefs = PreferencesStore.shared

    // Main owns lifecycle, parser mutations, and output application. Blocking
    // pipe reads and waitUntilExit remain on the invoke queue.
    private var currentInvocation: StreamInvocation?

    init?(fileURL: URL, invokeQueue: OperationQueue? = nil, createSupportDirectories: Bool = true) {
        let nameComponents = fileURL.lastPathComponent.components(separatedBy: ".")
        id = fileURL.lastPathComponent
        name = nameComponents.first ?? ""
        file = fileURL.path
        self.invokeQueue = invokeQueue ?? delegate.pluginManager.pluginInvokeQueue
        lastState = .Streaming
        makeScriptExecutable(file: file)
        refreshPluginMetadata()
        guard metadata?.type == .Streamable else { return nil }
        guard enabled else { return }
        if createSupportDirectories { createSupportDirs() }
        start()
    }

    func refresh(reason: PluginRefreshReason = .FirstLaunch) {
        lastRefreshReason = reason
        start()
    }

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        stopCurrentInvocation()
        guard enabled else { return }

        let invocation = StreamInvocation(useTrailingSeparator: metadata?.useTrailingStreamSeparator == true)
        currentInvocation = invocation
        lastUpdated = Date()
        lastState = .Streaming
        error = nil
        let environment = env
        let runInBash = metadata?.shouldRunInBash ?? true
        let debugOutput = prefs.streamablePluginDebugOutput
        let file = file
        let name = name

        let operation = BlockOperation { [weak self] in
            do {
                let output = try runScript(to: file, process: invocation.process,
                                           env: environment, runInBash: runInBash,
                                           streamOutput: true, stdinPipe: invocation.stdin,
                                           launchProcess: { process in
                                               // Serialize the actual launch with cancellation:
                                               // a cancelled queued run must never launch later.
                                               try DispatchQueue.main.sync {
                                                   guard self?.currentInvocation === invocation else {
                                                       throw CocoaError(.userCancelled)
                                                   }
                                                   try process.run()
                                               }
                                           }, onOutputUpdate: { chunk in
                                               DispatchQueue.main.async { [weak self] in
                                                   guard let self, self.currentInvocation === invocation,
                                                         let chunk else { return }
                                                   if debugOutput {
                                                       os_log("Streaming %{public}@: %{public}@", log: Log.plugin, name, chunk)
                                                   }
                                                   for block in invocation.parser.consume(chunk) {
                                                       self.content = block
                                                   }
                                               }
                                           })
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.currentInvocation === invocation else { return }
                    if let errorOutput = output.err, !errorOutput.isEmpty {
                        self.debugInfo.addEvent(type: .ContentUpdateError, value: errorOutput)
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.currentInvocation === invocation else { return }
                    self.error = error
                    self.lastState = .Failed
                    self.content = nil
                }
            }
        }
        self.operation = operation
        invokeQueue.addOperation(operation)
    }

    private func stopCurrentInvocation() {
        let previous = currentInvocation
        currentInvocation = nil
        operation?.cancel()
        if previous?.process.isRunning == true { previous?.process.terminate() }
    }

    func disable() {
        terminate()
        content = ""
        prefs.disabledPlugins.append(id)
    }

    func terminate() {
        dispatchPrecondition(condition: .onQueue(.main))
        stopCurrentInvocation()
        lastState = .Disabled
    }

    func enable() {
        prefs.disabledPlugins.removeAll(where: { $0 == id })
        start()
    }

    @discardableResult func invoke() -> String? {
        // A streaming invocation delivers asynchronously; never block main
        // waiting for a long-lived process to exit.
        start()
        return content
    }

    func writeStdin(_ input: String) throws {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let invocation = currentInvocation, invocation.process.isRunning else {
            throw CocoaError(.fileWriteUnknown)
        }
        try invocation.stdin.fileHandleForWriting.write(contentsOf: Data((input + "\n").utf8))
    }
}
