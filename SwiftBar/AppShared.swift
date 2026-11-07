import Cocoa
import os
import SwiftUI

private let kittyBundleIdentifier = "net.kovidgoyal.kitty"

struct PreparedTerminalCommand {
    let command: String
    let temporaryDirectory: URL?
}

/// Terminal may accept a command before its login shell leaves canonical input
/// mode, where a line is limited to 1024 bytes. Source a private file for long
/// commands so neither environment exports nor arguments are truncated.
func prepareTerminalCommand(_ command: String, in temporaryDirectory: URL = FileManager.default.temporaryDirectory) throws -> PreparedTerminalCommand {
    guard command.utf8.count >= 900 else {
        return PreparedTerminalCommand(command: command, temporaryDirectory: nil)
    }
    let directory = temporaryDirectory.appendingPathComponent("swiftbar-terminal-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                          attributes: [.posixPermissions: 0o700])
    do {
        let file = directory.appendingPathComponent("command")
        // Source keeps the user's current shell and environment semantics. The
        // open file remains readable after unlinking; cleanup precedes the user
        // command so even exec/exit and a failed command leave no private data.
        let source = "/bin/rm -- \(file.path.quoteIfNeeded())\n/bin/rmdir -- \(directory.path.quoteIfNeeded())\n\(command)\n"
        try source.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return PreparedTerminalCommand(command: "source \(file.path.quoteIfNeeded())", temporaryDirectory: directory)
    } catch {
        try? FileManager.default.removeItem(at: directory)
        throw error
    }
}

func buildTerminalAppleScript(command: String, terminal: TerminalOptions) -> String {
    let escapedCommand = command.appleScriptEscaped()

    switch terminal {
    case .Terminal:
        return """
        tell application "Terminal"
            activate
            if (count of windows) is 0 then
                do script "\(escapedCommand)"
            else
                tell application "System Events" to keystroke "t" using {command down}
                delay 0.1
                do script "\(escapedCommand)" in selected tab of front window
            end if
            activate
        end tell
        """
    case .iTerm:
        return """
        tell application "iTerm"
            activate
            if (count of windows) is 0 then
                create window with default profile
            else
                tell current window
                    create tab with default profile
                end tell
            end if
            tell current session of current tab of current window to write text "\(escapedCommand)"
        end tell
        """
    case .Ghostty:
        return """
        tell application "Ghostty"
            activate
            try
                set ghosttyWindow to front window
                set ghosttyTab to new tab in ghosttyWindow
                set ghosttyTerminal to focused terminal of ghosttyTab
            on error
                set ghosttyWindow to new window
                set ghosttyTerminal to focused terminal of selected tab of ghosttyWindow
            end try
            input text "\(escapedCommand)" to ghosttyTerminal
            send key "enter" to ghosttyTerminal
        end tell
        """
    case .Kitty:
        assertionFailure("Kitty should be handled via runInKitty(), not AppleScript")
        return ""
    }
}

func buildKittyLaunchArguments(command: String, loginShell: String) -> [String] {
    let shellPath = loginShell.lowercased()
    let shellArgs = if shellPath.hasSuffix("tcsh") || shellPath.hasSuffix("csh") {
        ["-c", command]
    } else {
        ["-lc", command]
    }

    return ["--single-instance", loginShell] + shellArgs
}

func kittyExecutableURL(workspace: NSWorkspace = .shared) -> URL? {
    if let appURL = workspace.urlForApplication(withBundleIdentifier: kittyBundleIdentifier) {
        let executableURL = appURL.appendingPathComponent("Contents/MacOS/kitty")
        if FileManager.default.isExecutableFile(atPath: executableURL.path) {
            return executableURL
        }
    }

    let fallbackPaths = [
        "/Applications/kitty.app/Contents/MacOS/kitty",
        "/Applications/Kitty.app/Contents/MacOS/kitty",
        "/opt/homebrew/bin/kitty",
        "/usr/local/bin/kitty",
    ]

    for path in fallbackPaths where FileManager.default.isExecutableFile(atPath: path) {
        return URL(fileURLWithPath: path)
    }

    return nil
}

class AppShared: NSObject {
    public static func openPluginFolder(path: String? = nil) {
        let pluginDirectoryPath = PreferencesStore.shared.pluginDirectoryResolvedPath
        // A custom file viewer (NSFileViewer) gets no folder path when nothing is selected, only a reopen event.
        if path == nil, let pluginDirectoryPath, UserDefaults.standard.string(forKey: "NSFileViewer")?.isEmpty == false {
            NSWorkspace.shared.selectFile(pluginDirectoryPath, inFileViewerRootedAtPath: "")
        } else {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: pluginDirectoryPath ?? "")
        }
    }

    public static func changePluginFolder() {
        let dialog = NSOpenPanel()
        dialog.message = Localizable.App.ChoosePluginFolderTitle.localized
        dialog.showsResizeIndicator = true
        dialog.showsHiddenFiles = false
        dialog.canChooseDirectories = true
        dialog.canChooseFiles = false
        dialog.canCreateDirectories = true
        dialog.allowsMultipleSelection = false

        guard dialog.runModal() == .OK,
              let url = dialog.url
        else { return }

        var restrictedPaths =
            [FileManager.SearchPathDirectory.allApplicationsDirectory, .documentDirectory, .downloadsDirectory, .desktopDirectory, .libraryDirectory, .developerDirectory, .userDirectory, .musicDirectory, .moviesDirectory,
             .picturesDirectory]
            .map { FileManager.default.urls(for: $0, in: .allDomainsMask) }
            .flatMap { $0 }

        restrictedPaths.append(FileManager.default.homeDirectoryForCurrentUser)

        if restrictedPaths.contains(url) {
            let alert = NSAlert()
            alert.messageText = Localizable.App.FolderNotAllowedMessage.localized
            alert.informativeText = "\(url.path)"
            alert.addButton(withTitle: Localizable.App.FolderNotAllowedAction.localized)
            let modalResult = alert.runModal()

            switch modalResult {
            case .alertFirstButtonReturn:
                AppShared.changePluginFolder()
            default:
                break
            }
            return
        }

        PreferencesStore.shared.pluginDirectoryPath = url.path
        delegate.pluginManager.terminateAllPlugins()
        delegate.pluginManager.loadPlugins()
        delegate.pluginManager.persistLatestSystemReport(reason: "plugin-folder-changed")
    }

    public static func getPlugins() {
        while PreferencesStore.shared.pluginDirectoryPath == nil {
            let alert = NSAlert()
            alert.messageText = Localizable.App.ChoosePluginFolderMessage.localized
            alert.informativeText = Localizable.App.ChoosePluginFolderInfo.localized
            alert.addButton(withTitle: Localizable.App.OKButton.localized)
            alert.addButton(withTitle: Localizable.App.CancelButton.localized)
            let modalResult = alert.runModal()

            switch modalResult {
            case .alertFirstButtonReturn:
                AppShared.changePluginFolder()
            default:
                return
            }
        }

        defer {
            NSApp.setActivationPolicy(.regular)
            delegate.repositoryWindowController?.showWindow(self)
            delegate.repositoryWindowController?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        guard delegate.repositoryWindowController == nil else { return }

        let myWindow = NSWindow(
            contentRect: .init(origin: .zero, size: CGSize(width: 400, height: 500)),
            styleMask: [.closable, .miniaturizable, .resizable, .titled],
            backing: .buffered,
            defer: false
        )
        myWindow.toolbar = .repositoryToolbar
        myWindow.title = Localizable.PluginRepository.PluginRepository.localized
        myWindow.center()

        delegate.repositoryWindowController = NSWindowController(window: myWindow)
        delegate.repositoryWindowController?.contentViewController = NSHostingController(rootView: PluginRepositoryView())
    }

    public static func refreshRepositoryData() {
        PluginRepository.shared.refreshRepositoryData(ignoreCache: true)
    }

    public static func openPreferences() {
        NSApp.setActivationPolicy(.regular)
        delegate.preferencesWindowController.show()
    }

    public static func showAbout() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        NSApp.orderFrontStandardAboutPanel()
    }

    public static func showPluginDebug(plugin: Plugin) {
        let myWindow = AnimatableWindow(
            contentRect: .init(origin: .zero, size: CGSize(width: 400, height: 500)),
            styleMask: [.closable, .miniaturizable, .resizable, .titled],
            backing: .buffered,
            defer: false
        )
        myWindow.title = "Plugin Debug"
        myWindow.center()

        let windowController = NSWindowController(window: myWindow)
        windowController.contentViewController = NSHostingController(rootView: DebugView(plugin: plugin, debugInfo: plugin.debugInfo))
        windowController.showWindow(self)
        windowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public static func runInTerminal(script: String, args: [String] = [], runInBackground: Bool = false, env: [String: String] = [:], runInBash: Bool, completionHandler: (() -> Void)? = nil) {
        if runInBackground {
            DispatchQueue.global(qos: .userInitiated).async {
                os_log("Executing script in background... \n%{public}@", log: Log.plugin, script)
                do {
                    try runScript(to: script, args: args, env: env, runInBash: runInBash)

                    completionHandler?()
                } catch {
                    guard let error = error as? ShellOutError else { return }
                    os_log("Failed to execute script in background\n%{public}@", log: Log.plugin, type: .error, error.message)
                }
            }
            return
        }

        let runInTerminalScript = buildTerminalCommand(script: script, args: args, env: env)
        if PreferencesStore.shared.terminal == .Kitty {
            runInKitty(command: runInTerminalScript, completionHandler: completionHandler)
            return
        }

        let terminal = PreferencesStore.shared.terminal
        let prepared: PreparedTerminalCommand
        do {
            prepared = terminal == .Terminal ? try prepareTerminalCommand(runInTerminalScript) :
                PreparedTerminalCommand(command: runInTerminalScript, temporaryDirectory: nil)
        } catch {
            os_log("Failed to prepare Terminal command: %{public}@", log: Log.plugin, type: .error, error.localizedDescription)
            return
        }
        let appleScript = buildTerminalAppleScript(command: prepared.command, terminal: terminal)

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: appleScript) {
            if let outputString = scriptObject.executeAndReturnError(&error).stringValue {
                print(outputString)
            } else if let error {
                if let directory = prepared.temporaryDirectory { try? FileManager.default.removeItem(at: directory) }
                os_log("Failed to execute script in Terminal \n%{public}@", log: Log.plugin, type: .error, error.description)
            }
            completionHandler?()
        } else if let directory = prepared.temporaryDirectory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static func runInKitty(command: String, completionHandler: (() -> Void)? = nil) {
        guard let executableURL = kittyExecutableURL() else {
            os_log("Failed to locate Kitty executable", log: Log.plugin, type: .error)
            return
        }

        let loginShell = sharedEnv.userLoginShell.isEmpty ? "/bin/zsh" : sharedEnv.userLoginShell
        let process = Process()
        process.executableURL = executableURL
        process.arguments = buildKittyLaunchArguments(command: command, loginShell: loginShell)

        do {
            try process.run()
            completionHandler?()
        } catch {
            os_log("Failed to execute script in Kitty \n%{public}@", log: Log.plugin, type: .error, String(describing: error))
        }
    }

    public static var isDarkTheme: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") != nil
    }

    public static func isDarkStatusBar(appearance: NSAppearance?) -> Bool {
        appearance?.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    public static var isReduceTransparencyEnabled: Bool {
        UserDefaults(suiteName: "com.apple.universalaccess.plist")?.bool(forKey: "reduceTransparency") ?? false
    }

    public static var cacheDirectory: URL? {
        guard let bundleName = Bundle.main.bundleIdentifier,
              let url = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
              .appendingPathComponent(bundleName)
              .appendingPathComponent("Plugins")
        else {
            return nil
        }
        return url
    }

    public static var dataDirectory: URL? {
        guard let appName = Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String,
              let url = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
              .appendingPathComponent(appName)
              .appendingPathComponent("Plugins")
        else {
            return nil
        }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: nil)
        return url
    }

    public static func checkForUpdates() {
        #if !MAC_APP_STORE
            delegate.softwareUpdater.checkForUpdates()
        #endif
    }
}
