import Cocoa
import os
import SwiftUI

private let kittyBundleIdentifier = "net.kovidgoyal.kitty"

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
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: PreferencesStore.shared.pluginDirectoryResolvedPath ?? "")
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

        let appleScript = buildTerminalAppleScript(command: runInTerminalScript, terminal: PreferencesStore.shared.terminal)

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: appleScript) {
            if let outputString = scriptObject.executeAndReturnError(&error).stringValue {
                print(outputString)
            } else if let error {
                os_log("Failed to execute script in Terminal \n%{public}@", log: Log.plugin, type: .error, error.description)
            }
            completionHandler?()
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

    public static var isDarkStatusBar: Bool {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let currentAppearance = item.button?.effectiveAppearance
        NSStatusBar.system.removeStatusItem(item)
        return currentAppearance?.bestMatch(from: [.aqua, .darkAqua]) == .aqua
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
