import Combine
import Foundation
import Testing

@testable import SwiftBar

final class TestPlugin: Plugin {
    let id: PluginID
    let type: PluginType = .Executable
    let name: String
    let file: String
    let enabled: Bool
    var metadata: PluginMetadata?
    var contentUpdatePublisher = PassthroughSubject<String?, Never>()
    var updateInterval: Double = 60
    var lastUpdated: Date?
    var lastState: PluginState
    var lastRefreshReason: PluginRefreshReason = .FirstLaunch
    var content: String?
    var error: Error?
    var debugInfo = PluginDebugInfo()
    var refreshEnv: [String: String] = [:]
    var terminateCallCount = 0

    init(id: PluginID, file: String, content: String? = "...", enabled: Bool = true, lastState: PluginState = .Loading) {
        self.id = id
        self.name = id
        self.file = file
        self.content = content
        self.enabled = enabled
        self.lastState = lastState
    }

    func refresh(reason: PluginRefreshReason) {}
    func enable() {}
    func disable() {}
    func start() {}
    func terminate() {
        terminateCallCount += 1
    }
    func invoke() -> String? { content }
    func makeScriptExecutable(file: String) {}
    func refreshPluginMetadata() {}
    func writeStdin(_ input: String) throws {}
}

struct SwiftBarTests {
    @Test func testShouldShowDefaultBarItem_whenNoVisiblePluginsAndNotInStealthMode() async throws {
        #expect(shouldShowDefaultBarItem(hasVisiblePlugins: false, stealthMode: false))
    }

    @Test func testShouldShowDefaultBarItem_hidesFallbackWhenPluginIsVisible() async throws {
        #expect(!shouldShowDefaultBarItem(hasVisiblePlugins: true, stealthMode: false))
    }

    @Test func testShouldShowDefaultBarItem_hidesFallbackInStealthMode() async throws {
        #expect(!shouldShowDefaultBarItem(hasVisiblePlugins: false, stealthMode: true))
    }

