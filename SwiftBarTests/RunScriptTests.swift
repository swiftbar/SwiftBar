import Foundation
import Intents
import Testing

@testable import SwiftBar

private final class OutputRecorder {
    private let lock = NSLock()
    private var values: [String?] = []
    private var writeError: String?

    func append(_ value: String?) -> Bool {
        lock.lock()
        values.append(value)
        let isFirstValue = values.count == 1
        lock.unlock()
        return isFirstValue
    }

    func recordWriteError(_ error: Error) {
        lock.lock()
        writeError = error.localizedDescription
        lock.unlock()
    }

    func recordedValues() -> [String?] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func recordedWriteError() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return writeError
    }
}

struct RunScriptTests {
    @Test func longTerminalCommandsKeepAllBytesAndCleanUpTheirPrivateFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("terminal space ' quote \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let text = String(repeating: "🌍 quotes ' and $ literal ", count: 150)
        let command = "printf '%s\\n' \(text.quoteIfNeeded()); printf END; false"
        let prepared = try prepareTerminalCommand(command, in: root)
        let directory = try #require(prepared.temporaryDirectory)
        #expect(prepared.command.utf8.count < 900)
        #expect(try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int == 0o700)
        #expect(try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("command").path)[.posixPermissions] as? Int == 0o600)

        for shell in ["/bin/bash", "/bin/zsh"] {
            let invocation = shell == "/bin/bash" ? prepared : try prepareTerminalCommand(command, in: root)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = ["-c", invocation.command]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            #expect(String(decoding: output, as: UTF8.self) == text + "\nEND")
            #expect(process.terminationStatus == 1)
            #expect(!FileManager.default.fileExists(atPath: try #require(invocation.temporaryDirectory).path))
        }
    }

    @Test func shortTerminalCommandsNeedNoTemporaryFile() throws {
        let prepared = try prepareTerminalCommand("echo short")
        #expect(prepared.command == "echo short")
        #expect(prepared.temporaryDirectory == nil)
    }

    @Test func rejectedLaunchDoesNotReadAnUnlaunchedProcessStatus() throws {
        for streaming in [false, true] {
            do {
                _ = try runScript(to: "/usr/bin/true", runInBash: false, streamOutput: streaming,
                                  launchProcess: { _ in throw CocoaError(.userCancelled) })
                Issue.record("Rejected launch unexpectedly succeeded")
            } catch let error as ShellOutError {
                #expect(error.terminationStatus == -1)
                #expect(!error.message.isEmpty)
            }
        }
    }
    @Test func utf8ChunkDecoder_reassemblesScalarsSplitAtEveryByte() {
        let expected = "A¢●🌍Z"
        let bytes = Array(expected.utf8)

        for splitIndex in 0 ... bytes.count {
            var decoder = UTF8ChunkDecoder()
            let first = decoder.decode(Data(bytes[..<splitIndex]))
            let second = decoder.decode(Data(bytes[splitIndex...]))

            #expect(first + second + decoder.finish() == expected)
        }

        var byteAtATimeDecoder = UTF8ChunkDecoder()
        let byteAtATime = bytes
            .map { byteAtATimeDecoder.decode(Data([$0])) }
            .joined()
        #expect(byteAtATime + byteAtATimeDecoder.finish() == expected)
    }

    @Test func utf8ChunkDecoder_replacesIncompleteScalarAtEndOfStream() {
        var decoder = UTF8ChunkDecoder()

        #expect(decoder.decode(Data([0xE2, 0x97])).isEmpty)
        #expect(decoder.finish() == "�")
        #expect(decoder.finish().isEmpty)
    }

