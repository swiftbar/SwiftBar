import Cocoa
import Combine
import SwiftUI
import HotKey

class MenubarItem: NSObject {
    var plugin: Plugin?
    let barItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let statusBarMenu = NSMenu(title: "SwiftBar Menu")
    let titleCylleInterval: Double = 5
    var contentUpdateCancellable: AnyCancellable? = nil
    var titleCycleCancellable: AnyCancellable? = nil
    let lastUpdatedMenuItem = NSMenuItem(title: "Updating...", action: nil, keyEquivalent: "")
    var isOpen = false
    var hotKeys: [HotKey] = []

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

    var prevLevel = 0
    var prevItems = [NSMenuItem]()

    var titleCylleTimerPubliser: Timer.TimerPublisher {
        return Timer.TimerPublisher(interval: titleCylleInterval, runLoop: .main, mode: .default)
    }

    init(title: String, plugin: Plugin? = nil) {
        super.init()
        barItem.menu = statusBarMenu
        guard plugin != nil else {
            barItem.button?.title = title
            buildStandardMenu()
            return
        }
        self.plugin = plugin
        statusBarMenu.delegate = self
        updateMenu()
        contentUpdateCancellable = (plugin as? ExecutablePlugin)?.contentUpdatePublisher
            .sink {[weak self] _ in
                guard self?.isOpen == false else {return}
                DispatchQueue.main.async { [weak self] in
                    self?.disableTitleCycle()
                    self?.updateMenu()
                }
            }
    }

    deinit {
        contentUpdateCancellable?.cancel()
        titleCycleCancellable?.cancel()
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
        isOpen = true
        guard let lastUpdated = (plugin as? ExecutablePlugin)?.lastUpdated else {return}
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relativeDate = formatter.localizedString(for: lastUpdated, relativeTo: Date()).capitalized
        lastUpdatedMenuItem.title = "Updated \(relativeDate)"
    }

    func menuDidClose(_ menu: NSMenu) {
        isOpen = false
    }
}