    @Test func testShouldLoadPluginFile_skipsEmptyFiles() async throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fileURL = tempDirectory.appendingPathComponent("empty.5s.sh")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data())

        #expect(!shouldLoadPluginFile(at: fileURL, makePluginExecutable: true))
    }

    @Test func testShouldLoadPluginFile_requiresExecutableBitWhenAutoChmodIsDisabled() async throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fileURL = tempDirectory.appendingPathComponent("test.5s.sh")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data("echo hi\n".utf8))

        #expect(!shouldLoadPluginFile(at: fileURL, makePluginExecutable: false))
        #expect(shouldLoadPluginFile(at: fileURL, makePluginExecutable: true))
    }

    @Test func testShouldLoadPluginFile_acceptsSymlinkedExecutableFiles() async throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let targetFileURL = tempDirectory.appendingPathComponent("target.5s.sh")
        try Data("#!/bin/zsh\necho hi\n".utf8).write(to: targetFileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: targetFileURL.path)

        let symlinkURL = tempDirectory.appendingPathComponent("link.5s.sh")
        try FileManager.default.createSymbolicLink(atPath: symlinkURL.path, withDestinationPath: targetFileURL.path)

        #expect(pluginFileState(for: symlinkURL) != nil)
        #expect(shouldLoadPluginFile(at: symlinkURL, makePluginExecutable: false))
    }

    @Test func testMenuItemActionKinds_includeHrefAndRefreshTogether() async throws {
        let params = MenuLineParameters(line: "Test | href=https://example.com refresh=true")

        #expect(MenubarItem.actionKinds(for: params) == [.href, .refresh])
    }

    @Test func testMenuItemActionKinds_includeAllSupportedActionsWithoutShortCircuiting() async throws {
        let params = MenuLineParameters(line: "Test | href=https://example.com bash=/bin/echo param1=hello stdin=ping refresh=true")

        #expect(MenubarItem.actionKinds(for: params) == [.href, .bash, .stdin, .refresh])
    }

    @Test func testMenuItemActionKinds_ignorePlaceholderHref() async throws {
        let params = MenuLineParameters(line: "Test | href=. refresh=true")

        #expect(MenubarItem.actionKinds(for: params) == [.refresh])
    }

    @Test func testHasAction_falseWithNoActionParams() async throws {
        let params = MenuLineParameters(line: "Status | color=red")
        #expect(!params.hasAction)
    }

    @Test func testHasAction_trueWithRefresh() async throws {
        let params = MenuLineParameters(line: "Status | color=red refresh=true")
        #expect(params.hasAction)
    }

    @Test func testColorParam_parsedWithoutAction() async throws {
        let params = MenuLineParameters(line: "Status | color=white")
        #expect(params.color != nil)
        #expect(!params.hasAction)
    }

    @Test func testParseUserShell_extractsShellPath() async throws {
        let output = """
        GeneratedUID: ABCDEF-1234
        UserShell: /opt/homebrew/bin/fish
        """

        #expect(parseUserShell(from: output) == "/opt/homebrew/bin/fish")
    }

    @Test func testParseUserShell_returnsNilWhenMissing() async throws {
        let output = "GeneratedUID: ABCDEF-1234"

        #expect(parseUserShell(from: output) == nil)
    }

    @Test func testParseUserShell_trimsWhitespace() async throws {
        let output = "UserShell:    /bin/zsh  \n"

        #expect(parseUserShell(from: output) == "/bin/zsh")
    }

    @Test func testParseUserShell_returnsNilForEmptyValue() async throws {
        let output = "UserShell:   "

        #expect(parseUserShell(from: output) == nil)
    }

    @Test func testStatusItemVisibilityKeys_preservesPreferredPositionKeys() async throws {
        let keysToRemove = statusItemVisibilityKeys(in: [
            "NSStatusItem Visible com.example.one": 0,
            "NSStatusItem Visible com.example.two": 1,
            "NSStatusItem Preferred Position com.example.one": 12,
            "UnrelatedKey": true,
        ])

        #expect(keysToRemove == [
            "NSStatusItem Visible com.example.one",
            "NSStatusItem Visible com.example.two",
        ])
    }

    @Test func testBuildTerminalCommand_quotesMultiWordBashCArgument() async throws {
        let command = buildTerminalCommand(
            script: "bash",
            args: ["-c", "echo Hello"],
            env: [:]
        )

        #expect(command.contains("bash -c 'echo Hello'"))
    }

    @Test func testBuildTerminalCommand_preservesShellExpandedExecutablePath() async throws {
        let command = buildTerminalCommand(
            script: "$HOME/bin/tool",
            args: ["--flag"],
            env: [:]
        )

        #expect(command.contains("$HOME/bin/tool --flag"))
        #expect(!command.contains("'$HOME/bin/tool'"))
    }

    @Test func testBuildTerminalCommand_andAppleScriptEscaping_preserveQuotedArguments() async throws {
        let command = buildTerminalCommand(
            script: "bash",
            args: ["-c", "echo \"Hello\" && echo done"],
            env: [:]
        )
        let appleScriptSafe = command.appleScriptEscaped()

        #expect(command.contains("bash -c 'echo \"Hello\" && echo done'"))
        #expect(appleScriptSafe.contains("\\\"Hello\\\""))
    }

    @Test func testBuildTerminalAppleScript_terminalUsesExplicitNewTabPath() async throws {
        let appleScript = buildTerminalAppleScript(command: "echo hello", terminal: .Terminal)

        #expect(appleScript.contains("if (count of windows) is 0 then"))
        #expect(appleScript.contains("do script \"echo hello\""))
        #expect(appleScript.contains("keystroke \"t\" using {command down}"))
        #expect(appleScript.contains("do script \"echo hello\" in selected tab of front window"))
    }

    @Test func testBuildTerminalAppleScript_iTermUsesCreateTabAndWriteText() async throws {
        let appleScript = buildTerminalAppleScript(command: "echo hello", terminal: .iTerm)

        #expect(appleScript.contains("if (count of windows) is 0 then"))
        #expect(appleScript.contains("create window with default profile"))
        #expect(appleScript.contains("create tab with default profile"))
        #expect(appleScript.contains("tell current session of current tab of current window to write text \"echo hello\""))
    }

    @Test func testBuildTerminalAppleScript_ghosttyUsesNativeAppleScriptAPI() async throws {
        let appleScript = buildTerminalAppleScript(command: "echo hello", terminal: .Ghostty)

        #expect(appleScript.contains("set ghosttyWindow to front window"))
        #expect(appleScript.contains("set ghosttyTab to new tab in ghosttyWindow"))
        #expect(appleScript.contains("set ghosttyTerminal to focused terminal of ghosttyTab"))
        #expect(appleScript.contains("set ghosttyWindow to new window"))
        #expect(appleScript.contains("input text \"echo hello\" to ghosttyTerminal"))
        #expect(appleScript.contains("send key \"enter\" to ghosttyTerminal"))
        #expect(!appleScript.contains("System Events"))
        #expect(!appleScript.contains("keystroke"))
    }

    @Test func testBuildTerminalAppleScript_ghosttyEscapesQuotedCommands() async throws {
        let appleScript = buildTerminalAppleScript(command: "echo \"hello\"", terminal: .Ghostty)

        #expect(appleScript.contains("input text \"echo \\\"hello\\\"\" to ghosttyTerminal"))
    }

    @Test func testBuildKittyLaunchArguments_usesSingleInstanceLoginShellLaunch() async throws {
        let args = buildKittyLaunchArguments(command: "export FOO=bar; echo hello", loginShell: "/bin/zsh")

        #expect(args == [
            "--single-instance",
            "/bin/zsh",
            "-lc",
            "export FOO=bar; echo hello",
        ])
    }

    @Test func testBuildKittyLaunchArguments_usesCshCompatibleCommandFlag() async throws {
        let args = buildKittyLaunchArguments(command: "setenv FOO bar; echo hello", loginShell: "/bin/tcsh")

        #expect(args == [
            "--single-instance",
            "/bin/tcsh",
            "-c",
            "setenv FOO bar; echo hello",
        ])
    }

    @Test func testBuildTerminalCommand_preventsCommandInjectionViaSemicolon() async throws {
        let command = buildTerminalCommand(
            script: "echo",
            args: ["foo; rm -rf /"],
            env: [:]
        )

        // The malicious arg should be fully quoted, not interpreted as separate commands
        #expect(command.contains("'foo; rm -rf /'"))
    }

    @Test func testBuildTerminalCommand_quotesEnclosedInQuotesBypass() async throws {
        let safelyQuoted = "'; rm -rf /; echo '"
        let result = safelyQuoted.quoteIfNeeded()

        // This shell token is already safely single-quoted, so it should be preserved.
        #expect(result == safelyQuoted)
    }

    @Test func testBuildTerminalCommand_requotesMalformedSingleQuotedToken() async throws {
        let malformed = "'foo' bar '"
        let result = malformed.quoteIfNeeded()

        #expect(result != malformed)
    }

    @Test func testBuildTerminalCommand_preservesEscapedApostropheSingleQuotedToken() async throws {
        let quoted = "'O'\\''Reilly'"
        let result = quoted.quoteIfNeeded()

        #expect(result == quoted)
    }

    @Test func testBuildTerminalCommand_preventsCommandInjectionViaDollar() async throws {
        let command = buildTerminalCommand(
            script: "echo",
            args: ["$(whoami)"],
            env: [:]
        )

        // Should be single-quoted so $() is not expanded
        #expect(command.contains("'$(whoami)'"))
    }

    @Test func testBuildTerminalCommand_preventsBacktickExpansion() async throws {
        let command = buildTerminalCommand(
            script: "echo",
            args: ["`whoami`"],
            env: [:]
        )

        // Should be single-quoted so backticks are not expanded
        #expect(command.contains("'`whoami`'"))
    }

    @Test func testBuildTerminalCommand_handlesPipeAndRedirect() async throws {
        let command = buildTerminalCommand(
            script: "echo",
            args: ["hello | cat > /tmp/evil"],
            env: [:]
        )

        // Should be quoted as a single argument, not interpreted as pipe/redirect
        #expect(command.contains("'hello | cat > /tmp/evil'"))
    }

    @Test func testBuildTerminalCommand_envValueWithMetacharacters() async throws {
        let originalShell = sharedEnv.userLoginShell
        defer { sharedEnv.userLoginShell = originalShell }
        sharedEnv.userLoginShell = "/bin/zsh"

        let command = buildTerminalCommand(
            script: "echo",
            args: [],
            env: ["EVIL": "$(whoami); rm -rf /"]
        )

        // Env value should be safely quoted
        #expect(command.contains("EVIL='$(whoami); rm -rf /'"))
    }

    @Test func testAppleScriptEscaped_handlesBackslashesAndQuotes() async throws {
        let input = "path\\to\\file \"with quotes\""
        let escaped = input.appleScriptEscaped()

        // Backslashes must be escaped first (\\ in AppleScript = literal \),
        // then double quotes (\\" in AppleScript = literal ")
        #expect(escaped == "path\\\\to\\\\file \\\"with quotes\\\"")
    }

    @Test func testAppleScriptEscaped_escapesBackslashFromShellQuoting() async throws {
        // quoteIfNeeded() uses the '\'' pattern to escape single quotes in shell.
        // This pattern contains a backslash which AppleScript would treat as an
        // escape character, causing a parse error on \'. Escaping \ to \\ fixes this.
        let shellQuoted = "hello'world".quoteIfNeeded()
        #expect(shellQuoted == "'hello'\\''world'")

        let escaped = shellQuoted.appleScriptEscaped()
        // '\'' becomes '\\'' — AppleScript sees \\\\ as literal backslash
        #expect(escaped == "'hello'\\\\''world'")
    }

    @Test func testAppleScriptEscaped_plainStringUnchanged() async throws {
        let input = "hello world"
        #expect(input.appleScriptEscaped() == "hello world")
    }

    @Test func testQuoteIfNeeded_singleQuotes() async throws {
        // Test that strings with single quotes are properly escaped
        let input = "This has 'single quotes'"
        let output = input.quoteIfNeeded()
        #expect(output == "'This has '\\''single quotes'\\'''")
    }

    @Test func testQuoteIfNeeded_noSpecialChars() async throws {
        // Test that strings without special characters remain unchanged
        let input = "simple_string"
        let output = input.quoteIfNeeded()
        #expect(output == "simple_string")
    }

    @Test func testEscaped_withSpaces() async throws {
        // Test that strings with spaces are quoted
        let input = "string with spaces"
        let output = input.escaped()
        #expect(output == "'string with spaces'")
    }

    @Test func testNeedsShellQuoting_withSingleQuotes() async throws {
        // Test that strings with single quotes need shell quoting
        let input = "string with 'quotes'"
        #expect(input.needsShellQuoting)
    }

    @Test func testProcessArgs_singleQuotes_runInBash() async throws {
        // This test simulates what happens in Process.launchScript when runInBash = true
        let script = "/path/to/script.sh"
        let args = ["arg with 'quotes'", "normal arg"]

        let escapedArgs = args.map { $0.quoteIfNeeded() }
        let bashArgs = ["-c", "\(script.escaped()) \(escapedArgs.joined(separator: " "))"]

        #expect(escapedArgs[0] == "'arg with '\\''quotes'\\'''")
        #expect(escapedArgs[1] == "'normal arg'") // "normal arg" contains a space so it needs quoting
        #expect(bashArgs[1].contains("'\\''quotes'\\''"))
    }

    @Test func testProcessArgs_singleQuotes_runWithoutBash() async throws {
        // This test simulates what happens in Process.launchScript when runInBash = false
        // In this case, args should be passed directly without any quoting
        let args = ["arg with 'quotes'", "normal arg"]

        // When runInBash = false, arguments should be passed directly without quoting
        #expect(args[0] == "arg with 'quotes'")
    }

    @Test func testProcessArgs_complexShellChars_runInBash() async throws {
        // Test handling of various shell special characters
        let args = ["arg with $HOME", "arg with \"quotes\"", "arg with ;", "arg with &&"]

        let escapedArgs = args.map { $0.quoteIfNeeded() }

        #expect(escapedArgs[0] == "'arg with $HOME'")
        #expect(escapedArgs[1] == "'arg with \"quotes\"'")
        #expect(escapedArgs[2] == "'arg with ;'")
        #expect(escapedArgs[3] == "'arg with &&'")
    }

    @Test func testProcessArgs_complexShellChars_runWithoutBash() async throws {
        // When not running in bash, all characters should be preserved exactly
        let args = ["arg with $HOME", "arg with \"quotes\"", "arg with ;", "arg with &&"]

        // These should be passed directly to the process without modification
        for (index, arg) in args.enumerated() {
            #expect(args[index] == arg, "Argument should be preserved exactly as is")
        }
    }

    @Test func testSingleQuotesInParameters() async throws {
        // This test specifically verifies the fix for the issue with single quotes
        // in parameters when runInBash is false

        // This is the exact scenario described in the bug report:
        // "single quote in text param | terminal=false bash='./.write.php' param1=\"text's\""
        let singleQuoteArg = "text's"

        // For runInBash = false, arguments should be passed directly
        // This is the correct behavior for the fix
        let directArgs = [singleQuoteArg]

        // Verify that with runInBash = false, the argument is passed as-is including the single quote
        #expect(directArgs[0] == "text's",
                "Single quotes should be preserved exactly when runInBash is false")

        // Test the specific escaped quote cases from the bug report
        let escapedSingleQuoteArg = "text\\'s"
        let doubleEscapedArg = "text\\\\'s"

        let escapedArgs = [escapedSingleQuoteArg, doubleEscapedArg]

        // These should be passed directly to the process without any changes when runInBash = false
        #expect(escapedArgs[0] == "text\\'s", "Escaped single quotes should be preserved exactly")
        #expect(escapedArgs[1] == "text\\\\'s", "Double escaped backslashes should be preserved exactly")
    }

    @Test func testMenuLineParameters_singleQuoteInParam() async throws {
        // This tests the exact scenario from the bug report
        let line = "single quote in text param | terminal=false bash='/path/to/script.php' param1=\"text's\""

        let params = MenuLineParameters(line: line)

        // Verify the parameter with single quote was parsed correctly
        #expect(params.params["param1"] == "text's", "Parameter with single quote should be preserved exactly")
        #expect(params.terminal == false, "Terminal parameter should be false")

        // Get the bash parameters
        let bashParams = params.bashParams

        // Verify that the parameter still contains the single quote
        #expect(bashParams.count == 1, "Should have one bash parameter")
        #expect(bashParams[0] == "text's", "Bash parameter should preserve the single quote")
    }

    @Test func testMenuLineParameters_additionalQuoteCases() async throws {
        // Test case 1: Double quotes inside single-quoted value
        let line1 = "quotes test | bash='/path/script.sh' param1='text with \"quotes\"'"
        let params1 = MenuLineParameters(line: line1)

        #expect(params1.params["param1"] == "text with \"quotes\"",
                "Parameter with double quotes inside single quotes should be preserved")

        // Test case 2: Escaped quotes in value
        let line2 = "escaped quotes | bash='/script.sh' param1=\"text with \\\"escaped quotes\\\"\""
        let params2 = MenuLineParameters(line: line2)

        // We expect both backslashes and quotes to be preserved exactly
        #expect(params2.params["param1"] == "text with \\\"escaped quotes\\\"",
                "Parameter with escaped quotes should preserve the backslashes")

        // Test case 3: Multiple parameters with different quote styles
        let line3 = "multiple params | param1=\"double quoted\" param2='single quoted' param3=unquoted"
        let params3 = MenuLineParameters(line: line3)

        #expect(params3.params["param1"] == "double quoted", "Double quoted parameter should be parsed correctly")
        #expect(params3.params["param2"] == "single quoted", "Single quoted parameter should be parsed correctly")
        #expect(params3.params["param3"] == "unquoted", "Unquoted parameter should be parsed correctly")

        // Test case 4: Complex real-world examples
        let line4 = "complex example | bash=\"/bin/sh\" param1=\"arg with 'single quotes' inside\" param2='arg with \"double quotes\" inside'"
        let params4 = MenuLineParameters(line: line4)

        #expect(params4.params["param1"] == "arg with 'single quotes' inside",
                "Single quotes inside double quotes should be preserved")
        #expect(params4.params["param2"] == "arg with \"double quotes\" inside",
                "Double quotes inside single quotes should be preserved")

        // Test case 5: Escaped single quotes - reported issue cases
        let line5 = "escaped single quote | terminal=false bash='/path/script.php' param1=\"text\\'s\""
        let params5 = MenuLineParameters(line: line5)

        #expect(params5.params["param1"] == "text\\'s",
                "Escaped single quote should be preserved exactly as typed")

        // Test case 6: Double escaped backslash with single quote
        let line6 = "double escaped | terminal=false bash='/path/script.php' param1=\"text\\\\'s\""
        let params6 = MenuLineParameters(line: line6)

        #expect(params6.params["param1"] == "text\\\\'s",
                "Double escaped backslash with single quote should be preserved exactly")
    }
}