    @Test func runScript_streamOutputPreservesUTF8SplitAcrossPipeReads() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let scriptURL = tempDirectory.appendingPathComponent("split-utf8.sh")
        let script = """
        #!/bin/sh
        printf 'prefix \\342\\227'
        read _
        printf '\\217 suffix\\n'
        """
        try Data(script.utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let recorder = OutputRecorder()
        let stdinPipe = Pipe()
        let result = try runScript(
            to: scriptURL.path,
            runInBash: false,
            streamOutput: true,
            stdinPipe: stdinPipe,
            onOutputUpdate: { value in
                if recorder.append(value) {
                    do {
                        try stdinPipe.fileHandleForWriting.write(contentsOf: Data("\n".utf8))
                    } catch {
                        recorder.recordWriteError(error)
                    }
                }
            }
        )
        let updates = recorder.recordedValues()

        #expect(recorder.recordedWriteError() == nil)
        #expect(updates.allSatisfy { $0 != nil })
        #expect(updates.compactMap { $0 }.joined() == "prefix ● suffix\n")
        #expect(result.out == "prefix ● suffix\n")
    }
}

struct StreamContentParserTests {
    @Test func leadingSeparatorResetsTheMenuEvenWhenNextContentArrivesLater() {
        let separator = "~~~\n"
        for split in 0...separator.count {
            var parser = StreamContentParser(useTrailingSeparator: false)
            #expect(parser.consume("hello\n") == ["hello\n"])
            let boundary = separator.index(separator.startIndex, offsetBy: split)
            let resets = parser.consume(String(separator[..<boundary])) + parser.consume(String(separator[boundary...]))
            #expect(resets.last == "", "Separator split at \(split) must clear prior content")
        }
    }

    @Test func trailingFramesSurviveEveryChunkBoundary() {
        let text = "First 🌍\n---\nBody\n~~~\nSecond\n~~~\n"
        let expected = ["First 🌍\n---\nBody\n", "Second\n"]
        for split in 0...text.count {
            let boundary = text.index(text.startIndex, offsetBy: split)
            var parser = StreamContentParser(useTrailingSeparator: true)
            let frames = parser.consume(String(text[..<boundary])) + parser.consume(String(text[boundary...]))
            #expect(frames == expected, "Split at character \(split)")
        }
        var parser = StreamContentParser(useTrailingSeparator: true)
        #expect(text.flatMap { parser.consume(String($0)) } == expected)
    }

    @Test func leadingFramesPreservePartialLinesAndSplitSeparators() {
        var parser = StreamContentParser(useTrailingSeparator: false)
        #expect(parser.consume("first") == ["first"])
        #expect(parser.consume(" line\n~") == ["first line\n"])
        #expect(parser.consume("~").isEmpty)
        #expect(parser.consume("~\nsec") == ["sec"])
        #expect(parser.consume("ond\n") == ["second\n"])
        #expect(parser.consume("text ~~~ inside a row\n") == ["second\ntext ~~~ inside a row\n"])
    }

    @Test func trailingModeDoesNotPublishAnIncompleteFrame() {
        var parser = StreamContentParser(useTrailingSeparator: true)
        #expect(parser.consume("partial\n~~").isEmpty)
        #expect(parser.consume("~").isEmpty)
        #expect(parser.consume("\r\n") == ["partial\n"])
        #expect(parser.consume("next\n~~~\n") == ["next\n"])
    }
}

