import Cocoa
import os
import Sparkle
import SwiftUI

class AppShared: NSObject {
    public static func openPluginFolder(path: String? = nil) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: Preferences.shared.pluginDirectoryResolvedPath ?? "")
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

        Preferences.shared.pluginDirectoryPath = url.path
        delegate.pluginManager.loadPlugins()
    }

    public static func getPlugins() {
        while Preferences.shared.pluginDirectoryPath == nil {
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
        myWindow.title = Localizable.PluginRepository.PluginRepository.localized
        myWindow.center()

        delegate.repositoryWindowController = NSWindowController(window: myWindow)
        delegate.repositoryWindowController?.contentViewController = NSHostingController(rootView: PluginRepositoryView())
    }

    public static func openPreferences() {
        defer {
            delegate.preferencesWindowController?.showWindow(self)
            delegate.preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        guard delegate.preferencesWindowController == nil else { return }
        let myWindow = AnimatableWindow(
            contentRect: .init(origin: .zero, size: CGSize(width: 400, height: 500)),
            styleMask: [.closable, .miniaturizable, .resizable, .titled],
            backing: .buffered,
            defer: false
        )
        myWindow.title = Localizable.Preferences.Preferences.localized
        myWindow.center()

        delegate.preferencesWindowController = NSWindowController(window: myWindow)
        delegate.preferencesWindowController?.contentViewController = NSHostingController(rootView: PreferencesView().environmentObject(Preferences.shared))
    }

    public static func showAbout() {
        NSApp.orderFrontStandardAboutPanel()
    }

    public static func runInTerminal(script: String, runInBackground: Bool = false, env: [String: String] = [:], runInBash: Bool, completionHandler: ((() -> Void)?) = nil) {
        if runInBackground {
            DispatchQueue.global(qos: .userInitiated).async {
                os_log("Executing script in background... \n%{public}@", log: Log.plugin, script)
                do {
                    try runScript(to: script, env: env, runInBash: runInBash)

                    completionHandler?()
                } catch {
                    guard let error = error as? ShellOutError else { return }
                    os_log("Failed to execute script in background\n%{public}@", log: Log.plugin, type: .error, error.message)
                }
            }
            return
        }

        let runInTerminalScript = getEnvExportString(env: env).appending(";").appending(script)
        var appleScript: String = ""
        switch Preferences.shared.terminal {
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
        }

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: appleScript) {
            if let outputString = scriptObject.executeAndReturnError(&error).stringValue {
                print(outputString)
            } else if let error = error {
                os_log("Failed to execute script in Terminal \n%{public}@", log: Log.plugin, type: .error, error.description)
            }
            completionHandler?()
        }
    }

    public static var isDarkTheme: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") != nil
    }

    public static var isReduceTransparencyEnabled: Bool {
        UserDefaults(suiteName: "com.apple.universalaccess.plist")?.bool(forKey: "reduceTransparency") ?? false
    }

    public static func checkForUpdates() {
        delegate.softwareUpdater.checkForUpdates()
    }
}