@Suite(.serialized)
struct SwiftBarIntegrationTests {
    @Test func testPluginFileState_changesWhenFileContentChanges() async throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fileURL = tempDirectory.appendingPathComponent("test.5s.sh")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data("echo hi\n".utf8))

        let initialState = try #require(pluginFileState(for: fileURL))
        try Data("echo hello world\n".utf8).write(to: fileURL)
        let updatedState = try #require(pluginFileState(for: fileURL))

        #expect(initialState != updatedState)
    }

    @MainActor @Test func testPluginItemHideCallbackRestoresDefaultBarItem() async throws {
        let manager = PluginManager()
        let originalStealthMode = manager.prefs.stealthMode
        manager.prefs.stealthMode = false

        defer {
            manager.plugins.removeAll()
            manager.menuBarItems.removeAll()
            manager.directoryObserver = nil
            manager.barItem.show()
            manager.prefs.stealthMode = originalStealthMode
        }

        let plugin = TestPlugin(id: "test-plugin", file: "/tmp/test-plugin.5s.sh")
        manager.plugins = [plugin]

        let pluginItem = try #require(manager.menuBarItems[plugin.id])
        #expect(!manager.barItem.barItem.isVisible)

        pluginItem.hide()

        #expect(manager.barItem.barItem.isVisible)
    }

    @Test func testSyncFilePlugins_reloadsModifiedFilePlugin() async throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fileURL = tempDirectory.appendingPathComponent("test.5s.sh")
        try Data("#!/bin/zsh\necho one\n".utf8).write(to: fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fileURL.path)

        let initialState = try #require(pluginFileState(for: fileURL))
        let existingPlugin = TestPlugin(id: "original-plugin", file: fileURL.path, content: "one", lastState: .Success)

        try Data("#!/bin/zsh\necho updated output that changes size\n".utf8).write(to: fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fileURL.path)

        let syncResult = syncFilePlugins(
            existingFilePlugins: [existingPlugin],
            freshFilePlugins: [fileURL],
            previousFileStates: [fileURL.path: initialState]
        ) { fileURL in
            TestPlugin(
                id: "reloaded-plugin",
                file: fileURL.path,
                content: "updated",
                lastState: .Success
            )
        }

        let reloadedPlugin = try #require(syncResult.loadedPlugins.first)
        #expect(syncResult.removedPluginIDs.isEmpty)
        #expect(syncResult.modifiedPluginIDs == [existingPlugin.id])
        #expect(syncResult.loadedPlugins.count == 1)
        #expect(ObjectIdentifier(reloadedPlugin as AnyObject) != ObjectIdentifier(existingPlugin as AnyObject))
        #expect(syncResult.freshFileStates[fileURL.path] != initialState)
    }

    @Test func testSyncFilePlugins_doesNotTreatTemporarilySkippedFileAsRemoved() async throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fileURL = tempDirectory.appendingPathComponent("test.5s.sh")
        try Data("#!/bin/zsh\necho one\n".utf8).write(to: fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)

        let existingPlugin = TestPlugin(id: "disabled-plugin", file: fileURL.path, enabled: false, lastState: .Disabled)

        let syncResult = syncFilePlugins(
            existingFilePlugins: [existingPlugin],
            freshFilePlugins: [],
            previousFileStates: [:],
            discoveredFilePlugins: [fileURL]
        ) { fileURL in
            TestPlugin(id: "reloaded-plugin", file: fileURL.path, content: "updated", lastState: .Success)
        }

        #expect(syncResult.removedPluginIDs.isEmpty)
        #expect(syncResult.modifiedPluginIDs.isEmpty)
        #expect(syncResult.loadedPlugins.isEmpty)
    }

    @Test func testMergePluginsPreservingOrder_replacesModifiedPluginsInPlace() async throws {
        let firstPlugin = TestPlugin(id: "first", file: "/tmp/first.5s.sh")
        let modifiedPlugin = TestPlugin(id: "modified", file: "/tmp/modified.5s.sh")
        let thirdPlugin = TestPlugin(id: "third", file: "/tmp/third.5s.sh")
        let replacementPlugin = TestPlugin(id: "modified", file: "/tmp/modified.5s.sh", content: "updated")

        let mergedPlugins = mergePluginsPreservingOrder(
            existingPlugins: [firstPlugin, modifiedPlugin, thirdPlugin],
            removedPluginIDs: [],
            reloadedFilePlugins: [replacementPlugin],
            newShortcutPlugins: []
        )

        #expect(mergedPlugins.count == 3)
        #expect(mergedPlugins[0] === firstPlugin)
        #expect(mergedPlugins[1] === replacementPlugin)
        #expect(mergedPlugins[2] === thirdPlugin)
    }

    @Test func testMergePluginsPreservingOrder_removesPluginInMiddleOfList() async throws {
        let first = TestPlugin(id: "first", file: "/tmp/first.5s.sh")
        let middle = TestPlugin(id: "middle", file: "/tmp/middle.5s.sh")
        let last = TestPlugin(id: "last", file: "/tmp/last.5s.sh")

        let merged = mergePluginsPreservingOrder(
            existingPlugins: [first, middle, last],
            removedPluginIDs: ["middle"],
            reloadedFilePlugins: [],
            newShortcutPlugins: []
        )

        #expect(merged.count == 2)
        #expect(merged[0] === first)
        #expect(merged[1] === last)
    }

    @Test func testMergePluginsPreservingOrder_appendsNewFilePluginAndShortcuts() async throws {
        let existing = TestPlugin(id: "existing", file: "/tmp/existing.5s.sh")
        let brandNew = TestPlugin(id: "brand-new", file: "/tmp/brand-new.5s.sh")
        let shortcut = ShortcutPlugin(PersistentShortcutPlugin(id: "shortcut", name: "shortcut", shortcut: "test", repeatString: "", cronString: ""))

        let merged = mergePluginsPreservingOrder(
            existingPlugins: [existing],
            removedPluginIDs: [],
            reloadedFilePlugins: [brandNew],
            newShortcutPlugins: [shortcut]
        )

        #expect(merged.count == 3)
        #expect(merged[0] === existing)
        #expect(merged[1] === brandNew)
        #expect(merged[2] === shortcut)
    }

    @Test func testUnloadPlugins_preservesDisabledStateForModifiedPlugins() async throws {
        let manager = PluginManager()
        let originalDisabledPlugins = manager.prefs.disabledPlugins
        defer { manager.prefs.disabledPlugins = originalDisabledPlugins }

        let plugin = TestPlugin(id: "disabled-plugin", file: "/tmp/disabled-plugin.5s.sh", enabled: false, lastState: .Disabled)
        manager.prefs.disabledPlugins = [plugin.id]
        manager.plugins = [plugin]

        manager.unloadPlugins([plugin], clearDisabledState: false)

        #expect(plugin.terminateCallCount == 1)
        #expect(manager.prefs.disabledPlugins == [plugin.id])
        #expect(manager.plugins.isEmpty)
    }

    @Test func testUnloadPlugins_clearsDisabledStateForRemovedPlugins() async throws {
        let manager = PluginManager()
        let originalDisabledPlugins = manager.prefs.disabledPlugins
        defer { manager.prefs.disabledPlugins = originalDisabledPlugins }

        let plugin = TestPlugin(id: "removed-plugin", file: "/tmp/removed-plugin.5s.sh", enabled: false, lastState: .Disabled)
        manager.prefs.disabledPlugins = [plugin.id]
        manager.plugins = [plugin]

        manager.unloadPlugins([plugin], clearDisabledState: true)

        #expect(plugin.terminateCallCount == 1)
        #expect(manager.prefs.disabledPlugins.isEmpty)
        #expect(manager.plugins.isEmpty)
    }

    @MainActor @Test func testPluginsDidChange_reusesMenuBarItemForReloadedPluginWithSameID() async throws {
        let manager = PluginManager()
        defer {
            manager.plugins.removeAll()
            manager.menuBarItems.removeAll()
            manager.directoryObserver = nil
        }

        let originalPlugin = TestPlugin(id: "reloaded-plugin", file: "/tmp/reloaded-plugin.5s.sh", content: "one")
        let replacementPlugin = TestPlugin(id: "reloaded-plugin", file: "/tmp/reloaded-plugin.5s.sh", content: "two")

        manager.plugins = [originalPlugin]

        let originalMenuBarItem = try #require(manager.menuBarItems[originalPlugin.id])

        manager.plugins = [replacementPlugin]

        let updatedMenuBarItem = try #require(manager.menuBarItems[replacementPlugin.id])
        #expect(updatedMenuBarItem === originalMenuBarItem)
        #expect(updatedMenuBarItem.plugin === replacementPlugin)
    }
}

