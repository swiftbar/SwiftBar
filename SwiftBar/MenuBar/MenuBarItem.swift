import Cocoa
import Combine

class MenubarItem: NSObject {
    var plugin: Plugin?
    let barItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let statusBarMenu = NSMenu(title: "SwiftBar Menu")
    let titleCylleInterval: Double = 5
    var contentUpdateCancellable: AnyCancellable? = nil
    var titleCycleCancellable: AnyCancellable? = nil
    let lastUpdatedMenuItem = NSMenuItem(title: "Updating...", action: nil, keyEquivalent: "")

    var titleLines: [String] = [] {
        didSet {
            currentTitleLine = -1
            guard titleLines.count > 1 else {
                disableTitleCycle()
                return
            }
            enableTitleCycle()
        }
    }
    
    var currentTitleLine: Int = -1
    var lastMenuItem: NSMenuItem? = nil

    var titleCylleTimerPubliser: Timer.TimerPublisher {
        return Timer.TimerPublisher(interval: titleCylleInterval, runLoop: .main, mode: .default)
    }

    init(title: String, plugin: Plugin? = nil) {
        super.init()
        barItem.menu = statusBarMenu
        self.plugin = plugin
        statusBarMenu.delegate = self
        updateMenu()
        contentUpdateCancellable = (plugin as? ExecutablePlugin)?.contentUpdatePublisher
            .sink {[weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.disableTitleCycle()
                    self?.updateMenu()
                }
            }
    }

    func enableTitleCycle() {
        titleCycleCancellable = titleCylleTimerPubliser
            .autoconnect()
            .receive(on: RunLoop.main)
            .sink(receiveValue: {[weak self] _ in
                self?.cycleThroughTitles()
            })
    }

    func disableTitleCycle() {
        titleCycleCancellable?.cancel()
    }

    func show() {
        barItem.isVisible = true
    }

    func hide() {
        barItem.isVisible = false
    }
}

extension MenubarItem: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard let lastUpdated = (plugin as? ExecutablePlugin)?.lastUpdated else {return}
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relativeDate = formatter.localizedString(for: lastUpdated, relativeTo: Date()).capitalized
        lastUpdatedMenuItem.title = "Updated \(relativeDate)"
    }
}

// Standard status bar menu
extension MenubarItem {
    func buildStandardMenu() {
        let firstLevel = (plugin == nil)
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
            statusBarMenu.addItem(NSMenuItem.separator())

            // put swiftbar menu as submenu
            let item = NSMenuItem(title: "SwiftBar", action: nil, keyEquivalent: "")
            item.submenu = menu
            statusBarMenu.addItem(item)

            // default plugin menu items
            statusBarMenu.addItem(NSMenuItem.separator())
            statusBarMenu.addItem(lastUpdatedMenuItem)
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
        plugin?.refresh()
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

//parse script output
extension MenubarItem {
    func splitScriptOutput(scriptOutput: String) -> (header: [String], body: [String]){
        guard let index = scriptOutput.range(of: "---") else {
            return (scriptOutput.components(separatedBy: CharacterSet.newlines).filter{!$0.isEmpty},[])
        }
        let header = String(scriptOutput[...index.lowerBound])
            .components(separatedBy: CharacterSet.newlines)
            .dropLast()
            .filter{!$0.isEmpty}
        let body = String(scriptOutput[index.upperBound...])
            .components(separatedBy: CharacterSet.newlines)
            .dropFirst()
            .filter{!$0.isEmpty}
        return (header,body)
    }

    func updateMenu() {
        statusBarMenu.removeAllItems()
        guard let scriptOutput = plugin?.content, scriptOutput.count > 0 else {
            barItem.button?.title = "⚠️"
            buildStandardMenu()
            return
        }
        let parts = splitScriptOutput(scriptOutput: scriptOutput)
        titleLines =  parts.header
        updateMenuTitle(titleLines: parts.header)

        if !parts.body.isEmpty {
            statusBarMenu.addItem(NSMenuItem.separator())
        }

        parts.body.forEach { line in
            addMenuItem(from: line)
        }
        buildStandardMenu()
    }

    func addMenuItem(from line: String) {
        if line == "---" {
            statusBarMenu.addItem(NSMenuItem.separator())
            return
        }
        var workingLine = line
        var submenu: NSMenu? = nil
        while workingLine.hasPrefix("--") {
            workingLine = String(workingLine.dropFirst(2))
            let item = lastMenuItem ?? statusBarMenu.items.last
            if item?.submenu == nil {
                item?.submenu = NSMenu(title: "")
            }
            submenu = item?.submenu
        }

        if let item = buildMenuItem(params: MenuLineParameters(line: workingLine)) {
            item.target = self
            (submenu ?? statusBarMenu)?.addItem(item)
            lastMenuItem = item
        }
    }

    func updateMenuTitle(titleLines: [String]) {
        setMenuTitle(title: titleLines.first ?? "⚠️")
        guard titleLines.count > 1 else {return}

        titleLines.forEach{ line in
            addMenuItem(from: line)
        }
    }

    func setMenuTitle(title: String) {
        barItem.button?.attributedTitle = atributedTitle(with: MenuLineParameters(line: title)).title
    }

    func cycleThroughTitles() {
        currentTitleLine += 1
        if !titleLines.indices.contains(currentTitleLine) {
            currentTitleLine = 0
        }
        setMenuTitle(title: titleLines[currentTitleLine])
    }

    func atributedTitle(with params: MenuLineParameters) -> (title: NSAttributedString, tooltip: String) {
        var title = params.trim ? params.title.trimmingCharacters(in: .whitespaces):params.title
        if params.emojize {
            title = title.emojify()
        }
        let fullTitle = title
        if let length = params.length, length < title.count {
            title = String(title.prefix(length)).appending("...")
        }
        let fontSize = params.size ?? 14
        let color = params.color ?? NSColor.labelColor
        let font = NSFont(name: params.font ?? "", size: fontSize) ?? NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)

        return (NSAttributedString(string: title,
                                  attributes: [
                                    NSAttributedString.Key.foregroundColor:color,
                                    NSAttributedString.Key.font:font
        ]), fullTitle)
    }

    func buildMenuItem(params: MenuLineParameters) -> NSMenuItem? {
        guard params.dropdown else {return nil}

        let item = NSMenuItem(title: params.title,
                            action: params.href != nil ? #selector(performMenuItemHREFAction):
                            params.bash != nil ? #selector(performMenuItemBashAction):
                            params.refresh ? #selector(performMenuItemRefreshAction): nil,
                          keyEquivalent: "")
        item.representedObject = params
        let title = atributedTitle(with: params)
        item.attributedTitle = title.title

        if let length = params.length, length < title.title.string.count {
            item.toolTip = title.tooltip
        }

        if params.alternate {
            item.isAlternate = true
            item.keyEquivalentModifierMask = NSEvent.ModifierFlags.option
        }
        if let image = params.image {
            item.image = image
        }
        return item
    }

    @objc func performMenuItemHREFAction(_ sender: NSMenuItem) {
        guard let params = sender.representedObject as? MenuLineParameters,
              let href = params.href,
              let url = URL(string: href)
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc func performMenuItemBashAction() {

    }

    @objc func performMenuItemRefreshAction(_ sender: NSMenuItem) {
        plugin?.refresh()
    }

}
