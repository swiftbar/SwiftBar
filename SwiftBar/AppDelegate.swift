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
import AppCenter
import AppCenterCrashes

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
    let sharedEnv = Environment.shared
    #if !MAC_APP_STORE
        var softwareUpdater: SPUUpdater!
    #endif

    func applicationDidFinishLaunching(_: Notification) {
        if prefs.collectCrashReports {
            // Not cool to have the KEY here, but since this is for crash reporting I don't care
            AppCenter.start(withAppSecret: "40e6c2fa-2383-40a7-bfbd-75662a7d92a9", services: [
                Crashes.self,
            ])
            Crashes.notify(with: .send)
        }
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

        setDefaultShelf()
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
                                                          queue: OperationQueue.main)
        { [weak self] _ in
            os_log("Mac is going to sleep", log: Log.plugin, type: .info)
            self?.sharedEnv.updateSleepTime(date: NSDate.now)
            self?.pluginManager.terminateAllPlugins()
        }

        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                          object: nil,
                                                          queue: OperationQueue.main)
        { [weak self] _ in
            os_log("Mac waked up", log: Log.plugin, type: .info)
            self?.sharedEnv.updateWakeTime(date: NSDate.now)
            self?.pluginManager.startAllPlugins()
        }
    }

    func setDefaultShelf() {
        let out = try? runScript(to: "echo", args: ["$SHELL"])
        if let shell = out?.out, shell != "" {
            sharedEnv.userLoginShell = shell.trimmingCharacters(in: .newlines)
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

    func getPluginFromURL(url: URL) -> Plugin? {
        guard let identifier = url.queryParameters?["plugin"] ?? url.queryParameters?["name"] else { return nil }
        return pluginManager.getPluginByNameOrID(identifier: identifier)
    }

    func feedURLString(for _: SPUUpdater) -> String? {
        if prefs.includeBetaUpdates {
            return "https://swiftbar.github.io/SwiftBar/appcast-beta.xml"
        }
        return "https://swiftbar.github.io/SwiftBar/appcast.xml"
    }

    func application(_: NSApplication, open urls: [URL]) {
        for url in urls {
            switch url.host?.lowercased() {
            case "refreshallplugins":
                pluginManager.refreshAllPlugins(reason: .RefreshAllURLScheme)
            case "refreshplugin":
                if let plugin = getPluginFromURL(url: url) {
                    pluginManager.menuBarItems[plugin.id]?.dimOnManualRefresh()
                    if let params = url.queryParameters {
                        plugin.refreshEnv = params.filter { $0.key != "name" }
                    }
                    plugin.refresh(reason: .URLScheme)
                    return
                }
                if let indexStr = url.queryParameters?["index"], let index = Int(indexStr) {
                    pluginManager.refreshPlugin(with: index, reason: .URLScheme)
                    return
                }
            case "disableplugin":
                if let plugin = getPluginFromURL(url: url) {
                    pluginManager.disablePlugin(plugin: plugin)
                }
            case "enableplugin":
                if let plugin = getPluginFromURL(url: url) {
                    pluginManager.enablePlugin(plugin: plugin)
                }
            case "toggleplugin":
                if let plugin = getPluginFromURL(url: url) {
                    pluginManager.togglePlugin(plugin: plugin)
                }
            case "addplugin":
                if let src = url.queryParameters?["src"], let url = URL(string: src) {
                    pluginManager.importPlugin(from: url)
                }
            case "setephemeralplugin":
                if let name = url.queryParameters?["name"],
                   case let pluginContent = url.queryParameters?["content"] ?? "",
                   let exitAfter = Double(url.queryParameters?["exitafter"] ?? "0")
                {
                    pluginManager.setEphemeralPlugin(pluginId: name, content: pluginContent, exitAfter: exitAfter)
                }
            case "notify":
                guard let plugin = getPluginFromURL(url: url) else { return }
                let paramsString = url.queryParameters?.map { "\($0.key)=\($0.value.escaped())" }.joined(separator: " ") ?? ""
                pluginManager.showNotification(plugin: plugin,
                                               title: url.queryParameters?["title"]?.replacingOccurrences(of: "+", with: " "),
                                               subtitle: url.queryParameters?["subtitle"]?.replacingOccurrences(of: "+", with: " "),
                                               body: url.queryParameters?["body"]?.replacingOccurrences(of: "+", with: " "),
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
                                    env: plugin.env, runInBash: plugin.metadata?.shouldRunInBash ?? true)
            {
                if params.refresh {
                    plugin.refresh(reason: .NotificationAction)
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