struct PluginMetadataEnvironmentParsingTests {
    @Test func testEnvironmentParsing_BasicCommaSeparation() throws {
        let script = "<swiftbar.environment>[VAR1=val1,VAR2=val2]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["VAR1"] == "val1")
        #expect(metadata.environment["VAR2"] == "val2")
        #expect(metadata.environment.count == 2)
    }

    @Test func testEnvironmentExportString_WithEqualsInValue() throws {
        let originalShell = sharedEnv.userLoginShell
        defer { sharedEnv.userLoginShell = originalShell }
        sharedEnv.userLoginShell = "/bin/zsh"

        // Test case from issue #445: VAR_MONOSPACE_FONT: font=Menlo size=12
        let env = ["VAR_MONOSPACE_FONT": "font=Menlo size=12"]
        let exportString = getEnvExportString(env: env)

        // The export string should properly handle values with equals signs
        #expect(exportString.contains("VAR_MONOSPACE_FONT='font=Menlo size=12'"))

        // The export string should be valid shell syntax
        #expect(exportString.starts(with: "export "))
        #expect(!exportString.contains("VAR_MONOSPACE_FONT: font"))
    }

    @Test func testEnvironmentExportString_WithSpecialChars() throws {
        let originalShell = sharedEnv.userLoginShell
        defer { sharedEnv.userLoginShell = originalShell }
        sharedEnv.userLoginShell = "/bin/zsh"

        // Test various special characters that might cause issues
        let env = [
            "VAR_WITH_EQUALS": "key=value",
            "VAR_WITH_COLON": "key:value",
            "VAR_WITH_SPACES": "value with spaces",
            "VAR_WITH_QUOTES": "value with 'quotes'",
            "VAR_COMPLEX": "font=Menlo size=12 style=bold",
        ]
        let exportString = getEnvExportString(env: env)

        // The export string should be valid for shell execution
        #expect(exportString.starts(with: "export "))

        // Test individual quoting behavior to understand what's expected
        #expect("key=value".quoteIfNeeded() == "key=value", "Equals alone should not trigger quoting")
        #expect("key:value".quoteIfNeeded() == "key:value", "Colon alone should not trigger quoting")
        #expect("value with spaces".quoteIfNeeded() == "'value with spaces'", "Spaces should trigger quoting")
        #expect("value with 'quotes'".quoteIfNeeded() == "'value with '\\''quotes'\\'''", "Single quotes should be escaped")
        #expect("font=Menlo size=12 style=bold".quoteIfNeeded() == "'font=Menlo size=12 style=bold'", "Spaces should trigger quoting")

        // Test our specific variables are present in the export string
        // Since = and : don't need quoting by themselves, they will be unquoted
        #expect(exportString.contains("VAR_WITH_EQUALS=key=value") || exportString.contains("VAR_WITH_EQUALS='key=value'"))
        #expect(exportString.contains("VAR_WITH_COLON=key:value") || exportString.contains("VAR_WITH_COLON='key:value'"))
        #expect(exportString.contains("VAR_WITH_SPACES='value with spaces'"))
        #expect(exportString.contains("VAR_WITH_QUOTES='value with '\\''quotes'\\'''"))
        #expect(exportString.contains("VAR_COMPLEX='font=Menlo size=12 style=bold'"))
    }

    @Test func testIssue445_EnvironmentVariableParsing() throws {
        let originalShell = sharedEnv.userLoginShell
        defer { sharedEnv.userLoginShell = originalShell }
        sharedEnv.userLoginShell = "/bin/zsh"

        // Test the specific issue reported in GitHub #445
        let script = "<swiftbar.environment>[VAR_MONOSPACE_FONT: font=Menlo size=12]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)

        // Environment parsing should work correctly
        #expect(metadata.environment["VAR_MONOSPACE_FONT"] == "font=Menlo size=12")
        #expect(metadata.environment.count == 1)

        // Test the export string generation
        let exportString = getEnvExportString(env: metadata.environment)
        #expect(exportString.contains("VAR_MONOSPACE_FONT='font=Menlo size=12'"))
        #expect(exportString.starts(with: "export "))

        // Ensure the export string doesn't contain the colon separator in the wrong place
        #expect(!exportString.contains("VAR_MONOSPACE_FONT: font"))
    }

    @Test func testMenuLineParameters_TabCharacterHandling() throws {
        // Test the fix for issue #455: tab character handling
        // The unescape function should convert \t escape sequences to actual tab characters

        // Test that the title is extracted correctly (with escape sequences preserved as literal characters)
        let line1 = "Hello\\tWorld | bash='/bin/echo'"
        let params1 = MenuLineParameters(line: line1)
        // The title contains the literal backslash and t characters
        #expect(params1.title.contains("\\"), "Title should contain backslash")
        #expect(params1.title.contains("t"), "Title should contain t")

        // Test multiple escapes
        let line2 = "Column1\\tColumn2\\tColumn3"
        let params2 = MenuLineParameters(line: line2)
        #expect(params2.title.contains("\\"), "Title should contain backslashes")

        // Test mixed escapes
        let line3 = "Test\\tTab\\nNewline | color=blue"
        let params3 = MenuLineParameters(line: line3)
        #expect(params3.title.contains("\\"), "Title should contain escape characters")
        #expect(params3.params["color"] == "blue", "Parameters should be parsed correctly")
    }

