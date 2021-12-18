import Cocoa
import Combine
import HotKey
import os
import SwiftUI

class MenubarItem: NSObject {
    var plugin: Plugin?

    private lazy var workQueue: OperationQueue = {
        let providerQueue = OperationQueue()
        providerQueue.qualityOfService = .userInitiated
        return providerQueue
    }()

    var barItem: NSStatusItem = {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        return item
    }()

    let statusBarMenu = NSMenu(title: "")
    let titleCylleInterval: Double = 5
    var contentUpdateCancellable: AnyCancellable?
    var titleCycleCancellable: AnyCancellable?
    let lastUpdatedItem = NSMenuItem(title: Localizable.MenuBar.UpdatingMenu.localized, action: nil, keyEquivalent: "")
    let aboutItem = NSMenuItem(title: Localizable.MenuBar.AboutSwiftBar.localized, action: #selector(showAboutPopover), keyEquivalent: "")
    let runInTerminalItem = NSMenuItem(title: Localizable.MenuBar.RunInTerminal.localized, action: #selector(runInTerminal), keyEquivalent: "")
    let disablePluginItem = NSMenuItem(title: Localizable.MenuBar.DisablePlugin.localized, action: #selector(disablePlugin), keyEquivalent: "")
    let debugPluginItem = NSMenuItem(title: Localizable.MenuBar.DebugPlugin.localized, action: #selector(debugPlugin), keyEquivalent: "")
    let swiftBarItem = NSMenuItem(title: Localizable.MenuBar.SwiftBar.localized, action: nil, keyEquivalent: "")
    var isDefault = false
    var isOpen = false
    var refreshOnClose = false
    var hotKeys: [HotKey] = []

    private var aboutPopover = NSPopover()
    private var errorPopover = NSPopover()
    private var popoverDismissMonitor: Any?
    private let popoverDismissEventMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]

    var titleLines: [String] = [] {
        didSet {
            currentTitleLineIndex = -1
            guard titleLines.count > 1 else {
                disableTitleCycle()
                return
            }
            enableTitleCycle()
        }
    }

    var currentTitleLineIndex: Int = -1

    var currentTitleLine: String {
        guard titleLines.indices.contains(currentTitleLineIndex) else {
            return titleLines.first ?? ""
        }
        return titleLines[currentTitleLineIndex]
    }

    var lastMenuItem: NSMenuItem?

    var prevLevel = 0
    var prevItems = [NSMenuItem]()

    var titleCylleTimerPubliser: Timer.TimerPublisher {
        Timer.TimerPublisher(interval: titleCylleInterval, runLoop: .main, mode: .default)
    }

    lazy var menuUpdateQueue: OperationQueue = {
        delegate.pluginManager.menuUpdateQueue
    }()

    init(title: String, plugin: Plugin? = nil) {
        super.init()
        barItem.button?.action = #selector(barItemClicked)
        barItem.button?.target = self
        guard plugin != nil else {
            barItem.button?.title = title
            buildStandardMenu()
            return
        }
        self.plugin = plugin
        barItem.autosaveName = plugin?.id
        statusBarMenu.delegate = self
        if let dropTypes = plugin?.metadata?.dropTypes, !dropTypes.isEmpty {
            barItem.button?.window?.registerForDraggedTypes([NSPasteboard.PasteboardType.fileURL])
            barItem.button?.window?.registerForDraggedTypes(NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
            barItem.button?.window?.delegate = self
        }
        updateMenu(content: plugin?.content)
        contentUpdateCancellable = plugin?.contentUpdatePublisher
            .receive(on: menuUpdateQueue)
            .sink { [weak self] content in
                guard plugin?.metadata?.refreshOnOpen == false else {
                    os_log("Skipping refresh for refreshOnOpen plugin", log: Log.plugin, type: .info)
                    return
                }
                guard self?.isOpen == false else {
                    self?.refreshOnClose = true
                    return
                }
                self?.disableTitleCycle()
                self?.updateMenu(content: content)
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
            .sink(receiveValue: { [weak self] _ in
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
    func menuWillOpen(_: NSMenu) {
        isOpen = true

        var params = MenuLineParameters(line: currentTitleLine)
        params.params["color"] = "white"
        params.params["sfcolor"] = "white"
        if !AppShared.isReduceTransparencyEnabled {
            barItem.button?.attributedTitle = atributedTitle(with: params, pad: true).title
        }

        hotKeys.forEach { $0.isPaused = true }
        guard let lastUpdated = plugin?.lastUpdated else { return }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relativeDate = formatter.localizedString(for: lastUpdated, relativeTo: Date()).capitalized
        lastUpdatedItem.title = "\(Localizable.MenuBar.LastUpdated.localized) \(relativeDate)"

        guard NSApp.currentEvent?.modifierFlags.contains(.option) == false else {
            [lastUpdatedItem, runInTerminalItem, disablePluginItem, debugPluginItem, aboutItem, swiftBarItem].forEach { $0.isHidden = false }
            return
        }
        lastUpdatedItem.isHidden = plugin?.metadata?.hideLastUpdated ?? false
        runInTerminalItem.isHidden = plugin?.metadata?.hideRunInTerminal ?? false
        disablePluginItem.isHidden = plugin?.metadata?.hideDisablePlugin ?? false
        aboutItem.isHidden = plugin?.metadata?.hideAbout ?? false
        swiftBarItem.isHidden = plugin?.metadata?.hideSwiftBar ?? false
    }

    func menuDidClose(_: NSMenu) {
        isOpen = false
        setMenuTitle(title: currentTitleLine)
        hotKeys.forEach { $0.isPaused = false }

        // if plugin was refreshed when menu was opened refresh on menu close
        if refreshOnClose {
            menuUpdateQueue.addOperation { [weak self] in
                self?.refreshOnClose = false
                self?.disableTitleCycle()
                self?.updateMenu(content: self?.plugin?.content)
            }
        }
        // since we're handling click in barItemClicked we need to remove the menu
        barItem.menu = nil
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        if let highlitedItem = menu.highlightedItem,
           highlitedItem.attributedTitle != nil,
           let params = highlitedItem.representedObject as? MenuLineParameters,
           params.color != nil
        {
            highlitedItem.attributedTitle = atributedTitle(with: params).title
        }

        if var params = item?.representedObject as? MenuLineParameters,
           item?.attributedTitle != nil,
           params.color != nil
        {
            params.params.removeValue(forKey: "color")
            item?.attributedTitle = atributedTitle(with: params).title
        }
    }
}

// Standard status bar menu
extension MenubarItem {
    func buildStandardMenu() {
        let firstLevel = (plugin == nil)
        let menu = firstLevel ? statusBarMenu : NSMenu(title: "")

        let refreshAllItem = NSMenuItem(title: Localizable.MenuBar.RefreshAll.localized, action: #selector(refreshAllPlugins), keyEquivalent: "r")
        let enableAllItem = NSMenuItem(title: Localizable.MenuBar.EnableAll.localized, action: #selector(enableAllPlugins), keyEquivalent: "")
        let disableAllItem = NSMenuItem(title: Localizable.MenuBar.DisableAll.localized, action: #selector(disableAllPlugins), keyEquivalent: "")
        let preferencesItem = NSMenuItem(title: Localizable.MenuBar.Preferences.localized, action: #selector(openPreferences), keyEquivalent: ",")
        let openPluginFolderItem = NSMenuItem(title: Localizable.MenuBar.OpenPluginsFolder.localized, action: #selector(openPluginFolder), keyEquivalent: "")
        let changePluginFolderItem = NSMenuItem(title: Localizable.MenuBar.ChangePluginsFolder.localized, action: #selector(changePluginFolder), keyEquivalent: "")
        let getPluginsItem = NSMenuItem(title: Localizable.MenuBar.GetPlugins.localized, action: #selector(getPlugins), keyEquivalent: "")
        let sendFeedbackItem = NSMenuItem(title: Localizable.MenuBar.SendFeedback.localized, action: #selector(sendFeedback), keyEquivalent: "")
        let aboutSwiftbarItem = NSMenuItem(title: Localizable.MenuBar.AboutPlugin.localized, action: #selector(aboutSwiftBar), keyEquivalent: "")
        let quitItem = NSMenuItem(title: Localizable.App.Quit.localized, action: #selector(quit), keyEquivalent: "q")
        let showErrorItem = NSMenuItem(title: Localizable.MenuBar.ShowError.localized, action: #selector(showErrorPopover), keyEquivalent: "")
        [refreshAllItem, enableAllItem, disableAllItem, preferencesItem, openPluginFolderItem, changePluginFolderItem, getPluginsItem, quitItem, disablePluginItem, debugPluginItem, aboutItem, aboutSwiftbarItem, runInTerminalItem, showErrorItem, sendFeedbackItem].forEach { item in
            item.target = self
            item.attributedTitle = NSAttributedString(string: item.title, attributes: [.font: NSFont.menuBarFont(ofSize: 0)])
        }

        menu.addItem(refreshAllItem)
        menu.addItem(enableAllItem)
        menu.addItem(disableAllItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(openPluginFolderItem)
        menu.addItem(changePluginFolderItem)
        menu.addItem(getPluginsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(aboutSwiftbarItem)
        menu.addItem(preferencesItem)
        menu.addItem(sendFeedbackItem)
        menu.addItem(quitItem)

        if !firstLevel {
            statusBarMenu.addItem(NSMenuItem.separator())

            // put swiftbar menu as submenu
            swiftBarItem.attributedTitle = NSAttributedString(string: swiftBarItem.title, attributes: [.font: NSFont.menuBarFont(ofSize: 0)])
            swiftBarItem.submenu = menu
            swiftBarItem.image = PreferencesStore.shared.swiftBarIconIsHidden ? nil : NSImage(named: "AppIcon")?.resizedCopy(w: 21, h: 21)
            statusBarMenu.addItem(swiftBarItem)

            // default plugin menu items
            statusBarMenu.addItem(NSMenuItem.separator())
            statusBarMenu.addItem(lastUpdatedItem)
            if plugin?.error != nil {
                statusBarMenu.addItem(showErrorItem)
            }
            statusBarMenu.addItem(runInTerminalItem)
            statusBarMenu.addItem(disablePluginItem)
            if PreferencesStore.shared.pluginDebugMode {
                statusBarMenu.addItem(debugPluginItem)
            }
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
        AppShared.openPluginFolder()
    }

    // TODO: Preferences should be shown as a standalone window.
    @objc func openPreferences() {
        AppShared.openPreferences()
    }

    @objc func changePluginFolder() {
        AppShared.changePluginFolder()
    }

    @objc func getPlugins() {
        AppShared.getPlugins()
    }

    @objc func sendFeedback() {
        NSWorkspace.shared.open(URL(string: "https://github.com/swiftbar/SwiftBar/issues")!)
    }

    @objc func quit() {
        NSApp.terminate(self)
    }

    @objc func runInTerminal() {
        guard let scriptPath = plugin?.file else { return }
        AppShared.runInTerminal(script: scriptPath, env: plugin?.env ?? [:], runInBash: plugin?.metadata?.shouldRunInBash ?? true)
    }

    func startPopupMonitor() {
        popoverDismissMonitor = NSEvent.addGlobalMonitorForEvents(matching: popoverDismissEventMask, handler: popoverHideHandler) as? NSObject
    }

    func stopPopupMonitor() {
        if let monitor = popoverDismissMonitor {
            NSEvent.removeMonitor(monitor)
            popoverDismissMonitor = nil
        }
    }

    @objc func disablePlugin() {
        guard let plugin = plugin else { return }
        delegate.pluginManager.disablePlugin(plugin: plugin)
    }

    @objc func debugPlugin() {
        guard let plugin = plugin else { return }
        AppShared.showPluginDebug(plugin: plugin)
    }

    @objc func showErrorPopover() {
        guard let plugin = plugin, plugin.error != nil else { return }
        errorPopover.behavior = .transient
        errorPopover.contentViewController = NSHostingController(rootView: PluginErrorView(plugin: plugin))
        errorPopover.show(relativeTo: barItem.button!.bounds, of: barItem.button!, preferredEdge: .minY)
        errorPopover.contentViewController?.view.window?.becomeKey()
        startPopupMonitor()
    }

    @objc func hideErrorPopover(_ sender: AnyObject?) {
        errorPopover.performClose(sender)
        stopPopupMonitor()
    }

    @objc func showAboutPopover() {
        guard let pluginMetadata = plugin?.metadata else { return }
        aboutPopover.behavior = .transient
        aboutPopover.contentViewController = NSHostingController(rootView: AboutPluginView(md: pluginMetadata))
        aboutPopover.show(relativeTo: barItem.button!.bounds, of: barItem.button!, preferredEdge: .minY)
        aboutPopover.contentViewController?.view.window?.becomeKey()
        startPopupMonitor()
    }

    @objc func hideAboutPopover(_ sender: AnyObject?) {
        aboutPopover.performClose(sender)
        stopPopupMonitor()
    }

    func popoverHideHandler(_ event: NSEvent?) {
        if aboutPopover.isShown {
            hideAboutPopover(event)
        }

        if errorPopover.isShown {
            hideErrorPopover(event)
        }
    }

    @objc func aboutSwiftBar() {
        AppShared.showAbout()
    }
}

extension MenubarItem {
    static func defaultBarItem() -> MenubarItem {
        let item = MenubarItem(title: "SwiftBar")
        item.isDefault = true
        return item
    }
}

// parse script output
extension MenubarItem {
    func splitScriptOutput(scriptOutput: String) -> (header: [String], body: [String]) {
        let lines = scriptOutput.components(separatedBy: CharacterSet.newlines).filter { !$0.isEmpty }
        guard let index = lines.firstIndex(where: { $0.hasPrefix("---") }) else {
            return (lines, [])
        }
        let header = Array(lines[...index].dropLast())
        let body = Array(lines[index...])

        return (header, body)
    }

    func addShortcut(shortcut: HotKey, action: @escaping () -> Void) {
        shortcut.keyUpHandler = action
        hotKeys.append(shortcut)
    }

    func updateMenu(content: String?) {
        DispatchQueue.main.async { [weak self] in
            self?._updateMenu(content: content)
        }
    }

    func _updateMenu(content: String?) {
        statusBarMenu.removeAllItems()
        show()

        if plugin?.lastState == .Failed {
            titleLines = ["⚠️"]
            barItem.button?.title = "⚠️"
            buildStandardMenu()
            return
        }

        guard let scriptOutput = content,
              !scriptOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || plugin?.lastState == .Loading
        else {
            hide()
            return
        }

        let parts = splitScriptOutput(scriptOutput: scriptOutput)
        titleLines = parts.header
        updateMenuTitle(titleLines: parts.header)
        if let title = titleLines.first, let kc = MenuLineParameters(line: title).shortcut {
            addShortcut(shortcut: HotKey(keyCombo: kc)) { [weak self] in
                self?.barItem.button?.performClick(nil)
            }
        }

        if !parts.body.isEmpty {
            statusBarMenu.addItem(NSMenuItem.separator())
        }

        // prevItems.append(statusBarMenu.items.last)
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
        var submenu: NSMenu?
        var currentLevel = 0

        while workingLine.hasPrefix("--") {
            workingLine = String(workingLine.dropFirst(2))
            currentLevel += 1
            if workingLine == "---" {
                break
            }
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

        if let item = workingLine == "---" ? NSMenuItem.separator() : buildMenuItem(params: MenuLineParameters(line: workingLine)) {
            item.target = self
            (submenu ?? statusBarMenu)?.addItem(item)
            lastMenuItem = item
            prevLevel = currentLevel
            prevItems.insert(item, at: 0)

            if let kc = MenuLineParameters(line: line).shortcut {
                item.keyEquivalentModifierMask = kc.modifiers
                item.keyEquivalent = kc.key?.description.lowercased() ?? ""
                addShortcut(shortcut: HotKey(keyCombo: kc)) {
                    guard let action = item.action else { return }
                    NSApp.sendAction(action, to: item.target, from: item)
                }
            }
        }
    }

    func updateMenuTitle(titleLines: [String]) {
        setMenuTitle(title: titleLines.first ?? "⚠️")
        guard titleLines.count > 1 else { return }

        titleLines.forEach { line in
            addMenuItem(from: line)
        }
    }

    func setMenuTitle(title: String) {
        barItem.button?.attributedTitle = NSAttributedString()
        barItem.button?.image = nil

        let params = MenuLineParameters(line: title)
        if let image = params.image {
            barItem.button?.image = image
            barItem.button?.imagePosition = .imageLeft
        }
        let attrTitle = atributedTitle(with: params, pad: true).title
        barItem.button?.attributedTitle = atributedTitle(with: params, pad: true).title
    }

    func cycleThroughTitles() {
        currentTitleLineIndex += 1
        if !titleLines.indices.contains(currentTitleLineIndex) {
            currentTitleLineIndex = 0
        }
        setMenuTitle(title: titleLines[currentTitleLineIndex])
    }

    func atributedTitle(with params: MenuLineParameters, pad: Bool = false) -> (title: NSAttributedString, tooltip: String) {
        var title = params.trim ? params.title.trimmingCharacters(in: .whitespaces) : params.title
        guard !title.isEmpty else { return (NSAttributedString(), "") }

        if params.emojize, !params.symbolize {
            title = title.emojify()
        }
        let fullTitle = title
        if let length = params.length, length < title.count {
            title = String(title.prefix(length)).appending("...")
        }
        title = title.replacingOccurrences(of: "\\n", with: "\n")

        let fontSize = params.size ?? 0
        let color = params.color ?? NSColor.controlTextColor
        let font = NSFont(name: params.font ?? "", size: fontSize) ??
            NSFont.menuBarFont(ofSize: fontSize)
        let offset = font.menuBarOffset

        let style = NSMutableParagraphStyle()
        style.alignment = .left

        var attributedTitle = NSMutableAttributedString(string: title)

        if params.symbolize, !params.ansi {
            attributedTitle = title.symbolize(font: font, colors: params.sfcolors, sfsize: params.sfsize)
        }
        if params.ansi {
            attributedTitle = title.colorizedWithANSIColor()
        }

        if attributedTitle.length > 0, pad {
            attributedTitle.insert(NSAttributedString(string: " "), at: 0)
        }

        if !params.ansi {
            attributedTitle.addAttributes([.foregroundColor: color],
                                          range: NSRange(0 ..< attributedTitle.length))
        }

        attributedTitle.addAttributes([.font: font, .paragraphStyle: style, .baselineOffset: offset],

                                      range: NSRange(0 ..< attributedTitle.length))
        return (attributedTitle, fullTitle)
    }

    func buildMenuItem(params: MenuLineParameters) -> NSMenuItem? {
        guard params.dropdown else { return nil }

        let item = NSMenuItem(title: params.title,
                              action: params.hasAction ? #selector(perfomMenutItemAction) : nil,
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

    @objc func barItemClicked() {
        guard let eventType = NSApp.currentEvent?.type else { return }

        if eventType == .rightMouseDown {
            showMenu()
            return
        }

        if performItemAction(params: MenuLineParameters(line: currentTitleLine)) {
            return
        }

        showMenu()
    }

    func showMenu() {
        if plugin?.metadata?.refreshOnOpen == true, plugin?.type == .Executable {
            refreshAndShowMenu()
            return
        }
        barItem.menu = statusBarMenu
        barItem.button?.performClick(nil)
    }

    func refreshAndShowMenu() {
        if #available(macOS 11.0, *) {
            barItem.button?.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: nil)
            barItem.button?.imagePosition = .imageLeft
        } else {
            barItem.button?.image = nil
            barItem.button?.title = "..."
        }
        DispatchQueue.main.async { [weak self] in
            self?.barItem.button?.image = nil
            self?.barItem.button?.title.removeAll()
            self?.plugin?.refresh()
            self?.updateMenu(content: self?.plugin?.content)
            self?.barItem.menu = self?.statusBarMenu
            self?.barItem.button?.performClick(nil)
        }
    }

    @discardableResult func performItemAction(params: MenuLineParameters) -> Bool {
        defer {
            if params.color != nil {
                updateMenu(content: plugin?.content) // dumb fix for #221, ideally come up with something better...
            }
        }

        if let href = params.href, let url = URL(string: href) {
            NSWorkspace.shared.open(url)
            return true
        }

        if let bash = params.bash {
            AppShared.runInTerminal(script: bash, args: params.bashParams, runInBackground: !params.terminal,
                                    env: plugin?.env ?? [:], runInBash: plugin?.metadata?.shouldRunInBash ?? true) { [weak self] in
                if params.refresh {
                    self?.plugin?.refresh()
                }
            }
            return true
        }

        if params.refresh {
            plugin?.refresh()
            return true
        }
        return false
    }

    @objc func perfomMenutItemAction(_ sender: NSMenuItem) {
        guard let params = sender.representedObject as? MenuLineParameters else { return }
        performItemAction(params: params)
    }
}

extension MenubarItem: NSWindowDelegate, NSDraggingDestination {
    func draggingEntered(_: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        var env: [String: String] = plugin?.env ?? [:]
        var files: [String] = []
        let supportedClasses = [
            NSFilePromiseReceiver.self,
            NSURL.self,
        ]

        let searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: plugin?.metadata?.dropTypes ?? [],
        ]

        let destinationURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Drops")
        try? FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)

        sender.enumerateDraggingItems(options: [], for: nil, classes: supportedClasses, searchOptions: searchOptions) { draggingItem, _, _ in
            switch draggingItem.item {
            case let filePromiseReceiver as NSFilePromiseReceiver:
                filePromiseReceiver.receivePromisedFiles(atDestination: destinationURL, options: [:], operationQueue: self.workQueue) { fileURL, error in
                    if error == nil {
                        files.append(fileURL.path)
                    }
                }
            case let fileURL as URL:
                files.append(fileURL.path)
            default: break
            }
        }

        env["DROPPED_FILES"] = files.joined(separator: ",")
        guard let scriptPath = plugin?.file else { return false }
        AppShared.runInTerminal(script: scriptPath, env: env, runInBash: plugin?.metadata?.shouldRunInBash ?? true)
        return true
    }
}
