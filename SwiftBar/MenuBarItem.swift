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

        let refreshAll = NSMenuItem(title: "Refresh All", action: #selector(refreshPlugins), keyEquivalent: "r")
        let changePluginFolder = NSMenuItem(title: "Change Plugin Folder...", action: nil, keyEquivalent: "")
        let openPluginFolder = NSMenuItem(title: "Open Plugin Folder...", action: nil, keyEquivalent: "")
        let getPlugins = NSMenuItem(title: "Get Plugins...", action: nil, keyEquivalent: "")
        let quitItem = NSMenuItem(title: "Quit SwiftBar", action: #selector(quit), keyEquivalent: "q")
        let disablePluginItem = NSMenuItem(title: "Disable Plugin", action: #selector(disablePlugin), keyEquivalent: "")

        [refreshAll,changePluginFolder,openPluginFolder,getPlugins,quitItem,disablePluginItem].forEach{$0.target = self}

        menu.addItem(refreshAll)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(changePluginFolder)
        menu.addItem(openPluginFolder)
        menu.addItem(getPlugins)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)

        if !firstLevel {
            let item = NSMenuItem(title: "SwiftBar", action: nil, keyEquivalent: "")
            item.submenu = menu
            statusBarMenu.addItem(item)
            statusBarMenu.addItem(NSMenuItem.separator())
            statusBarMenu.addItem(disablePluginItem)
        }
    }

    @objc func refreshPlugins() {
        PluginManager.shared.addDummyPlugin()
    }

    @objc func quit() {
        NSApp.terminate(self)
    }

    @objc func disablePlugin() {
        guard let plugin = plugin else {return}
        PluginManager.shared.disablePlugin(plugin: plugin)
    }
}


extension MenubarItem {
    static func defaultBarItem() -> MenubarItem {
        let item = MenubarItem(title: "SwiftBar")
        return item
    }
}
