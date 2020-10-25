import Cocoa

class MenubarItem {
    let barItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let statusBarMenu = NSMenu(title: "SwiftBar Menu")

    init(title: String, noPlugins: Bool = false) {
        barItem.button?.title = title
        barItem.menu = statusBarMenu
        buildStandardMenu(submenu: noPlugins)
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
    func buildStandardMenu(submenu: Bool) {
        let menu = submenu ? statusBarMenu:NSMenu(title: "Preferences")

        let refreshAll = NSMenuItem(title: "Refresh All", action: #selector(refreshPlugins), keyEquivalent: "r")
        let changePluginFolder = NSMenuItem(title: "Change Plugin Folder...", action: nil, keyEquivalent: "")
        let openPluginFolder = NSMenuItem(title: "Open Plugin Folder...", action: nil, keyEquivalent: "")
        let getPlugins = NSMenuItem(title: "Get Plugins...", action: nil, keyEquivalent: "")
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")

        [refreshAll,changePluginFolder,openPluginFolder,getPlugins,quitItem].forEach{$0.target = self}

        menu.addItem(refreshAll)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(changePluginFolder)
        menu.addItem(openPluginFolder)
        menu.addItem(getPlugins)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)

        if !submenu {
            let item = NSMenuItem(title: "Preferences", action: nil, keyEquivalent: "")
            item.submenu = menu
            statusBarMenu.addItem(item)
        }
    }

    @objc func refreshPlugins() {
        PluginManager.shared.addDummyPlugin()
    }

    @objc func quit() {
        NSApp.terminate(self)
    }
}


extension MenubarItem {
    static func defaultBarItem() -> MenubarItem {
        let item = MenubarItem(title: "SwiftBar", noPlugins: true)
        return item
    }
}