    @Test func testIssue445_ShellExportString() throws {
        let originalShell = sharedEnv.userLoginShell
        defer { sharedEnv.userLoginShell = originalShell }
        sharedEnv.userLoginShell = "/bin/zsh"

        // Test that environment variables with equals signs in values are properly escaped
        // This addresses the specific tcsh export error mentioned in the issue
        let problematicEnv = [
            "VAR_MONOSPACE_FONT": "font=Menlo size=12",
            "VAR_COMPLEX": "key1=value1 key2=value2",
            "VAR_SIMPLE": "simple_value",
        ]

        let exportString = getEnvExportString(env: problematicEnv)

        // The export string should be valid for shell execution
        #expect(exportString.starts(with: "export "))

        // Verify each of our test variables is properly quoted
        // Note: The function merges with system env, so we check for specific patterns
        #expect(exportString.contains("VAR_MONOSPACE_FONT='font=Menlo size=12'"))
        #expect(exportString.contains("VAR_COMPLEX='key1=value1 key2=value2'"))

        // VAR_SIMPLE might not need quoting since it has no special characters
        // Check for either quoted or unquoted version
        let hasSimpleQuoted = exportString.contains("VAR_SIMPLE='simple_value'")
        let hasSimpleUnquoted = exportString.contains("VAR_SIMPLE=simple_value")
        #expect(hasSimpleQuoted || hasSimpleUnquoted,
                "VAR_SIMPLE should be present either quoted or unquoted")
    }

    @Test func testEnvironmentParsing_EqualsSeparator() throws {
        let script = "<swiftbar.environment>[MY_VAR=value]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["MY_VAR"] == "value")
        #expect(metadata.environment.count == 1)
    }

    @Test func testEnvironmentParsing_ColonSeparator() throws {
        let script = "<swiftbar.environment>[MY_VAR:value]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["MY_VAR"] == "value")
        #expect(metadata.environment.count == 1)
    }

    @Test func testEnvironmentParsing_ValueContainsEqualsColonSeparator() throws {
        let script = "<swiftbar.environment>[MY_VAR:key=value,OTHER_VAR:another=val]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["MY_VAR"] == "key=value")
        #expect(metadata.environment["OTHER_VAR"] == "another=val")
        #expect(metadata.environment.count == 2)
    }

    @Test func testEnvironmentParsing_ValueContainsColonEqualsSeparator() throws {
        let script = "<swiftbar.environment>[MY_VAR=key:value,OTHER_VAR=another:val]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["MY_VAR"] == "key:value")
        #expect(metadata.environment["OTHER_VAR"] == "another:val")
        #expect(metadata.environment.count == 2)
    }

    @Test func testEnvironmentParsing_EmptyValueEqualsSeparator() throws {
        let script = "<swiftbar.environment>[MY_VAR=]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["MY_VAR"] == "")
        #expect(metadata.environment.count == 1)
    }

    @Test func testEnvironmentParsing_EmptyValueColonSeparator() throws {
        let script = "<swiftbar.environment>[MY_VAR:]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["MY_VAR"] == "")
        #expect(metadata.environment.count == 1)
    }

    @Test func testEnvironmentParsing_LeadingTrailingWhitespace() throws {
        let script = "<swiftbar.environment>[  MY_VAR  =  val with spaces  ,  NEXT_VAR:val2  ]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["MY_VAR"] == "val with spaces")
        #expect(metadata.environment["NEXT_VAR"] == "val2")
        #expect(metadata.environment.count == 2)
    }

    @Test func testEnvironmentParsing_NoBrackets() throws {
        let script = "<swiftbar.environment>VAR_A=1,VAR_B:2</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["VAR_A"] == "1")
        #expect(metadata.environment["VAR_B"] == "2")
        #expect(metadata.environment.count == 2)
    }

    @Test func testEnvironmentParsing_MixedSeparators() throws {
        let script = "<swiftbar.environment>[VAR_EQ=val1,VAR_COL:val2,VAR_COMPLEX:data=value,VAR_OTHER_COMPLEX=data:value]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["VAR_EQ"] == "val1")
        #expect(metadata.environment["VAR_COL"] == "val2")
        #expect(metadata.environment["VAR_COMPLEX"] == "data=value")
        #expect(metadata.environment["VAR_OTHER_COMPLEX"] == "data:value")
        #expect(metadata.environment.count == 4)
    }

    @Test func testEnvironmentParsing_SingleVariableEquals() throws {
        let script = "<swiftbar.environment>[SINGLE_VAR=foo]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["SINGLE_VAR"] == "foo")
        #expect(metadata.environment.count == 1)
    }

    @Test func testEnvironmentParsing_SingleVariableColon() throws {
        let script = "<swiftbar.environment>[SINGLE_VAR:bar]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["SINGLE_VAR"] == "bar")
        #expect(metadata.environment.count == 1)
    }

    @Test func testEnvironmentParsing_KeyContainsNeitherSeparator() throws {
        // Test case 13: Variable with equals in key (should not happen based on current parsing but good to be defensive if primary separator logic is ':' e.g. VAR=WITH=EQUALS:value - this might be an invalid case depending on how strictly we define keys) For now, let's assume keys do not contain = or :.
        // Based on the current implementation, the key is everything before the *first* determined separator.
        // So, `VAR=WITH=EQUALS:value` will be parsed as `VAR=WITH=EQUALS` -> `value` if `:` is the separator.
        // And `VAR:WITH:COLONS=value` will be parsed as `VAR:WITH:COLONS` -> `value` if `=` is the separator.
        // The prompt states "assume keys do not contain = or :", so this test will verify standard behavior.
        // A key like "MY_KEY" is valid. "MY=KEY" or "MY:KEY" is assumed not to be a valid key string.
        // This test will simply use a valid key. The more complex cases are handled by valueContainsEquals/Colon tests.
        let script = "<swiftbar.environment>[MY_VALID_KEY=somesvalue]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["MY_VALID_KEY"] == "somesvalue")
        #expect(metadata.environment.count == 1)
    }

    @Test func testEnvironmentParsing_ComplexRealWorldCase() throws {
        let script = "<swiftbar.environment>[VAR_SUBMENU_LAYOUT: false, VAR_TABLE_RENDERING: true, VAR_DEFAULT_FONT: , VAR_MONOSPACE_FONT: font=Menlo size=12]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["VAR_SUBMENU_LAYOUT"] == "false")
        #expect(metadata.environment["VAR_TABLE_RENDERING"] == "true")
        #expect(metadata.environment["VAR_DEFAULT_FONT"] == "")
        #expect(metadata.environment["VAR_MONOSPACE_FONT"] == "font=Menlo size=12")
        #expect(metadata.environment.count == 4)
    }
}

// MARK: - xbar.var Variable Tests (Issue #469)

struct PluginVariableParsingTests {
    @Test func testVariableParsing_StringType() throws {
        let script = """
        #!/bin/bash
        # <xbar.var>string(VAR_NAME="default value"): Your name</xbar.var>
        echo "Hello"
        """
        let metadata = PluginMetadata.parser(script: script)

        #expect(metadata.variables.count == 1)
        let variable = metadata.variables[0]
        #expect(variable.type == .string)
        #expect(variable.name == "VAR_NAME")
        #expect(variable.defaultValue == "default value")
        #expect(variable.description == "Your name")
        #expect(variable.options.isEmpty)
    }

    @Test func testVariableParsing_NumberType() throws {
        let script = """
        #!/bin/bash
        # <xbar.var>number(VAR_COUNT="42"): Number of items</xbar.var>
        """
        let metadata = PluginMetadata.parser(script: script)

        #expect(metadata.variables.count == 1)
        let variable = metadata.variables[0]
        #expect(variable.type == .number)
        #expect(variable.name == "VAR_COUNT")
        #expect(variable.defaultValue == "42")
        #expect(variable.description == "Number of items")
    }

    @Test func testVariableParsing_BooleanType() throws {
        let script = """
        #!/bin/bash
        # <xbar.var>boolean(VAR_ENABLED="true"): Enable feature</xbar.var>
        """
        let metadata = PluginMetadata.parser(script: script)

        #expect(metadata.variables.count == 1)
        let variable = metadata.variables[0]
        #expect(variable.type == .boolean)
        #expect(variable.name == "VAR_ENABLED")
        #expect(variable.defaultValue == "true")
        #expect(variable.description == "Enable feature")
    }

    @Test func testVariableParsing_SelectType_WithOptions() throws {
        let script = """
        #!/bin/bash
        # <xbar.var>select(VAR_THEME="light"): Color theme. [light, dark, auto]</xbar.var>
        """
        let metadata = PluginMetadata.parser(script: script)

        #expect(metadata.variables.count == 1)
        let variable = metadata.variables[0]
        #expect(variable.type == .select)
        #expect(variable.name == "VAR_THEME")
        #expect(variable.defaultValue == "light")
        #expect(variable.description == "Color theme")
        #expect(variable.options == ["light", "dark", "auto"])
    }

    @Test func testVariableParsing_MultipleVariables() throws {
        let script = """
        #!/bin/bash
        # <xbar.var>string(VAR_LOCATION="San Francisco"): Your location</xbar.var>
        # <xbar.var>number(VAR_REFRESH="5"): Refresh interval</xbar.var>
        # <xbar.var>boolean(VAR_EMOJI="true"): Show emoji</xbar.var>
        # <xbar.var>select(VAR_THEME="light"): Theme. [light, dark]</xbar.var>
        """
        let metadata = PluginMetadata.parser(script: script)

        #expect(metadata.variables.count == 4)
        #expect(metadata.variables[0].name == "VAR_LOCATION")
        #expect(metadata.variables[1].name == "VAR_REFRESH")
        #expect(metadata.variables[2].name == "VAR_EMOJI")
        #expect(metadata.variables[3].name == "VAR_THEME")
    }

    @Test func testVariableParsing_SwiftBarPrefix() throws {
        // SwiftBar should also support swiftbar.var prefix
        let script = """
        #!/bin/bash
        # <swiftbar.var>string(VAR_TEST="value"): Test variable</swiftbar.var>
        """
        let metadata = PluginMetadata.parser(script: script)

        #expect(metadata.variables.count == 1)
        #expect(metadata.variables[0].name == "VAR_TEST")
        #expect(metadata.variables[0].defaultValue == "value")
    }

    @Test func testVariableParsing_DefaultsAddedToEnvironment() throws {
        let script = """
        #!/bin/bash
        # <xbar.var>string(VAR_NAME="John"): Name</xbar.var>
        # <xbar.var>number(VAR_AGE="30"): Age</xbar.var>
        """
        let metadata = PluginMetadata.parser(script: script)

        // Defaults should be added to metadata.environment
        #expect(metadata.environment["VAR_NAME"] == "John")
        #expect(metadata.environment["VAR_AGE"] == "30")
    }

    @Test func testVariableParsing_EmptyDefaultValue() throws {
        let script = """
        #!/bin/bash
        # <xbar.var>string(VAR_OPTIONAL=""): Optional value</xbar.var>
        """
        let metadata = PluginMetadata.parser(script: script)

        #expect(metadata.variables.count == 1)
        #expect(metadata.variables[0].defaultValue == "")
    }
}

struct PluginVariableStorageTests {
    @Test func testVarsFileURL_GeneratesCorrectPath() throws {
        let pluginFile = "/path/to/myplugin.1h.sh"
        let varsURL = PluginVariableStorage.variablesFileURL(forPluginFile: pluginFile)

        #expect(varsURL.path == "/path/to/myplugin.1h.vars.json")
    }