// Standard status bar menu
extension MenubarItem {
    func buildStandardMenu() {
        let firstLevel = (plugin == nil)
        let menu = firstLevel ? statusBarMenu:NSMenu(title: "Preferences")

        let refreshAllItem = NSMenuItem(title: "Refresh All", action: #selector(refreshAllPlugins), keyEquivalent: "r")
        let enableAllItem = NSMenuItem(title: "Enable All", action: #selector(enableAllPlugins), keyEquivalent: "")
        let disableAllItem = NSMenuItem(title: "Disable All", action: #selector(disableAllPlugins), keyEquivalent: "")
        let preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        let openPluginFolderItem = NSMenuItem(title: "Open Plugin Folder...", action: #selector(openPluginFolder), keyEquivalent: "")
        let changePluginFolderItem = NSMenuItem(title: "Change Plugin Folder...", action: #selector(changePluginFolder), keyEquivalent: "")
        let getPluginsItem = NSMenuItem(title: "Get Plugins...", action: #selector(getPlugins), keyEquivalent: "")
        let aboutSwiftBarItem = NSMenuItem(title: "About", action: #selector(aboutSwiftBar), keyEquivalent: "")
        let aboutItem = NSMenuItem(title: "About", action: #selector(about), keyEquivalent: "")
        let quitItem = NSMenuItem(title: "Quit SwiftBar", action: #selector(quit), keyEquivalent: "q")
        let runInTerminalItem = NSMenuItem(title: "Run in Terminal...", action: #selector(runInTerminal), keyEquivalent: "")
        let disablePluginItem = NSMenuItem(title: "Disable Plugin", action: #selector(disablePlugin), keyEquivalent: "")
        let showErrorItem = NSMenuItem(title: "Show Error", action: #selector(showError), keyEquivalent: "")
        [refreshAllItem,enableAllItem,disableAllItem,preferencesItem,openPluginFolderItem,changePluginFolderItem,getPluginsItem,quitItem,disablePluginItem,aboutItem,aboutSwiftBarItem,runInTerminalItem,showErrorItem].forEach{$0.target = self}

        menu.addItem(refreshAllItem)
        menu.addItem(enableAllItem)
        menu.addItem(disableAllItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(openPluginFolderItem)
        menu.addItem(changePluginFolderItem)
        menu.addItem(getPluginsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(aboutSwiftBarItem)
        menu.addItem(preferencesItem)
        menu.addItem(quitItem)

        if !firstLevel {
            statusBarMenu.addItem(NSMenuItem.separator())

            // put swiftbar menu as submenu
            let item = NSMenuItem(title: "SwiftBar", action: nil, keyEquivalent: "")
            item.submenu = menu
            item.image = NSImage(named: "AppIcon")?.resizedCopy(w: 21, h: 21)
            statusBarMenu.addItem(item)

            // default plugin menu items
            statusBarMenu.addItem(NSMenuItem.separator())
            statusBarMenu.addItem(lastUpdatedMenuItem)
            if plugin?.error != nil {
                statusBarMenu.addItem(showErrorItem)
            }
            statusBarMenu.addItem(runInTerminalItem)
            statusBarMenu.addItem(disablePluginItem)
            if plugin?.metadata?.isEmpty == false {
                statusBarMenu.addItem(aboutItem)
            }
        }
    }

    @objc func refreshAllPlugins() {
        delegate.pluginManager.refreshAllPlugins()
    }

    @objc func disableAllPlugins() {
        delegate.pluginManager.disableAllPlugins()
    }

    @objc func enableAllPlugins() {
        delegate.pluginManager.enableAllPlugins()
    }

    @objc func openPluginFolder() {
        App.openPluginFolder()
    }

    //TODO: Preferences should be shown as a standalone window.
    @objc func openPreferences() {
        //        App.openPreferences()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PreferencesView().environmentObject(Preferences.shared))
        popover.show(relativeTo: barItem.button!.bounds, of: barItem.button!, preferredEdge: .minY)
        popover.contentViewController?.view.window?.becomeKey()
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

    @objc func showError() {
        guard let plugin = plugin, plugin.error != nil else {return}
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PluginErrorView(plugin: plugin))
        popover.show(relativeTo: barItem.button!.bounds, of: barItem.button!, preferredEdge: .minY)
        popover.contentViewController?.view.window?.becomeKey()
    }

    @objc func runInTerminal() {
        guard let scriptPath = plugin?.file else {return}
        App.runInTerminal(script: scriptPath)
    }

    @objc func disablePlugin() {
        guard let plugin = plugin else {return}
        delegate.pluginManager.disablePlugin(plugin: plugin)
    }

    @objc func about() {
        guard let pluginMetadata = plugin?.metadata else {return}
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: AboutPluginView(md: pluginMetadata))
        popover.show(relativeTo: barItem.button!.bounds, of: barItem.button!, preferredEdge: .minY)
        popover.contentViewController?.view.window?.becomeKey()
    }

    @objc func aboutSwiftBar() {
        App.showAbout()
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

    func addShortcut(shortcut: HotKey, action: @escaping ()-> Void) {
        shortcut.keyUpHandler = action
        hotKeys.append(shortcut)
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
        if let title = titleLines.first, let kc = MenuLineParameters(line: title).shortcut {
            addShortcut(shortcut: HotKey(keyCombo: kc)) { [weak self] in
                self?.barItem.button?.performClick(nil)
            }
        }

        if !parts.body.isEmpty {
            statusBarMenu.addItem(NSMenuItem.separator())
        }

        //prevItems.append(statusBarMenu.items.last)
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
        var currentLevel = 0

        while workingLine.hasPrefix("--") {
            workingLine = String(workingLine.dropFirst(2))
            currentLevel += 1
        }

        if prevLevel >= currentLevel, prevItems.count > 0 {
            var cnt = prevLevel - currentLevel
            while cnt >= 0 {
                if !prevItems.isEmpty {
                    prevItems.removeFirst()
                }
                cnt = cnt - 1
            }
        }
        if currentLevel > 0 {
            let item = prevItems.first
            if item?.submenu == nil {
                item?.submenu = NSMenu(title: "")
            }
            submenu = item?.submenu
        }

        if let item = buildMenuItem(params: MenuLineParameters(line: workingLine)) {
            item.target = self
            (submenu ?? statusBarMenu)?.addItem(item)
            lastMenuItem = item
            prevLevel = currentLevel
            prevItems.insert(item, at: 0)

            if let kc = MenuLineParameters(line: line).shortcut {
                addShortcut(shortcut: HotKey(keyCombo: kc)) {
                    guard let action = item.action else {return}
                    NSApp.sendAction(action, to: item.target, from: item)
                }
            }
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
        let params = MenuLineParameters(line: title)
        if let image = params.image {
            barItem.button?.image = image
            return
        }
        barItem.button?.attributedTitle = atributedTitle(with: params).title
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
        title = title.replacingOccurrences(of: "\\n", with: "\n")
        let fontSize = params.size ?? 14
        let color = params.color ?? NSColor.labelColor
        let font = NSFont(name: params.font ?? "", size: fontSize) ?? NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        return (NSAttributedString(string: title,
                                  attributes: [
                                    .foregroundColor:color,
                                    .font:font,
                                    .paragraphStyle:style
        ]), fullTitle)
    }

    func itemActionSelector(params: MenuLineParameters) -> Selector? {
        return params.href != nil ? #selector(performMenuItemHREFAction):
            params.bash != nil ? #selector(performMenuItemBashAction):
            params.refresh ? #selector(performMenuItemRefreshAction): nil
    }

    func buildMenuItem(params: MenuLineParameters) -> NSMenuItem? {
        guard params.dropdown else {return nil}

        let item = NSMenuItem(title: params.title,
                            action: itemActionSelector(params: params),
                          keyEquivalent: "")
        item.representedObject = params
        let title = atributedTitle(with: params)
        item.attributedTitle = title.title

        item.toolTip = params.tooltip
        
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

        if params.checked {
            item.state = .on
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

    @objc func performMenuItemBashAction(_ sender: NSMenuItem) {
        guard let params = sender.representedObject as? MenuLineParameters,
              let bash = params.bash
        else {
            return
        }
        let script = "\(bash) \(params.bashParams.joined(separator: " "))"
        App.runInTerminal(script: script, runInBackground: !params.terminal)
    }

    @objc func performMenuItemRefreshAction(_ sender: NSMenuItem) {
        plugin?.refresh()
    }

}
