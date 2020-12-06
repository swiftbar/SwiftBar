import Cocoa
import SwiftUI
import ShellOut
import os

class App: NSObject {
    public static func openPluginFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: Preferences.shared.pluginDirectoryPath ?? "")
    }

    public static func changePluginFolder() {
        let dialog = NSOpenPanel()
        dialog.message                 = "Choose plugin folder"
        dialog.showsResizeIndicator    = true
        dialog.showsHiddenFiles        = false
        dialog.canChooseDirectories    = true
        dialog.canChooseFiles          = false
        dialog.canCreateDirectories    = true
        dialog.allowsMultipleSelection = false

        guard dialog.runModal() == .OK,
              let url = dialog.url
        else {return}
        
        let restrictedPaths = FileManager.default.urls(for: .allApplicationsDirectory, in: .allDomainsMask)
        
        if restrictedPaths.contains(url) {
            let alert = NSAlert()
            alert.messageText = "Can't use this folder as SwiftBar plugins location"
            alert.informativeText = "\(url.path)"
            alert.addButton(withTitle: "Choose New Location")
            let modalResult = alert.runModal()

            switch modalResult {
            case .alertFirstButtonReturn:
                App.changePluginFolder()
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
            alert.messageText = "Set SwiftBar Plugins Location"
            alert.informativeText = "Select a folder to store the plugins repository"
            alert.addButton(withTitle: "Ok")
            alert.addButton(withTitle: "Cancel")
            let modalResult = alert.runModal()

            switch modalResult {
            case .alertFirstButtonReturn:
                App.changePluginFolder()
            default:
                return
            }
            
        }
        let preferencesWindowController: NSWindowController?
        let myWindow = NSWindow(
            contentRect: .init(origin: .zero, size: CGSize(width: 400, height: 500)),
            styleMask: [.closable, .miniaturizable, .resizable, .titled],
            backing: .buffered,
            defer: false
        )
        myWindow.title = "Plugin Repository"
        myWindow.center()

        preferencesWindowController = NSWindowController(window: myWindow)
        preferencesWindowController?.contentViewController = NSHostingController(rootView: PluginRepositoryView())
        preferencesWindowController?.showWindow(self)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public static func openPreferences() {
        let preferencesWindowController: NSWindowController?
        let myWindow = NSWindow(
            contentRect: .init(origin: .zero, size: CGSize(width: 400, height: 500)),
            styleMask: [.closable, .miniaturizable, .resizable, .titled],
            backing: .buffered,
            defer: false
        )
        myWindow.title = "Preferences"
        myWindow.center()

        preferencesWindowController = NSWindowController(window: myWindow)
        preferencesWindowController?.contentViewController = NSHostingController(rootView: PreferencesView().environmentObject(Preferences.shared))
        preferencesWindowController?.showWindow(self)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public static func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [:])
    }

    public static func runInTerminal(script: String, runInBackground: Bool = false, completionHandler: ((() -> Void)?) = nil) {
        if runInBackground {
            DispatchQueue.global(qos: .userInitiated).async {
                os_log("Executing script in background... \n%{public}@", log: Log.plugin, script)
                do {
                    try runScript(to: script)
                    completionHandler?()
                } catch {
                    guard let error = error as? ShellOutError else {return}
                    os_log("Failed to execute script in background\n%{public}@", log: Log.plugin, type:.error, error.message)
                }
            }
            return
        }
        var appleScript: String = ""
        switch Preferences.shared.terminal {
            case .Terminal:
                appleScript = """
                tell application "Terminal"
                    do script "\(script)" in front window
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
                        tell current session to write text "\(script)"
                    end tell
                end tell
                """
        }

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: appleScript) {
            if let outputString = scriptObject.executeAndReturnError(&error).stringValue {
                print(outputString)
            } else if let error = error {
                os_log("Failed to execute script in Terminal \n%{public}@", log: Log.plugin, type:.error, error.description)
            }
            completionHandler?()
        }
    }
}
