import Cocoa
import os
import SwiftUI

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

        let runInTerminalScript = getEnvExportString(env: env).appending(";")
            .appending(script.escaped())
            .appending(" ")
            .appending(args.joined(separator: " "))
        var appleScript = ""
        switch PreferencesStore.shared.terminal {
        case .Terminal:
            appleScript = """
            tell application "Terminal"
                activate
                tell application "System Events" to keystroke "t" using {command down}
                delay 0.2
                do script "\(runInTerminalScript)" in front window
                activate
            end tell
            """
        case .iTerm:
            appleScript = """
            tell application "iTerm"
                activate
                try
                    select first window
                    set onlywindow to false
                on error
                    create window with default profile
                    select first window
                    set onlywindow to true
                end try
                tell the first window
                    if onlywindow is false then
                        create tab with default profile
                    end if
                    tell current session to write text "\(runInTerminalScript)"
                end tell
            end tell
            """
        case .Ghostty:
            appleScript = """
            tell application "Ghostty"
                activate
                tell application "System Events"
                    keystroke "n" using {command down}
                    delay 0.2
                end tell
                tell application "System Events" to tell process "Ghostty"
                    keystroke "\(runInTerminalScript)"
                    keystroke return
                end tell
            end tell
            """
        }

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

    public static var isDarkTheme: Bool {
        if #available(macOS 15.0, *) {
            NSApplication.shared.effectiveAppearance.name.rawValue.contains("Dark")
        else
            UserDefaults.standard.string(forKey: "AppleInterfaceStyle") != nil
    }

    public static var isDarkStatusBar: Bool {
        let currentAppearance = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength).button?.effectiveAppearance
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
