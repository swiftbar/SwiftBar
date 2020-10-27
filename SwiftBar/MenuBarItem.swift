import Cocoa

class MenubarItem {
    var plugin: Plugin?
    let barItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let statusBarMenu = NSMenu(title: "SwiftBar Menu")

    init(title: String, plugin: Plugin? = nil) {
        barItem.button?.title = title
        barItem.menu = statusBarMenu
        self.plugin = plugin
        buildStandardMenu(firstLevel: plugin == nil)
    }

    func setupDefaultMenu() {

    }

    func show() {
        barItem.isVisible = true
    }

    func hide() {
        barItem.isVisible = false
    }
}

// Standard status bar menu
extension MenubarItem {
    func buildStandardMenu(firstLevel: Bool) {
        let menu = firstLevel ? statusBarMenu:NSMenu(title: "Preferences")

        let refreshAllItem = NSMenuItem(title: "Refresh All", action: #selector(refreshPlugins), keyEquivalent: "r")
        let changePluginFolderItem = NSMenuItem(title: "Change Plugin Folder...", action: #selector(changePluginFolder), keyEquivalent: "")
        let openPluginFolderItem = NSMenuItem(title: "Open Plugin Folder...", action: #selector(openPluginFolder), keyEquivalent: "")
        let getPluginsItem = NSMenuItem(title: "Get Plugins...", action: #selector(getPlugins), keyEquivalent: "")
        let aboutItem = NSMenuItem(title: "About", action: #selector(about), keyEquivalent: "")
        let quitItem = NSMenuItem(title: "Quit SwiftBar", action: #selector(quit), keyEquivalent: "q")
        let runInTerminalItem = NSMenuItem(title: "Run in Terminal...", action: #selector(runInTerminal), keyEquivalent: "")
        let disablePluginItem = NSMenuItem(title: "Disable Plugin", action: #selector(disablePlugin), keyEquivalent: "")

        [refreshAllItem,changePluginFolderItem,openPluginFolderItem,getPluginsItem,quitItem,disablePluginItem,aboutItem,runInTerminalItem].forEach{$0.target = self}

        menu.addItem(refreshAllItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(changePluginFolderItem)
        menu.addItem(openPluginFolderItem)
        menu.addItem(getPluginsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(aboutItem)
        menu.addItem(quitItem)

        if !firstLevel {
            // put swiftbar menu as submenu
            let item = NSMenuItem(title: "SwiftBar", action: nil, keyEquivalent: "")
            item.submenu = menu
            statusBarMenu.addItem(item)

            // default plugin menu items
            statusBarMenu.addItem(NSMenuItem.separator())
            statusBarMenu.addItem(runInTerminalItem)
            statusBarMenu.addItem(disablePluginItem)
        }
    }

    @objc func refreshPlugins() {
        App.refreshPlugins()
    }

    @objc func openPluginFolder() {
        App.openPluginFolder()
    }

    @objc func changePluginFolder() {
        App.changePluginFolder()
    }

    @objc func getPlugins() {
        App.getPlugins()
    }

    @objc func quit() {
        NSApp.terminate(self)
    }

    @objc func runInTerminal() {
        plugin?.invoke(params: [])
    }

    @objc func disablePlugin() {
        guard let plugin = plugin else {return}
        PluginManager.shared.disablePlugin(plugin: plugin)
    }

    @objc func about() {
        if let plugin = plugin {
            print(plugin.description)
        }
    }
}


extension MenubarItem {
    static func defaultBarItem() -> MenubarItem {
        let item = MenubarItem(title: "SwiftBar")
        return item
    }
}