@MainActor
struct StreamableLifecycleTests {
    private func makeScript(_ body: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("lifecycle-\(UUID().uuidString).sh")
        let script = """
        #!/bin/sh
        # <swiftbar.type>Streamable</swiftbar.type>
        # <swiftbar.runInBash>false</swiftbar.runInBash>
        # <swiftbar.useTrailingStreamSeparator>true</swiftbar.useTrailingStreamSeparator>
        \(body)
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func waitUntil(_ condition: () -> Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    @Test func shortcutHandlersAcceptBackgroundCallsForStreamingPlugins() async throws {
        let url = try makeScript("printf 'ready\\n~~~\\n'; while IFS= read -r line; do :; done")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let plugin = try #require(StreamablePlugin(fileURL: url, createSupportDirectories: false))
        // System reports inspect the manager's directory on plugin changes.
        // Keep this test away from the user's configured (possibly remote) folder.
        let previousManager = delegate.pluginManager
        let manager = TestDirectoryPluginManager(pluginDirectoryURL: url.deletingLastPathComponent())
        delegate.pluginManager = manager
        manager.plugins.append(plugin)
        defer {
            plugin.terminate()
            manager.plugins.removeAll { $0 === plugin }
            PreferencesStore.shared.disabledPlugins.removeAll { $0 == plugin.id }
            delegate.pluginManager = previousManager
        }
        let object = SKPlugin(identifier: plugin.id, display: plugin.name)
        let disable = DisablePluginIntent()
        disable.plugin = object
        let disabled: Bool = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                DisablePluginIntentHandler().handle(intent: disable) { response in
                    continuation.resume(returning: Thread.isMainThread && response.code == .success)
                }
            }
        }
        #expect(disabled)
        #expect(plugin.lastState == .Disabled)
        let enable = EnablePluginIntent()
        enable.plugin = object
        let enabled: Bool = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                EnablePluginIntentHandler().handle(intent: enable) { response in
                    continuation.resume(returning: Thread.isMainThread && response.code == .success)
                }
            }
        }
        #expect(enabled)
        #expect(plugin.lastState == .Streaming)
        let reload = ReloadPluginIntent()
        reload.plugin = object
        let reloaded: Bool = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                ReloadPluginIntentHandler().handle(intent: reload) { response in
                    continuation.resume(returning: Thread.isMainThread && response.code == .success)
                }
            }
        }
        #expect(reloaded)
        let listed: Bool = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                GetPluginsIntentHandler().handle(intent: GetPluginsIntent()) { response in
                    continuation.resume(returning: Thread.isMainThread && response.plugins?.contains { $0.identifier == plugin.id } == true)
                }
            }
        }
        #expect(listed)
    }

    @Test func cancelledQueuedInvocationsNeverStart() async throws {
        let url = try makeScript("touch \"$0.started\"")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let queue = OperationQueue()
        queue.isSuspended = true
        let plugin = try #require(StreamablePlugin(fileURL: url, invokeQueue: queue, createSupportDirectories: false))
        for _ in 0..<20 { plugin.refresh(reason: .URLScheme) }
        plugin.terminate()
        queue.isSuspended = false
        #expect(try await waitUntil { queue.operationCount == 0 })
        #expect(!FileManager.default.fileExists(atPath: url.path + ".started"))
        #expect(plugin.lastState == .Disabled)
    }

    @Test func restartedStreamsIgnoreLateOutputAndStoppedStreamsStayStopped() async throws {
        let url = try makeScript("""
        trap '' TERM
        i=0
        while [ "$i" -lt 30 ]; do
          printf '%s:%s\\n~~~\\n' "$$" "$i"
          i=$((i + 1))
          sleep 0.025
        done
        """)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let queue = OperationQueue()
        let plugin = try #require(StreamablePlugin(fileURL: url, invokeQueue: queue, createSupportDirectories: false))
        defer { plugin.terminate() }
        #expect(try await waitUntil { plugin.content?.contains(":") == true })
        let originalPID = try #require(plugin.content?.split(separator: ":").first.map(String.init))
        plugin.refresh(reason: .URLScheme)
        #expect(try await waitUntil {
            plugin.content?.split(separator: ":").first.map(String.init) != originalPID
        })
        let replacementPID = try #require(plugin.content?.split(separator: ":").first.map(String.init))
        for _ in 0..<15 {
            try await Task.sleep(for: .milliseconds(20))
            #expect(plugin.content?.hasPrefix(replacementPID + ":") == true)
        }
        plugin.terminate()
        let stoppedContent = plugin.content
        #expect(try await waitUntil { queue.operationCount == 0 })
        #expect(plugin.content == stoppedContent)
        #expect(plugin.lastState == .Disabled)
        #expect(throws: CocoaError.self) { try plugin.writeStdin("after stop") }
    }

    @Test func stdinTargetsTheActiveProcess() async throws {
        let url = try makeScript("""
        printf 'ready\\n~~~\\n'
        while IFS= read -r line; do
          printf '%s\\n~~~\\n' "$line"
        done
        """)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let plugin = try #require(StreamablePlugin(fileURL: url, createSupportDirectories: false))
        defer { plugin.terminate() }
        #expect(try await waitUntil { plugin.content == "ready\n" })
        try plugin.writeStdin("updated 🌍")
        #expect(try await waitUntil { plugin.content == "updated 🌍\n" })
    }
}

@MainActor
struct RegularPluginLifecycleTests {
    private func makePlugin(root: URL, packaged: Bool, interval: String = "1h", body: String) throws -> (any TimerArmingPlugin, URL) {
        let directory = packaged ? root.appendingPathComponent("lifecycle.swiftbar") : root
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent(packaged ? "plugin.\(interval).sh" : "regular.\(interval).sh")
        try ("#!/bin/sh\n# <swiftbar.runInBash>false</swiftbar.runInBash>\n" + body)
            .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        if packaged {
            return (try #require(PackagedPlugin(packageDirectory: directory, createSupportDirectories: false)), script)
        }
        return (ExecutablePlugin(fileURL: script, createSupportDirectories: false), script)
    }

    @Test(arguments: [false, true]) func cancelledOldFailureCannotReplaceNewerSuccessState(packaged: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let (plugin, script) = try makePlugin(root: root, packaged: packaged, body: """
        if [ "$MARKER" = older ]; then
          touch "$0.old-started"
          sleep 0.4
          printf 'older failed\\n' >&2
          exit 1
        fi
        printf '%s\\n' "${MARKER:-initial}"
        """)
        defer { plugin.operation?.cancel(); plugin.terminate() }
        try await waitForPluginOperation(plugin.operation)
        plugin.refreshEnv = ["MARKER": "older"]
        plugin.refresh(reason: .URLScheme)
        let oldOperation = try #require(plugin.operation)
        try await waitForPluginCondition { FileManager.default.fileExists(atPath: script.path + ".old-started") }
        plugin.refreshEnv = ["MARKER": "newer"]
        plugin.refresh(reason: .URLScheme)
        try await waitForPluginOperation(plugin.operation)
        #expect(plugin.content == "newer\n")
        #expect(plugin.lastState == .Success)
        let newestUpdate = plugin.lastUpdated
        try await waitForPluginOperation(oldOperation)
        #expect(plugin.content == "newer\n")
        #expect(plugin.lastState == .Success)
        #expect(plugin.error == nil)
        #expect(plugin.lastUpdated == newestUpdate)
    }

    @Test(arguments: [false, true]) func repeatedURLRefreshDoesNotRaceInvocationEnvironment(packaged: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let (plugin, _) = try makePlugin(root: root, packaged: packaged,
                                        body: "sleep 0.005\nprintf '%s\\n' \"${MARKER:-blank}\"\n")
        defer { plugin.operation?.cancel(); plugin.terminate() }
        for attempt in 0..<50 {
            var environment = Dictionary(uniqueKeysWithValues: (0..<500).map {
                ("TEST_KEY_\($0)", String(repeating: "x", count: 80) + "-\(attempt)-\($0)")
            })
            environment["MARKER"] = "request-\(attempt)"
            // Mirrors main-owned AppDelegate URL delivery immediately followed
            // by ExecutablePlugin.refresh, while the previous invoke may run.
            plugin.refreshEnv = environment
            plugin.refresh(reason: .URLScheme)
            try await Task.sleep(for: .milliseconds(1))
        }
        try await waitForPluginOperation(plugin.operation)
        #expect(plugin.content == "request-49\n")
    }

    @Test(arguments: [false, true]) func scheduledRunsRearmAndStopAfterTermination(packaged: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let (plugin, script) = try makePlugin(root: root, packaged: packaged, interval: "20ms", body: """
        printf '%s\\n' "$SWIFTBAR_PLUGIN_REFRESH_REASON" >> "$0.runs"
        printf 'ready\\n'
        """)
        defer { plugin.operation?.cancel(); plugin.terminate() }
        let log = URL(fileURLWithPath: script.path + ".runs")
        func runs() -> [Substring] {
            (try? String(contentsOf: log))?.split(separator: "\n") ?? []
        }
        try await waitForPluginCondition { runs().filter { $0 == "Schedule" }.count >= 2 }
        plugin.terminate()
        try await waitForPluginOperation(plugin.operation)
        let completedRuns = runs().count
        try await Task.sleep(for: .milliseconds(80))
        #expect(runs().count == completedRuns)
        #expect(plugin.content == "ready\n")
    }
}