    @Test func testVarsFileURL_HandlesMultipleExtensions() throws {
        let pluginFile = "/plugins/weather.5m.py"
        let varsURL = PluginVariableStorage.variablesFileURL(forPluginFile: pluginFile)

        // Should replace last extension with .vars.json
        #expect(varsURL.path == "/plugins/weather.5m.vars.json")
    }

    @Test func testSaveUserValues_DoesNotEscapeForwardSlashes() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pluginFile = tempDir.appendingPathComponent("repo.1h.sh").path
        let values = ["REPO_PATH": "/Users/bob/git-repos/swiftbar"]

        PluginVariableStorage.saveUserValues(values, pluginFile: pluginFile)

        let varsURL = PluginVariableStorage.variablesFileURL(forPluginFile: pluginFile)
        let data = try Data(contentsOf: varsURL)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"REPO_PATH\":\"/Users/bob/git-repos/swiftbar\""))
        #expect(!json.contains("\\/Users\\/bob\\/git-repos\\/swiftbar"))
    }

    @Test func testBuildEnvironment_UserValuesOverrideDefaults() throws {
        let variables = [
            PluginVariable(type: .string, name: "VAR_LOCATION", defaultValue: "San Francisco", description: "Location"),
            PluginVariable(type: .number, name: "VAR_COUNT", defaultValue: "10", description: "Count"),
        ]
        let userValues = [
            "VAR_LOCATION": "New York",
            "VAR_COUNT": "25",
        ]

        let env = PluginVariableStorage.buildEnvironment(variables: variables, userValues: userValues)

        #expect(env["VAR_LOCATION"] == "New York", "User value should override default")
        #expect(env["VAR_COUNT"] == "25", "User value should override default")
    }

    @Test func testBuildEnvironment_FallbackToDefaults() throws {
        let variables = [
            PluginVariable(type: .string, name: "VAR_A", defaultValue: "default_a", description: "A"),
            PluginVariable(type: .string, name: "VAR_B", defaultValue: "default_b", description: "B"),
        ]
        let userValues = [
            "VAR_A": "custom_a",
            // VAR_B not in user values
        ]

        let env = PluginVariableStorage.buildEnvironment(variables: variables, userValues: userValues)

        #expect(env["VAR_A"] == "custom_a", "User value should be used")
        #expect(env["VAR_B"] == "default_b", "Should fall back to default when user value missing")
    }

    @Test func testBuildEnvironment_EmptyUserValues() throws {
        let variables = [
            PluginVariable(type: .string, name: "VAR_X", defaultValue: "default_x", description: "X"),
            PluginVariable(type: .boolean, name: "VAR_Y", defaultValue: "true", description: "Y"),
        ]
        let userValues: [String: String] = [:]

        let env = PluginVariableStorage.buildEnvironment(variables: variables, userValues: userValues)

        #expect(env["VAR_X"] == "default_x", "Should use default when no user values")
        #expect(env["VAR_Y"] == "true", "Should use default when no user values")
    }

    @Test func testBuildEnvironment_AllVariablesIncluded() throws {
        let variables = [
            PluginVariable(type: .string, name: "VAR_1", defaultValue: "a", description: ""),
            PluginVariable(type: .number, name: "VAR_2", defaultValue: "1", description: ""),
            PluginVariable(type: .boolean, name: "VAR_3", defaultValue: "false", description: ""),
            PluginVariable(type: .select, name: "VAR_4", defaultValue: "opt1", description: "", options: ["opt1", "opt2"]),
        ]
        let userValues = [
            "VAR_1": "b",
            "VAR_3": "true",
        ]

        let env = PluginVariableStorage.buildEnvironment(variables: variables, userValues: userValues)

        #expect(env.count == 4, "All variables should be in environment")
        #expect(env["VAR_1"] == "b")
        #expect(env["VAR_2"] == "1") // default
        #expect(env["VAR_3"] == "true")
        #expect(env["VAR_4"] == "opt1") // default
    }
}

struct PluginVariableIntegrationTests {
    @Test func testFullFlow_ParseAndBuildEnvironment() throws {
        // Simulate full flow: parse script -> get variables -> build environment with user values
        let script = """
        #!/bin/bash
        # <xbar.var>string(VAR_LOCATION="San Francisco"): Location</xbar.var>
        # <xbar.var>number(VAR_REFRESH="5"): Refresh</xbar.var>
        # <xbar.var>boolean(VAR_EMOJI="true"): Emoji</xbar.var>
        # <xbar.var>select(VAR_THEME="light"): Theme. [light, dark, auto]</xbar.var>
        echo "$VAR_LOCATION"
        """

        // Step 1: Parse metadata
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.variables.count == 4)

        // Verify defaults are in metadata.environment
        #expect(metadata.environment["VAR_LOCATION"] == "San Francisco")
        #expect(metadata.environment["VAR_REFRESH"] == "5")
        #expect(metadata.environment["VAR_EMOJI"] == "true")
        #expect(metadata.environment["VAR_THEME"] == "light")

        // Step 2: Simulate user values from .vars.json
        let userValues = [
            "VAR_LOCATION": "New York",
            "VAR_REFRESH": "10",
            "VAR_EMOJI": "false",
            "VAR_THEME": "dark",
        ]

        // Step 3: Build environment (should use user values)
        let env = PluginVariableStorage.buildEnvironment(variables: metadata.variables, userValues: userValues)

        // Step 4: Verify user values override defaults
        #expect(env["VAR_LOCATION"] == "New York", "User value should override default")
        #expect(env["VAR_REFRESH"] == "10", "User value should override default")
        #expect(env["VAR_EMOJI"] == "false", "User value should override default")
        #expect(env["VAR_THEME"] == "dark", "User value should override default")
    }

    @Test func testPartialUserValues_MixedWithDefaults() throws {
        let script = """
        #!/bin/bash
        # <xbar.var>string(VAR_A="default_a"): A</xbar.var>
        # <xbar.var>string(VAR_B="default_b"): B</xbar.var>
        # <xbar.var>string(VAR_C="default_c"): C</xbar.var>
        """

        let metadata = PluginMetadata.parser(script: script)

        // User only customized VAR_B
        let userValues = ["VAR_B": "custom_b"]

        let env = PluginVariableStorage.buildEnvironment(variables: metadata.variables, userValues: userValues)

        #expect(env["VAR_A"] == "default_a", "Should use default")
        #expect(env["VAR_B"] == "custom_b", "Should use user value")
        #expect(env["VAR_C"] == "default_c", "Should use default")
    }
}

// MARK: - Environment Variable Tests (Issues #473, #453)

@Suite(.serialized)
struct EnvironmentVariableTests {
    // Issue #473: SWIFTBAR_PLUGINS_PATH should reflect the current plugin directory,
    // not a stale value captured at Environment init time.
    @Test func testPluginsPathReflectsCurrentPreference() throws {
        let env = Environment.shared

        // Save original value to restore later
        let originalPath = PreferencesStore.shared.pluginDirectoryPath
        defer { PreferencesStore.shared.pluginDirectoryPath = originalPath }

        // Set a known path
        PreferencesStore.shared.pluginDirectoryPath = "/tmp/test-plugins-path"
        let envStr = env.systemEnvStr
        #expect(envStr["SWIFTBAR_PLUGINS_PATH"] == "/tmp/test-plugins-path",
                "SWIFTBAR_PLUGINS_PATH should reflect the current pluginDirectoryPath")

        // Change the path and verify it updates dynamically
        PreferencesStore.shared.pluginDirectoryPath = "/tmp/other-plugins-path"
        let envStr2 = env.systemEnvStr
        #expect(envStr2["SWIFTBAR_PLUGINS_PATH"] == "/tmp/other-plugins-path",
                "SWIFTBAR_PLUGINS_PATH should update when pluginDirectoryPath changes")

    }

    @Test func testPluginsPathHandlesNilDirectory() throws {
        let env = Environment.shared

        let originalPath = PreferencesStore.shared.pluginDirectoryPath
        defer { PreferencesStore.shared.pluginDirectoryPath = originalPath }

        PreferencesStore.shared.pluginDirectoryPath = nil
        let envStr = env.systemEnvStr
        #expect(envStr["SWIFTBAR_PLUGINS_PATH"] == "",
                "SWIFTBAR_PLUGINS_PATH should be empty string when directory is nil")
    }
}

struct RefreshReasonContentSyncTests {
    // Issue #453: When invoke() is called directly (as in refreshAndShowMenu),
    // plugin.content must be updated to prevent subsequent scheduled refreshes
    // from being suppressed by the didSet guard.
    @Test func testContentDidSetGuardSuppressesIdenticalContent() throws {
        // This test demonstrates the mechanism behind issue #453:
        // If plugin.content is "Schedule" and a new invoke() also returns "Schedule",
        // the didSet guard prevents contentUpdatePublisher from firing.

        var publisherFired = false
        let publisher = PassthroughSubject<String?, Never>()
        let cancellable = publisher.sink { _ in
            publisherFired = true
        }

        // Simulate the didSet guard logic from ExecutablePlugin.content
        let oldContent = "Schedule"
        let newContent = "Schedule"
        let lastRefreshReason = PluginRefreshReason.Schedule

        // This mirrors the guard in ExecutablePlugin.content didSet
        let shouldPublish = newContent != oldContent || PluginRefreshReason.manualReasons().contains(lastRefreshReason)

        if shouldPublish {
            publisher.send(newContent)
        }

        #expect(!publisherFired,
                "Publisher should NOT fire when content is identical and reason is Schedule")
        _ = cancellable // keep alive
    }

    @Test func testContentDidSetAllowsChangedContent() throws {
        var publisherFired = false
        let publisher = PassthroughSubject<String?, Never>()
        let cancellable = publisher.sink { _ in
            publisherFired = true
        }

        let oldContent = "MenuOpen"
        let newContent = "Schedule"
        let lastRefreshReason = PluginRefreshReason.Schedule

        let shouldPublish = newContent != oldContent || PluginRefreshReason.manualReasons().contains(lastRefreshReason)

        if shouldPublish {
            publisher.send(newContent)
        }

        #expect(publisherFired,
                "Publisher should fire when content changes")
        _ = cancellable
    }

    @Test func testMenuOpenIsManualReason() throws {
        // MenuOpen should be a manual reason, which forces content update even if content is identical
        #expect(PluginRefreshReason.manualReasons().contains(.MenuOpen),
                "MenuOpen should be in manualReasons so refreshOnOpen always triggers UI updates")
    }
}

