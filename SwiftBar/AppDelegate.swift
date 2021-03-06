import Cocoa
import os
import Sparkle
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate, SPUUpdaterDelegate, UNUserNotificationCenterDelegate, NSWindowDelegate {
    var preferencesWindowController: NSWindowController? {
        didSet {
            preferencesWindowController?.window?.delegate = self
        }
    }

    var repositoryWindowController: NSWindowController? {
        didSet {
            repositoryWindowController?.window?.delegate = self
        }
    }

    var pluginManager: PluginManager!
    let prefs = Preferences.shared
    var softwareUpdater: SPUUpdater!

    func applicationDidFinishLaunching(_: Notification) {
        let hostBundle = Bundle.main
        let updateDriver = SPUStandardUserDriver(hostBundle: hostBundle, delegate: self)
        softwareUpdater = SPUUpdater(hostBundle: hostBundle, applicationBundle: hostBundle, userDriver: updateDriver, delegate: self)

        do {
            try softwareUpdater.start()
        } catch {
            NSLog("Failed to start software updater with error: \(error)")
        }

        // Check if plugin folder exists
        var isDir: ObjCBool = false
        if let pluginDirectoryPath = prefs.pluginDirectoryResolvedPath,
           !FileManager.default.fileExists(atPath: pluginDirectoryPath, isDirectory: &isDir) || !isDir.boolValue
        {
            prefs.pluginDirectoryPath = nil
        }

        // Instance of Plugin Manager must be created after app launch
        pluginManager = PluginManager.shared
        pluginManager.loadPlugins()

        while Preferences.shared.pluginDirectoryPath == nil {
            let alert = NSAlert()
            alert.messageText = Localizable.App.ChoosePluginFolderMessage.localized
            alert.informativeText = Localizable.App.ChoosePluginFolderInfo.localized
            alert.addButton(withTitle: Localizable.App.OKButton.localized)
            alert.addButton(withTitle: Localizable.App.Quit.localized)
            let modalResult = alert.runModal()

            switch modalResult {
            case .alertFirstButtonReturn:
                AppShared.changePluginFolder()
            default:
                NSApplication.shared.terminate(self)
            }
        }

        NotificationCenter.default.addObserver(forName: NSWorkspace.willSleepNotification,
                                               object: nil,
                                               queue: OperationQueue.main) { [weak self] _ in
            self?.pluginManager.terminateAllPlugins()
        }

        NotificationCenter.default.addObserver(forName: NSWorkspace.didWakeNotification,
                                               object: nil,
                                               queue: OperationQueue.main) { [weak self] _ in
            self?.pluginManager.refreshAllPlugins()
        }
        AppShared.getPlugins()
    }

    func changePresentationType() {
        if preferencesWindowController?.window?.isVisible != true && repositoryWindowController?.window?.isVisible != true {
            NSApp.setActivationPolicy(.accessory)
            return
        }

        if preferencesWindowController?.window != nil || repositoryWindowController?.window != nil {
            NSApp.setActivationPolicy(.regular)
            return
        }
    }

    func applicationWillTerminate(_: Notification) {
        pluginManager.terminateAllPlugins()
    }

    func application(_: NSApplication, open urls: [URL]) {
        for url in urls {
            switch url.host?.lowercased() {
            case "refreshallplugins":
                pluginManager.refreshAllPlugins()
            case "refreshplugin":
                if let name = url.queryParameters?["name"] {
                    pluginManager.refreshPlugin(named: name)
                    return
                }
                if let indexStr = url.queryParameters?["index"], let index = Int(indexStr) {
                    pluginManager.refreshPlugin(with: index)
                    return
                }
            case "addplugin":
                if let src = url.queryParameters?["src"], let url = URL(string: src) {
                    pluginManager.importPlugin(from: url)
                }
            case "notify":
                guard let pluginID = url.queryParameters?["plugin"] else { return }
                pluginManager.showNotification(pluginID: pluginID,
                                               title: url.queryParameters?["title"],
                                               subtitle: url.queryParameters?["subtitle"],
                                               body: url.queryParameters?["body"],
                                               silent: url.queryParameters?["silent"] == "true")
            default:
                os_log("Unsupported URL scheme \n %{public}@", log: Log.plugin, type: .error, url.absoluteString)
            }
        }
    }

    func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
    {
        completionHandler([.alert, .sound])
    }

    func windowWillClose(_: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.changePresentationType()
        }
    }
}
