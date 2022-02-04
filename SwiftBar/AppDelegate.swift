import Cocoa
import os
import Preferences
import UserNotifications
#if MAC_APP_STORE
    protocol SPUStandardUserDriverDelegate {}
    protocol SPUUpdaterDelegate {}
#else
    import Sparkle
#endif

class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate, SPUUpdaterDelegate, UNUserNotificationCenterDelegate, NSWindowDelegate {
    var repositoryWindowController: NSWindowController? {
        didSet {
            repositoryWindowController?.window?.delegate = self
        }
    }

    lazy var preferencesWindowController = PreferencesWindowController(
        panes: preferencePanes,
        style: .toolbarItems
    )

    var repositoryToolbarSearchItem: NSToolbarItem?

    var pluginManager: PluginManager!
    let prefs = PreferencesStore.shared
    #if !MAC_APP_STORE
        var softwareUpdater: SPUUpdater!
    #endif

    func applicationDidFinishLaunching(_: Notification) {
        preferencesWindowController.window?.delegate = self
        setupToolbar()
        let hostBundle = Bundle.main
        #if !MAC_APP_STORE
            let updateDriver = SPUStandardUserDriver(hostBundle: hostBundle, delegate: self)
            softwareUpdater = SPUUpdater(hostBundle: hostBundle, applicationBundle: hostBundle, userDriver: updateDriver, delegate: self)

            do {
                try softwareUpdater.start()
            } catch {
                NSLog("Failed to start software updater with error: \(error)")
            }
        #endif

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

        while PreferencesStore.shared.pluginDirectoryPath == nil {
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

        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
                                                          object: nil,
                                                          queue: OperationQueue.main) { [weak self] _ in
            os_log("Mac is going to sleep", log: Log.plugin, type: .info)
            self?.pluginManager.terminateAllPlugins()
        }

        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                          object: nil,
                                                          queue: OperationQueue.main) { [weak self] _ in
            os_log("Mac waked up", log: Log.plugin, type: .info)
            self?.pluginManager.startAllPlugins()
        }
    }

    func changePresentationType() {
        if preferencesWindowController.window?.isVisible != true && repositoryWindowController?.window?.isVisible != true {
            NSApp.setActivationPolicy(.accessory)
            return
        }

        if preferencesWindowController.window != nil || repositoryWindowController?.window != nil {
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
            case "disableplugin":
                if let name = url.queryParameters?["name"] {
                    pluginManager.disablePlugin(named: name)
                }
            case "enableplugin":
                if let name = url.queryParameters?["name"] {
                    pluginManager.enablePlugin(named: name)
                }
            case "toggleplugin":
                if let name = url.queryParameters?["name"] {
                    pluginManager.togglePlugin(named: name)
                }
            case "addplugin":
                if let src = url.queryParameters?["src"], let url = URL(string: src) {
                    pluginManager.importPlugin(from: url)
                }
            case "notify":
                guard let pluginID = url.queryParameters?["plugin"] else { return }
                let paramsString = url.queryParameters?.map { "\($0.key)=\($0.value)" }.joined(separator: " ") ?? ""
                pluginManager.showNotification(pluginID: pluginID,
                                               title: url.queryParameters?["title"],
                                               subtitle: url.queryParameters?["subtitle"],
                                               body: url.queryParameters?["body"],
                                               href: url.queryParameters?["href"],
                                               commandParams: MenuLineParameters(line: "|\(paramsString)").json,
                                               silent: url.queryParameters?["silent"] == "true")
            default:
                os_log("Unsupported URL scheme \n %{public}@", log: Log.plugin, type: .error, url.absoluteString)
            }
        }
    }

    func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let payload = response.notification.request.content.userInfo

        guard let pluginID = payload[SystemNotificationName.pluginID] as? String,
              let plugin = pluginManager.plugins.first(where: { $0.id == pluginID }),
              plugin.enabled else { return }

        if let urlString = payload[SystemNotificationName.url] as? String,
           let url = URL(string: urlString)
        {
            NSWorkspace.shared.open(url)
        }

        if let commandString = payload[SystemNotificationName.command] as? String,
           let json = commandString.data(using: .utf8), let params = MenuLineParameters(json: json),
           let bash = params.bash
        {
            AppShared.runInTerminal(script: bash, args: params.bashParams, runInBackground: !params.terminal,
                                    env: plugin.env, runInBash: plugin.metadata?.shouldRunInBash ?? true) {
                if params.refresh {
                    plugin.refresh()
                }
            }
        }

        completionHandler()
    }

    func windowWillClose(_: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.changePresentationType()
        }
    }
}