struct MenubarItemIncrementalUpdateTests {
    @MainActor
    private func makeMenuBarItem() -> MenubarItem {
        let plugin = TestPlugin(id: "test-plugin", file: "/tmp/test-plugin.5s.sh", content: nil, lastState: .Success)
        let item = MenubarItem(title: "Test")
        item.plugin = plugin
        item.statusBarMenu.delegate = item
        return item
    }

    @MainActor
    private func menuLabels(for item: MenubarItem) -> [String] {
        item.statusBarMenu.items.map { menuItem in
            menuItem.isSeparatorItem ? "<separator>" : (menuItem.attributedTitle?.string ?? menuItem.title)
        }
    }

    @MainActor @Test func testIncrementalUpdate_excludesHiddenBodyRowsFromMenuDiff() throws {
        let item = makeMenuBarItem()

        item._updateMenu(content: """
        Title
        ---
        Visible A
        Hidden | dropdown=false
        Visible B
        """)

        item._updateMenu(content: """
        Title
        ---
        Visible A
        Hidden Changed | dropdown=false
        Visible B Updated
        """)

        #expect(Array(menuLabels(for: item).prefix(4)) == [
            "<separator>",
            "<separator>",
            "Visible A",
            "Visible B Updated",
        ])
    }

    @MainActor @Test func testIncrementalUpdate_rebuildsWhenBodyDisappearsToRemoveExtraSeparator() throws {
        let item = makeMenuBarItem()

        item._updateMenu(content: """
        Title
        ---
        Visible A
        """)

        item._updateMenu(content: "Title")

        #expect(item.statusBarMenu.items[0].isSeparatorItem)
        #expect(!item.statusBarMenu.items[1].isSeparatorItem)
        #expect(item.statusBarMenu.items[1].title == item.swiftBarItem.title)
    }

    @MainActor @Test func testIncrementalUpdate_rebuildsHeaderMenuRowsWhenHeaderChanges() throws {
        let item = makeMenuBarItem()

        item._updateMenu(content: """
        Header A
        Header B
        ---
        Body
        """)

        item._updateMenu(content: """
        Renamed Header
        ---
        Body
        """)

        let labels = menuLabels(for: item)

        #expect(!labels.contains("Header A"))
        #expect(!labels.contains("Header B"))
        #expect(Array(labels.prefix(3)) == [
            "<separator>",
            "<separator>",
            "Body",
        ])
    }

    @MainActor @Test func testIncrementalUpdate_reenablesTitleCycleWhenHeaderIsUnchanged() throws {
        let item = makeMenuBarItem()

        item._updateMenu(content: """
        Header A
        Header B
        ---
        Body
        """)

        let initialTitleCycle = try #require(item.titleCycleCancellable)
        item.disableTitleCycle()

        item._updateMenu(content: """
        Header A
        Header B
        ---
        Body Updated
        """)

        let updatedTitleCycle = try #require(item.titleCycleCancellable)
        #expect(ObjectIdentifier(initialTitleCycle) != ObjectIdentifier(updatedTitleCycle))
    }

    @MainActor @Test func testIncrementalUpdate_restoresBodyShortcuts() throws {
        let item = makeMenuBarItem()

        item._updateMenu(content: """
        Title
        ---
        Visible A | refresh=true
        """)

        item._updateMenu(content: """
        Title
        ---
        Visible A | refresh=true shortcut=cmd+b
        """)

        let bodyItem = item.statusBarMenu.items[2]
        #expect(bodyItem.keyEquivalent == "b")
        #expect(bodyItem.keyEquivalentModifierMask.contains(.command))
        #expect(item.hotKeys.count == 1)
    }

    @MainActor @Test func testFullRebuildWhileMenuIsOpen_reappliesHiddenStandardItems() throws {
        let item = makeMenuBarItem()
        item.plugin?.metadata = PluginMetadata(
            hideRunInTerminal: true,
            hideLastUpdated: true,
            hideDisablePlugin: true,
            hideSwiftBar: true
        )
        item.plugin?.lastUpdated = Date()

        item._updateMenu(content: """
        Title
        ---
        Visible A
        """)

        item.hotkeyTrigger = true
        item.menuWillOpen(item.statusBarMenu)

        #expect(item.lastUpdatedItem.isHidden)
        #expect(item.runInTerminalItem.isHidden)
        #expect(item.disablePluginItem.isHidden)
        #expect(item.swiftBarItem.isHidden)

        item._updateMenu(content: """
        Renamed Title
        ---
        Visible A
        """)

        #expect(item.lastUpdatedItem.isHidden)
        #expect(item.runInTerminalItem.isHidden)
        #expect(item.disablePluginItem.isHidden)
        #expect(item.swiftBarItem.isHidden)
    }

    @MainActor @Test func testIncrementalUpdate_keepsRegeneratedHotKeysPausedWhileMenuIsOpen() throws {
        let item = makeMenuBarItem()

        item._updateMenu(content: """
        Title
        ---
        Visible A | refresh=true shortcut=cmd+b
        """)

        item.hotkeyTrigger = true
        item.menuWillOpen(item.statusBarMenu)

        item._updateMenu(content: """
        Title
        ---
        Visible A Updated | refresh=true shortcut=cmd+b
        """)

        #expect(item.hotKeys.count == 1)
        #expect(item.hotKeys.allSatisfy { $0.isPaused })
    }
}

// MARK: - MenuItemNode Tree Building Tests

struct MenuItemNodeParsingTests {
    @Test func testParseLine_topLevelSeparator() throws {
        let result = MenuItemNode.parseLine("---")
        #expect(result.level == 0)
        #expect(result.isSeparator == true)
        #expect(result.workingLine == "---")
    }

    @Test func testParseLine_plainItem() throws {
        let result = MenuItemNode.parseLine("Hello World | color=red")
        #expect(result.level == 0)
        #expect(result.isSeparator == false)
        #expect(result.workingLine == "Hello World | color=red")
    }

    @Test func testParseLine_nestedItem() throws {
        let result = MenuItemNode.parseLine("--Sub Item | href=https://example.com")
        #expect(result.level == 1)
        #expect(result.isSeparator == false)
        #expect(result.workingLine == "Sub Item | href=https://example.com")
    }

    @Test func testParseLine_deeplyNestedItem() throws {
        let result = MenuItemNode.parseLine("----Deep Item")
        #expect(result.level == 2)
        #expect(result.isSeparator == false)
        #expect(result.workingLine == "Deep Item")
    }

    @Test func testParseLine_nestedSeparator() throws {
        // "-----" = two levels of "--" then "---"
        let result = MenuItemNode.parseLine("-----")
        #expect(result.level == 1)
        #expect(result.isSeparator == true)
        #expect(result.workingLine == "---")
    }

    @Test func testParseLine_tripleNestedSeparator() throws {
        // "-------" = "--" + "--" + "---"
        let result = MenuItemNode.parseLine("-------")
        #expect(result.level == 2)
        #expect(result.isSeparator == true)
        #expect(result.workingLine == "---")
    }
}

struct MenuItemNodeTreeBuildingTests {
    @Test func testBuildMenuTree_emptyInput() throws {
        let tree = MenuItemNode.buildMenuTree(from: [])
        #expect(tree.isEmpty)
    }

    @Test func testBuildMenuTree_flatItems() throws {
        let lines = ["---", "Item A", "Item B", "Item C"]
        let tree = MenuItemNode.buildMenuTree(from: lines)

        #expect(tree.count == 4)
        #expect(tree[0].isSeparator == true)
        #expect(tree[1].workingLine == "Item A")
        #expect(tree[2].workingLine == "Item B")
        #expect(tree[3].workingLine == "Item C")
        #expect(tree.allSatisfy { $0.children.isEmpty })
    }

    @Test func testBuildMenuTree_singleLevelNesting() throws {
        let lines = ["---", "Parent", "--Child 1", "--Child 2"]
        let tree = MenuItemNode.buildMenuTree(from: lines)

        #expect(tree.count == 2) // separator + parent
        #expect(tree[1].workingLine == "Parent")
        #expect(tree[1].children.count == 2)
        #expect(tree[1].children[0].workingLine == "Child 1")
        #expect(tree[1].children[1].workingLine == "Child 2")
    }

    @Test func testBuildMenuTree_multiLevelNesting() throws {
        let lines = [
            "---",
            "Item A",
            "--Sub A1",
            "--Sub A2",
            "----Deep A2a",
            "--Sub A3",
            "Item B",
        ]
        let tree = MenuItemNode.buildMenuTree(from: lines)

        #expect(tree.count == 3) // separator, Item A, Item B
        #expect(tree[2].workingLine == "Item B")
        #expect(tree[2].children.isEmpty)

        let itemA = tree[1]
        #expect(itemA.workingLine == "Item A")
        #expect(itemA.children.count == 3) // Sub A1, Sub A2, Sub A3

        let subA2 = itemA.children[1]
        #expect(subA2.workingLine == "Sub A2")
        #expect(subA2.children.count == 1)
        #expect(subA2.children[0].workingLine == "Deep A2a")
    }

    @Test func testBuildMenuTree_nestedSeparator() throws {
        let lines = ["---", "Parent", "--Child 1", "-----", "--Child 2"]
        let tree = MenuItemNode.buildMenuTree(from: lines)

        let parent = tree[1]
        #expect(parent.children.count == 3)
        #expect(parent.children[0].workingLine == "Child 1")
        #expect(parent.children[1].isSeparator == true)
        #expect(parent.children[1].level == 1)
        #expect(parent.children[2].workingLine == "Child 2")
    }

    @Test func testBuildMenuTree_multipleSeparatorsAtRoot() throws {
        let lines = ["---", "Section 1", "---", "Section 2"]
        let tree = MenuItemNode.buildMenuTree(from: lines)

        #expect(tree.count == 4)
        #expect(tree[0].isSeparator == true)
        #expect(tree[1].workingLine == "Section 1")
        #expect(tree[2].isSeparator == true)
        #expect(tree[3].workingLine == "Section 2")
    }

    @Test func testBuildMenuTree_levelJump() throws {
        // Jump from level 0 to level 2 (skipping level 1)
        // The level 2 item should become a child of the level 0 item,
        // matching the original addMenuItem behavior.
        let lines = ["---", "Item A", "----Deep"]
        let tree = MenuItemNode.buildMenuTree(from: lines)

        #expect(tree.count == 2) // separator, Item A
        let itemA = tree[1]
        #expect(itemA.children.count == 1)
        #expect(itemA.children[0].workingLine == "Deep")
        #expect(itemA.children[0].level == 2)
    }

    @Test func testBuildMenuTree_returnToShallowerAfterJump() throws {
        // Level 0 → level 2 → level 1 should work correctly
        let lines = ["---", "Item A", "----Deep", "--Normal Sub"]
        let tree = MenuItemNode.buildMenuTree(from: lines)

        let itemA = tree[1]
        #expect(itemA.children.count == 2)
        #expect(itemA.children[0].workingLine == "Deep")
        #expect(itemA.children[0].level == 2)
        #expect(itemA.children[1].workingLine == "Normal Sub")
        #expect(itemA.children[1].level == 1)
    }

    @Test func testBuildMenuTree_preservesOriginalLine() throws {
        let lines = ["--Sub Item | color=red"]
        let tree = MenuItemNode.buildMenuTree(from: lines)

        #expect(tree.count == 1)
        #expect(tree[0].line == "--Sub Item | color=red")
        #expect(tree[0].workingLine == "Sub Item | color=red")
    }

    @Test func testBuildMenuTree_excludesHiddenRowsAndKeepsFollowingVisibleItemsAligned() throws {
        let lines = [
            "---",
            "Visible A",
            "Hidden | dropdown=false",
            "Visible B",
        ]
        let tree = MenuItemNode.buildMenuTree(from: lines)

        #expect(tree.count == 3)
        #expect(tree[0].isSeparator == true)
        #expect(tree[1].workingLine == "Visible A")
        #expect(tree[2].workingLine == "Visible B")
    }

    @Test func testBuildMenuTree_skipsHiddenParentsWithoutBreakingVisibleChildren() throws {
        let lines = [
            "---",
            "Parent",
            "--Hidden Parent | dropdown=false",
            "----Visible Grandchild",
            "--Visible Child",
        ]
        let tree = MenuItemNode.buildMenuTree(from: lines)

        let parent = tree[1]
        #expect(parent.children.count == 2)
        #expect(parent.children[0].workingLine == "Visible Grandchild")
        #expect(parent.children[0].level == 2)
        #expect(parent.children[1].workingLine == "Visible Child")
    }
}

// MARK: - MenuDiff Tests

struct MenuDiffTests {
    // Helper to make a simple non-separator node
    func node(_ line: String, children: [MenuItemNode] = []) -> MenuItemNode {
        let (level, isSep, working) = MenuItemNode.parseLine(line)
        return MenuItemNode(line: line, level: level, isSeparator: isSep, workingLine: working, children: children)
    }

    @Test func testDiff_identicalArrays() throws {
        let items = [node("Item A"), node("Item B"), node("Item C")]
        let changes = diffMenuNodes(old: items, new: items)

        #expect(changes.count == 3)
        #expect(changes[0] == .unchanged(oldIndex: 0, newIndex: 0))
        #expect(changes[1] == .unchanged(oldIndex: 1, newIndex: 1))
        #expect(changes[2] == .unchanged(oldIndex: 2, newIndex: 2))
    }

    @Test func testDiff_emptyArrays() throws {
        let changes = diffMenuNodes(old: [], new: [])
        #expect(changes.isEmpty)
    }

    @Test func testDiff_singleItemChanged() throws {
        let old = [node("Item A"), node("Item B"), node("Item C")]
        let new = [node("Item A"), node("Item B Changed"), node("Item C")]
        let changes = diffMenuNodes(old: old, new: new)

        #expect(changes.count == 3)
        #expect(changes[0] == .unchanged(oldIndex: 0, newIndex: 0))
        #expect(changes[1] == .update(oldIndex: 1, newIndex: 1))
        #expect(changes[2] == .unchanged(oldIndex: 2, newIndex: 2))
    }

    @Test func testDiff_itemsAppended() throws {
        let old = [node("Item A")]
        let new = [node("Item A"), node("Item B"), node("Item C")]
        let changes = diffMenuNodes(old: old, new: new)

        #expect(changes.count == 3)
        #expect(changes[0] == .unchanged(oldIndex: 0, newIndex: 0))
        #expect(changes[1] == .insert(newIndex: 1))
        #expect(changes[2] == .insert(newIndex: 2))
    }

    @Test func testDiff_itemsRemoved() throws {
        let old = [node("Item A"), node("Item B"), node("Item C")]
        let new = [node("Item A")]
        let changes = diffMenuNodes(old: old, new: new)

        #expect(changes.count == 3)
        #expect(changes[0] == .unchanged(oldIndex: 0, newIndex: 0))
        // Removals in reverse index order
        #expect(changes[1] == .remove(oldIndex: 2))
        #expect(changes[2] == .remove(oldIndex: 1))
    }

    @Test func testDiff_allChanged() throws {
        let old = [node("Item A"), node("Item B")]
        let new = [node("Item X"), node("Item Y")]
        let changes = diffMenuNodes(old: old, new: new)

        #expect(changes.count == 2)
        #expect(changes[0] == .update(oldIndex: 0, newIndex: 0))
        #expect(changes[1] == .update(oldIndex: 1, newIndex: 1))
    }

    @Test func testDiff_fromEmptyToFull() throws {
        let new = [node("Item A"), node("Item B")]
        let changes = diffMenuNodes(old: [], new: new)

        #expect(changes.count == 2)
        #expect(changes[0] == .insert(newIndex: 0))
        #expect(changes[1] == .insert(newIndex: 1))
    }

    @Test func testDiff_fromFullToEmpty() throws {
        let old = [node("Item A"), node("Item B")]
        let changes = diffMenuNodes(old: old, new: [])

        #expect(changes.count == 2)
        // Reverse order
        #expect(changes[0] == .remove(oldIndex: 1))
        #expect(changes[1] == .remove(oldIndex: 0))
    }

    @Test func testDiff_childrenChangeTriggersUpdate() throws {
        let oldChild = node("--Child A")
        let newChild = node("--Child B")
        let old = [node("Parent", children: [oldChild])]
        let new = [node("Parent", children: [newChild])]
        let changes = diffMenuNodes(old: old, new: new)

        // Parent's deep equality fails because children differ
        #expect(changes.count == 1)
        #expect(changes[0] == .update(oldIndex: 0, newIndex: 0))
    }

    @Test func testDiff_contentEqualWithDifferentChildren() throws {
        let oldChild = node("--Child A")
        let newChild = node("--Child B")
        let oldParent = node("Parent", children: [oldChild])
        let newParent = node("Parent", children: [newChild])

        // Deep equality: different (children differ)
        #expect(oldParent != newParent)
        // Content equality: same (own properties match)
        #expect(oldParent.contentEqual(to: newParent))
    }

    @Test func testDiff_mixedInsertAndRemove() throws {
        let old = [node("Item A"), node("Item B"), node("Item C")]
        let new = [node("Item A"), node("Item B"), node("Item C"), node("Item D")]
        let changes = diffMenuNodes(old: old, new: new)

        #expect(changes.count == 4)
        #expect(changes[0] == .unchanged(oldIndex: 0, newIndex: 0))
        #expect(changes[1] == .unchanged(oldIndex: 1, newIndex: 1))
        #expect(changes[2] == .unchanged(oldIndex: 2, newIndex: 2))
        #expect(changes[3] == .insert(newIndex: 3))
    }
}
