import Cocoa
import Combine
import HotKey
import os
import SwiftUI

class MenubarItem: NSObject {
    enum ActionKind: Equatable {
        case href
        case bash
        case stdin
        case refresh
    }

    var plugin: Plugin?
    let visibilityDidChange: ((Bool) -> Void)?

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
    var stalenessCheckCancellable: AnyCancellable?
    let lastUpdatedItem = NSMenuItem(title: Localizable.MenuBar.UpdatingMenu.localized, action: nil, keyEquivalent: "")
    let aboutItem = NSMenuItem(title: Localizable.MenuBar.AboutSwiftBar.localized, action: #selector(showAboutPopover), keyEquivalent: "")
    let runInTerminalItem = NSMenuItem(title: Localizable.MenuBar.RunInTerminal.localized, action: #selector(runInTerminal), keyEquivalent: "")
    let disablePluginItem = NSMenuItem(title: Localizable.MenuBar.DisablePlugin.localized, action: #selector(disablePlugin), keyEquivalent: "")
    let debugPluginItem = NSMenuItem(title: Localizable.MenuBar.DebugPlugin.localized, action: #selector(debugPlugin), keyEquivalent: "")
    let terminatePluginItem = NSMenuItem(title: Localizable.MenuBar.TerminateEphemeralPlugin.localized, action: #selector(terminateEphemeralPlugin), keyEquivalent: "")
    let swiftBarItem = NSMenuItem(title: Localizable.MenuBar.SwiftBar.localized, action: nil, keyEquivalent: "")
    var isDefault = false
    var isOpen = false
    var refreshOnClose = false
    var hotKeys: [HotKey] = []
    var hotkeyTrigger: Bool = false
    var showsAllStandardItemsWhileOpen = false

    private var aboutPopover = NSPopover()
    private var errorPopover = NSPopover()
    private var webPopover = NSPopover()
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

    var refreshOnOpen: Bool {
        plugin?.metadata?.refreshOnOpen ?? false
    }

    lazy var menuUpdateQueue: OperationQueue = delegate.pluginManager.menuUpdateQueue

    init(title: String, plugin: Plugin? = nil, visibilityDidChange: ((Bool) -> Void)? = nil) {
        self.visibilityDidChange = visibilityDidChange
        super.init()
        barItem.button?.action = #selector(barItemClicked)
        barItem.button?.target = self
        guard plugin != nil else {
            barItem.button?.title = title
            buildStandardMenu()
            return
        }
        webPopover.delegate = self
        barItem.autosaveName = plugin?.id
        statusBarMenu.delegate = self
        replacePlugin(plugin)
    }

    deinit {
        contentUpdateCancellable?.cancel()
        titleCycleCancellable?.cancel()
        stalenessCheckCancellable?.cancel()
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
        setVisibility(isVisible: true)
    }

    func hide() {
        setVisibility(isVisible: false)
    }

    func replacePlugin(_ plugin: Plugin?) {
        dispatchPrecondition(condition: .onQueue(.main))
        let wasCyclingTitles = titleCycleCancellable != nil
        contentUpdateCancellable?.cancel()
        titleCycleCancellable?.cancel()
        stalenessCheckCancellable?.cancel()
        self.plugin = plugin
        // Only update autosaveName when we have a plugin so that a nil plugin
        // doesn't erase the saved menu bar position.
        if let plugin {
            barItem.autosaveName = plugin.id
        }

        if let dropTypes = plugin?.metadata?.dropTypes, !dropTypes.isEmpty {
            barItem.button?.window?.registerForDraggedTypes([NSPasteboard.PasteboardType.fileURL, NSPasteboard.PasteboardType.URL])
            barItem.button?.window?.registerForDraggedTypes(NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
            barItem.button?.window?.delegate = self
        } else {
            barItem.button?.window?.unregisterDraggedTypes()
        }

        updateMenu(content: plugin?.content)
        contentUpdateCancellable = plugin?.contentUpdatePublisher
            .receive(on: menuUpdateQueue)
            .sink { [weak self] content in
                guard self?.isOpen == false else {
                    self?.refreshOnClose = true
                    return
                }
                self?.disableTitleCycle()
                self?.updateMenu(content: content)
            }

        // Keep the existing status item and swap only the plugin bindings so menu bar position stays stable.
        stalenessCheckCancellable = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self,
                      let plugin = self.plugin else { return }

                let wasStale = barItem.button?.attributedTitle.string.hasPrefix("⚠️") ?? false
                let isNowStale = plugin.isStale

                if wasStale != isNowStale {
                    setMenuTitle(title: currentTitleLine)
                }
            }

        // Restore title cycling if it was active before the replacement.
        if wasCyclingTitles, titleLines.count > 1 {
            enableTitleCycle()
        }
    }

    private func setVisibility(isVisible: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        let visibilityChanged = barItem.isVisible != isVisible
        barItem.isVisible = isVisible

        guard visibilityChanged else { return }
        visibilityDidChange?(isVisible)
    }
}

extension MenubarItem: NSMenuDelegate {
    func menuWillOpen(_: NSMenu) {
        isOpen = true
        showsAllStandardItemsWhileOpen = !hotkeyTrigger && (NSApp.currentEvent?.modifierFlags.contains(.option) ?? false)

        if #available(macOS 12, *) {
            // nothing todo here
        } else if !AppShared.isReduceTransparencyEnabled {
            var params = MenuLineParameters(line: currentTitleLine)
            params.params["color"] = "white"
            params.params["sfcolor"] = "white"
            barItem.button?.attributedTitle = atributedTitle(with: params, pad: true).title
        }

        hotkeyTrigger = false
        reapplyOpenMenuStateIfNeeded()
    }

    func menuDidClose(_: NSMenu) {
        isOpen = false
        showsAllStandardItemsWhileOpen = false
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
        for item in [refreshAllItem, enableAllItem, disableAllItem, preferencesItem, openPluginFolderItem, changePluginFolderItem, getPluginsItem, quitItem, disablePluginItem, debugPluginItem, terminatePluginItem, aboutItem, aboutSwiftbarItem, runInTerminalItem, showErrorItem, sendFeedbackItem] {
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
            if let pluginType = plugin?.type {
                if PluginType.runnableInTerminal.contains(pluginType) {
                    statusBarMenu.addItem(runInTerminalItem)
                }
                if PreferencesStore.shared.pluginDebugMode, PluginType.debugable.contains(pluginType) {
                    statusBarMenu.addItem(debugPluginItem)
                }
                if PluginType.disableable.contains(pluginType) {
                    statusBarMenu.addItem(disablePluginItem)
                }
                if pluginType == .Ephemeral {
                    statusBarMenu.addItem(terminatePluginItem)
                }
            }

            if plugin?.metadata?.isEmpty == false {
                statusBarMenu.addItem(aboutItem)
            }
        }
    }

    @objc func refreshAllPlugins() {
        delegate.pluginManager.refreshAllPlugins(reason: .RefreshAllMenu)
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
        guard let plugin else { return }
        delegate.pluginManager.disablePlugin(plugin: plugin)
    }

    @objc func debugPlugin() {
        guard let plugin else { return }
        AppShared.showPluginDebug(plugin: plugin)
    }

    @objc func terminateEphemeralPlugin() {
        guard let plugin else { return }
        plugin.terminate()
    }

    @objc func showErrorPopover() {
        guard let plugin, plugin.error != nil else { return }
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

    func showWebPopover(url: URL, widht: CGFloat, height: CGFloat, zoom: CGFloat) {
        defer {
            webPopover.show(relativeTo: barItem.button!.bounds, of: barItem.button!, preferredEdge: .minY)
            webPopover.contentViewController?.view.window?.becomeKey()
            startPopupMonitor()
        }

        guard webPopover.contentViewController == nil || plugin?.metadata?.persistentWebView == false else {
            return
        }

        let urlRequest = URLRequest(url: url)
        webPopover.behavior = .transient
        webPopover.contentViewController = NSHostingController(
            rootView: WebPanelView(
                request: urlRequest,
                name: plugin?.name ?? "",
                zoomFactor: zoom
            )
        )
        webPopover.contentSize = NSSize(width: widht, height: height)
    }

    func hideWebPopover(_ sender: AnyObject?) {
        // If the popover is detached, don't automatically close it when clicking outside
        if let window = webPopover.contentViewController?.view.window,
           window.styleMask.contains(.titled)
        {
            // Only stop the monitor for detached windows, don't close the window
            stopPopupMonitor()
            return
        }

        // Normal popover behavior for non-detached popovers
        webPopover.performClose(sender)
        if plugin?.metadata?.persistentWebView == false {
            resetWebPopoverContent()
        }
        stopPopupMonitor()
    }

    func resetWebPopoverContent() {
        webPopover.contentViewController = nil
    }

    func popoverHideHandler(_ event: NSEvent?) {
        if aboutPopover.isShown {
            hideAboutPopover(event)
        }

        if errorPopover.isShown {
            hideErrorPopover(event)
        }

        if webPopover.isShown {
            hideWebPopover(event)
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
        // The fallback SwiftBar item intentionally has no visibility callback.
        // PluginManager owns its visibility directly, which avoids callback recursion.
        // Ensure the default bar item is always visible
        item.barItem.isVisible = true
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
        dispatchPrecondition(condition: .onQueue(.main))
        barItem.button?.appearsDisabled = false

        if plugin?.lastState == .Failed {
            fullRebuildMenu(content: nil)
            return
        }

        guard let scriptOutput = content,
              !scriptOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || plugin?.lastState == .Loading
        else {
            if plugin?.metadata?.alwaysVisible == true {
                fullRebuildMenu(content: nil)
            } else {
                currentMenuTree = []
                currentHeaderLines = []
                pluginItemCount = 0
                hide()
            }
            return
        }

        let parts = splitScriptOutput(scriptOutput: scriptOutput)
        let newTree = MenuItemNode.buildMenuTree(from: parts.body)

        // Use incremental diff if we have a previous tree to compare against
        if !currentMenuTree.isEmpty {
            incrementalUpdateMenu(content: scriptOutput, header: parts.header, body: parts.body, newTree: newTree)
        } else {
            fullRebuildMenu(content: content)
        }
    }

    /// Full rebuild: clears everything and recreates from scratch.
    /// Used on first render, error states, or as a fallback.
    private func fullRebuildMenu(content: String?) {
        statusBarMenu.removeAllItems()
        hotKeys.removeAll()
        prevItems.removeAll()
        prevLevel = 0
        resetWebPopoverContent()
        show()
        defer {
            reapplyOpenMenuStateIfNeeded()
        }

        if plugin?.lastState == .Failed {
            titleLines = ["􀇾"]
            barItem.button?.title = "􀇾"
            buildStandardMenu()
            return
        }

        guard let scriptOutput = content,
              !scriptOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || plugin?.lastState == .Loading
        else {
            if plugin?.metadata?.alwaysVisible == true {
                buildStandardMenu()
            } else {
                hide()
            }
            return
        }

        let parts = splitScriptOutput(scriptOutput: scriptOutput)
        titleLines = parts.header
        updateMenuTitle(titleLines: parts.header)

        if !parts.body.isEmpty {
            statusBarMenu.addItem(NSMenuItem.separator())
        }

        // prevItems.append(statusBarMenu.items.last)
        for line in parts.body {
            addMenuItem(from: line)
        }

        // Track how many items belong to the plugin content.
        // Includes title/header items + optional separator + body root-level items.
        // Standard menu items (SwiftBar submenu, etc.) are appended after this point.
        pluginItemCount = statusBarMenu.items.count
        currentMenuTree = MenuItemNode.buildMenuTree(from: parts.body)
        syncHotKeys()
        buildStandardMenu()
    }

    /// Incremental update: diffs old vs new tree and patches the live menu.
    /// This runs while the menu may be open, enabling live content updates
    /// without waiting for the menu to close and rebuild.
    private func incrementalUpdateMenu(content: String, header: [String], body: [String], newTree: [MenuItemNode]) {
        dispatchPrecondition(condition: .onQueue(.main))

        if header != currentHeaderLines || body.isEmpty {
            fullRebuildMenu(content: content)
            return
        }

        // Calculate the base index in statusBarMenu where body items start.
        // Layout: [title items...] [separator] [body items...] [standard items...]
        let oldBodyCount = countMenuItems(in: currentMenuTree)
        let bodyBaseIndex = pluginItemCount - oldBodyCount

        // Validate index assumptions; fall back to full rebuild if out of sync.
        guard bodyBaseIndex >= 0, bodyBaseIndex + oldBodyCount <= statusBarMenu.items.count else {
            os_log("Incremental update index mismatch (base=%d, bodyCount=%d, menuCount=%d), falling back to full rebuild",
                   log: Log.plugin, type: .error, bodyBaseIndex, oldBodyCount, statusBarMenu.items.count)
            fullRebuildMenu(content: content)
            return
        }

        // Diff body items and patch in-place
        let changes = diffMenuNodes(old: currentMenuTree, new: newTree)
        applyDiff(changes, oldTree: currentMenuTree, newTree: newTree, to: statusBarMenu, baseIndex: bodyBaseIndex)

        // Update tracking state
        pluginItemCount = pluginItemCount - oldBodyCount + countMenuItems(in: newTree)
        currentMenuTree = newTree
        restoreTitleCycleIfNeeded()
        syncHotKeys()
        if isOpen {
            reapplyOpenMenuStateIfNeeded()
        } else {
            updateLastUpdatedItem()
        }
    }

    /// Count the visible root-level NSMenuItems represented by the diff tree.
    private func countMenuItems(in nodes: [MenuItemNode]) -> Int {
        nodes.count
    }

    /// Apply a diff to a live NSMenu, patching items in-place.
    private func applyDiff(_ changes: [MenuItemChange], oldTree: [MenuItemNode], newTree: [MenuItemNode], to menu: NSMenu, baseIndex: Int) {
        applyRemovals(changes, to: menu, baseIndex: baseIndex)
        applyUpdatesAndInserts(changes, oldTree: oldTree, newTree: newTree, to: menu, baseIndex: baseIndex)
    }

    /// Remove items from the menu. Removals arrive in reverse index order from
    /// diffMenuNodes so that earlier indices are not invalidated.
    private func applyRemovals(_ changes: [MenuItemChange], to menu: NSMenu, baseIndex: Int) {
        for change in changes {
            if case .remove(let oldIndex) = change {
                let menuIndex = baseIndex + oldIndex
                if menuIndex < menu.items.count {
                    menu.removeItem(at: menuIndex)
                }
            }
        }
    }

    /// Process updates and inserts in forward order after removals are complete.
    private func applyUpdatesAndInserts(_ changes: [MenuItemChange], oldTree: [MenuItemNode], newTree: [MenuItemNode], to menu: NSMenu, baseIndex: Int) {
        for change in changes {
            switch change {
            case .unchanged:
                break

            case .update(let oldIndex, let newIndex):
                applyUpdate(menu: menu, baseIndex: baseIndex, oldNode: oldTree[oldIndex], newNode: newTree[newIndex], newIndex: newIndex)

            case .insert(let newIndex):
                applyInsert(menu: menu, baseIndex: baseIndex, newNode: newTree[newIndex], newIndex: newIndex)

            case .remove:
                break // Already handled in applyRemovals
            }
        }
    }

    /// Update a single existing menu item to match a new node.
    private func applyUpdate(menu: NSMenu, baseIndex: Int, oldNode: MenuItemNode, newNode: MenuItemNode, newIndex: Int) {
        let menuIndex = baseIndex + newIndex
        guard menuIndex < menu.items.count else { return }
        let existingItem = menu.items[menuIndex]

        if newNode.isSeparator {
            if !existingItem.isSeparatorItem {
                menu.removeItem(at: menuIndex)
                menu.insertItem(NSMenuItem.separator(), at: menuIndex)
            }
        } else if existingItem.isSeparatorItem {
            menu.removeItem(at: menuIndex)
            if let newItem = buildMenuItem(params: MenuLineParameters(line: newNode.workingLine)) {
                newItem.target = self
                menu.insertItem(newItem, at: menuIndex)
                buildSubmenuItems(for: newItem, from: newNode)
            }
        } else {
            if !oldNode.contentEqual(to: newNode) {
                patchMenuItem(existingItem, with: MenuLineParameters(line: newNode.workingLine))
            }
            if oldNode.children != newNode.children {
                updateSubmenu(of: existingItem, oldChildren: oldNode.children, newChildren: newNode.children)
            }
        }
    }

    /// Insert a new menu item for a node that did not exist in the old tree.
    private func applyInsert(menu: NSMenu, baseIndex: Int, newNode: MenuItemNode, newIndex: Int) {
        let menuIndex = baseIndex + newIndex
        if newNode.isSeparator {
            menu.insertItem(NSMenuItem.separator(), at: min(menuIndex, menu.items.count))
        } else if let newItem = buildMenuItem(params: MenuLineParameters(line: newNode.workingLine)) {
            newItem.target = self
            menu.insertItem(newItem, at: min(menuIndex, menu.items.count))
            buildSubmenuItems(for: newItem, from: newNode)
        }
    }

    /// Patch an existing NSMenuItem's visible properties to match new parameters.
    private func patchMenuItem(_ item: NSMenuItem, with params: MenuLineParameters) {
        let needsAction = params.hasAction || params.color != nil
        item.action = needsAction ? #selector(perfomMenutItemAction) : nil
        item.representedObject = params

        let title = atributedTitle(with: params)
        item.attributedTitle = title.title

        item.toolTip = params.tooltip?.replacingOccurrences(of: "\\n", with: "\n")
        if let length = params.length, length < title.title.string.count {
            item.toolTip = title.tooltip
        }

        item.isAlternate = params.alternate

        item.image = params.image
        item.state = params.checked ? .on : .off

        if #available(macOS 14.0, *) {
            item.badge = params.badge.isEmpty ? nil : NSMenuItemBadge(string: params.badge)
        }
    }

    private func syncHotKeys() {
        hotKeys.removeAll()

        if let title = titleLines.first, let kc = MenuLineParameters(line: title).shortcut {
            addShortcut(shortcut: HotKey(keyCombo: kc)) { [weak self] in
                self?.hotkeyTrigger = true
                self?.barItem.button?.performClick(nil)
            }
        }

        for item in statusBarMenu.items.prefix(pluginItemCount) {
            syncHotKeys(for: item)
        }
    }

    private func syncHotKeys(for item: NSMenuItem) {
        if let params = item.representedObject as? MenuLineParameters {
            applyShortcut(for: item, params: params)

            if let kc = params.shortcut {
                addShortcut(shortcut: HotKey(keyCombo: kc)) {
                    guard let action = item.action else { return }
                    NSApp.sendAction(action, to: item.target, from: item)
                }
            }
        } else {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
        }

        item.submenu?.items.forEach { syncHotKeys(for: $0) }
    }

    private func restoreTitleCycleIfNeeded() {
        guard titleLines.count > 1 else { return }
        enableTitleCycle()
    }

    private func reapplyOpenMenuStateIfNeeded() {
        guard isOpen else { return }
        hotKeys.forEach { $0.isPaused = true }
        updateOpenMenuItemVisibility()
    }

    private func updateOpenMenuItemVisibility() {
        updateLastUpdatedItem()

        if showsAllStandardItemsWhileOpen {
            [lastUpdatedItem, runInTerminalItem, disablePluginItem, debugPluginItem, aboutItem, swiftBarItem].forEach { $0.isHidden = false }
            return
        }

        lastUpdatedItem.isHidden = plugin?.metadata?.hideLastUpdated ?? false
        runInTerminalItem.isHidden = plugin?.metadata?.hideRunInTerminal ?? false
        disablePluginItem.isHidden = plugin?.metadata?.hideDisablePlugin ?? false
        aboutItem.isHidden = plugin?.metadata?.hideAbout ?? false
        swiftBarItem.isHidden = plugin?.metadata?.hideSwiftBar ?? false
    }

    private func applyShortcut(for item: NSMenuItem, params: MenuLineParameters) {
        item.keyEquivalent = ""
        item.keyEquivalentModifierMask = []

        if params.alternate {
            item.keyEquivalentModifierMask = NSEvent.ModifierFlags.option
        }

        if let kc = params.shortcut {
            item.keyEquivalentModifierMask = kc.modifiers
            item.keyEquivalent = kc.key?.description.lowercased() ?? ""
        }
    }

    /// Recursively update a submenu's children via diffing.
    private func updateSubmenu(of item: NSMenuItem, oldChildren: [MenuItemNode], newChildren: [MenuItemNode]) {
        if newChildren.isEmpty {
            item.submenu = nil
            return
        }

        if item.submenu == nil {
            item.submenu = NSMenu(title: "")
        }

        guard let submenu = item.submenu else { return }

        let childChanges = diffMenuNodes(old: oldChildren, new: newChildren)
        applyDiff(childChanges, oldTree: oldChildren, newTree: newChildren, to: submenu, baseIndex: 0)
    }

    /// Build submenu items from scratch for a newly inserted node.
    private func buildSubmenuItems(for item: NSMenuItem, from node: MenuItemNode) {
        guard !node.children.isEmpty else { return }
        item.submenu = NSMenu(title: "")
        guard let submenu = item.submenu else { return }
        for child in node.children {
            if child.isSeparator {
                submenu.addItem(NSMenuItem.separator())
            } else if let childItem = buildMenuItem(params: MenuLineParameters(line: child.workingLine)) {
                childItem.target = self
                submenu.addItem(childItem)
                buildSubmenuItems(for: childItem, from: child)
            }
        }
    }

    /// Update the "Last Updated" timestamp in the standard menu section.
    private func updateLastUpdatedItem() {
        guard let plugin, let lastUpdated = plugin.lastUpdated else { return }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relativeDate = formatter.localizedString(for: lastUpdated, relativeTo: Date()).capitalized

        if plugin.isStale {
            lastUpdatedItem.title = "⚠️ \(Localizable.MenuBar.LastUpdated.localized) \(relativeDate) (Stale - expected update every \(formatInterval(plugin.updateInterval)))"
        } else {
            lastUpdatedItem.title = "\(Localizable.MenuBar.LastUpdated.localized) \(relativeDate)"
        }
    }
    func addMenuItem(from line: String) {
        let (currentLevel, isSeparator, workingLine) = MenuItemNode.parseLine(line)

        if isSeparator, currentLevel == 0 {
            statusBarMenu.addItem(NSMenuItem.separator())
            return
        }

        var submenu: NSMenu?

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

        if let item = isSeparator ? NSMenuItem.separator() : buildMenuItem(params: MenuLineParameters(line: workingLine)) {
            item.target = self
            (submenu ?? statusBarMenu)?.addItem(item)
            lastMenuItem = item
            prevLevel = currentLevel
            prevItems.insert(item, at: 0)
        }
    }

    func updateMenuTitle(titleLines: [String]) {
        setMenuTitle(title: titleLines.first ?? "􀇾")
        guard titleLines.count > 1 else { return }

        for line in titleLines {
            addMenuItem(from: line)
        }
    }

    func setMenuTitle(title: String) {
        barItem.button?.image = nil

        let lines = title.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let displayText: String
        let isTwoLine: Bool

        if lines.count == 2 {
            // Exactly 2 lines - keep as is for proper multi-line display
            displayText = title
            isTwoLine = true
        } else if lines.count > 2 {
            // More than 2 lines - truncate to first line
            displayText = "\(lines.first ?? "")..."
            isTwoLine = false
        } else {
            // Single line or empty - no change
            displayText = title
            isTwoLine = false
        }

        let params = MenuLineParameters(line: displayText)
        if let image = params.getImage(isMenuBarItem: true) {
            barItem.button?.image = image
            barItem.button?.imagePosition = .imageLeft
        }

        var attributedTitle = atributedTitle(with: params, pad: true, isTwoLine: isTwoLine).title

        // Add stale indicator if plugin hasn't updated within 2x its refresh interval
        if let plugin, plugin.isStale {
            let warningSymbol = "⚠️ "
            let mutableTitle = NSMutableAttributedString(string: warningSymbol)
            mutableTitle.append(attributedTitle)
            attributedTitle = mutableTitle
        }

        barItem.button?.attributedTitle = attributedTitle
    }

    func cycleThroughTitles() {
        currentTitleLineIndex += 1
        if !titleLines.indices.contains(currentTitleLineIndex) {
            currentTitleLineIndex = 0
        }
        setMenuTitle(title: titleLines[currentTitleLineIndex])
    }

    private func formatInterval(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.maximumUnitCount = 2
        return formatter.string(from: interval) ?? "\(Int(interval))s"
    }

    // do the following conversion:
    // \\ -> \
    // \n -> LF
    // \t -> TAB
    // \c -> c  any char else
    func unescape(_ str: String) -> String {
        var newstr = ""
        var backslash = false
        for c in str {
            if backslash {
                backslash = false
                if c == "n" {
                    newstr += "\n"
                    continue
                }
                if c == "t" {
                    newstr += "\t"
                    continue
                }
            } else {
                if c == "\\" {
                    backslash = true
                    continue
                }
            }
            newstr += String(c)
        }
        return newstr
    }

    func atributedTitle(with params: MenuLineParameters, pad: Bool = false, isTwoLine: Bool = false) -> (title: NSAttributedString, tooltip: String) {
        var title = params.trim ? params.title.trimmingCharacters(in: .whitespaces) : params.title
        guard !title.isEmpty else { return (NSAttributedString(), "") }

        if params.emojize, !params.symbolize {
            title = title.emojify()
        }
        let fullTitle = title
        if let length = params.length, length < title.count {
            title = String(title.prefix(length)).appending("...")
        }

        title = unescape(title)

        let fontSize = params.size ?? 0
        let color = params.color ?? NSColor.controlTextColor
        var font = NSFont.menuBarFont(ofSize: fontSize)
        if let fontName = params.font, let customFont = NSFont(name: fontName, size: fontSize) {
            font = customFont
        }
        // Use custom vertical alignment if provided, otherwise use default offset
        let offset = params.valign ?? (isTwoLine ? font.twoLineMenuBarOffset : font.menuBarOffset)

        let style = NSMutableParagraphStyle()
        style.alignment = pad ? .center : .left

        // Configure tab stops for proper tab alignment (issue #455)
        // Add tab stops every 100 points to support tab-aligned text
        var tabStops: [NSTextTab] = []
        for i in 1...10 {
            let location = CGFloat(i * 100)
            tabStops.append(NSTextTab(textAlignment: .left, location: location))
        }
        style.tabStops = tabStops

        var attributedTitle = NSMutableAttributedString(string: title)
        if #available(macOS 12, *), params.md, let parsedMD = try? NSAttributedString(markdown: title) {
            attributedTitle = NSMutableAttributedString(attributedString: parsedMD)
        }

        if params.symbolize, !params.ansi {
            attributedTitle.symbolize(font: font, colors: params.sfcolors, sfsize: params.sfsize)
        }
        if params.ansi {
            attributedTitle = title.colorizedWithANSIColor()
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

        // Assign action when color is set so macOS renders the item as enabled,
        // allowing the custom color to display instead of the disabled grey.
        let needsAction = params.hasAction || params.color != nil
        let item = NSMenuItem(title: params.title,
                              action: needsAction ? #selector(perfomMenutItemAction) : nil,
                              keyEquivalent: "")
        item.representedObject = params
        let title = atributedTitle(with: params)
        item.attributedTitle = title.title

        item.toolTip = params.tooltip?.replacingOccurrences(of: "\\n", with: "\n")

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

        if #available(macOS 14.0, *) {
            if !params.badge.isEmpty {
                item.badge = NSMenuItemBadge(string: params.badge)
            }
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
        if refreshOnOpen, plugin?.type == .Executable {
            refreshAndShowMenu()
            return
        }
        barItem.menu = statusBarMenu
        barItem.button?.performClick(nil)
    }

    func refreshAndShowMenu() {
        os_log("Refreshing for refreshOnOpen plugin", log: Log.plugin, type: .info)
        plugin?.lastRefreshReason = .MenuOpen
        let content = plugin?.invoke()
        // Keep plugin.content in sync with the displayed content so that subsequent
        // scheduled refreshes are not suppressed by the content didSet guard.
        plugin?.content = content
        _updateMenu(content: content)
        barItem.menu = statusBarMenu
        barItem.button?.performClick(nil)
    }

    func dimOnManualRefresh() {
        guard delegate.prefs.dimOnManualRefresh else { return }
        barItem.button?.appearsDisabled = true
    }

    static func actionKinds(for params: MenuLineParameters) -> [ActionKind] {
        var actions: [ActionKind] = []

        if let url = params.href?.getURL(), url.absoluteString != "." {
            actions.append(.href)
        }

        if params.bash != nil {
            actions.append(.bash)
        }

        if params.stdin != nil {
            actions.append(.stdin)
        }

        if params.refresh {
            actions.append(.refresh)
        }

        return actions
    }

    @discardableResult func performItemAction(params: MenuLineParameters) -> Bool {
        var out = false
        let actions = Self.actionKinds(for: params)
        let shouldTriggerStandaloneRefresh = actions.contains(.refresh) && !actions.contains(.bash) && !actions.contains(.stdin)
        let refreshLock = NSLock()
        var didRequestRefresh = false

        let requestRefreshIfNeeded: () -> Void = { [weak self] in
            guard params.refresh else { return }

            refreshLock.lock()
            defer { refreshLock.unlock() }
            guard !didRequestRefresh else { return }
            didRequestRefresh = true
            self?.plugin?.refresh(reason: .MenuAction)
        }

        defer {
            if params.color != nil, out {
                updateMenu(content: plugin?.content) // dumb fix for #221, ideally come up with something better...
            }
        }

        if actions.contains(.href), let url = params.href?.getURL() {
            if params.webView {
                showWebPopover(
                    url: url,
                    widht: params.webViewWidth,
                    height: params.webViewHeight,
                    zoom: params.webViewZoom
                )
            } else {
                NSWorkspace.shared.open(url)
            }

            out = true
        }

        if let bash = params.bash {
            AppShared.runInTerminal(script: bash, args: params.bashParams, runInBackground: !params.terminal,
                                    env: plugin?.env ?? [:], runInBash: plugin?.metadata?.shouldRunInBash ?? true)
            {
                if params.refresh {
                    requestRefreshIfNeeded()
                }
            }
            out = true
        }

        if let stdinInput = params.stdin {
            guard let plugin else {
                os_log("No plugin available to handle stdin input", log: Log.plugin, type: .error)
                return out
            }

            do {
                try plugin.writeStdin(stdinInput)

                if params.refresh {
                    requestRefreshIfNeeded()
                }

                out = true
            } catch {
                plugin.error = error
                os_log("Failed to write stdin for plugin %{public}@: %{public}@", log: Log.plugin, type: .error, plugin.name, error.localizedDescription)
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isOpen else { return }
                    self.showErrorPopover()
                }
            }

        }

        if shouldTriggerStandaloneRefresh {
            dimOnManualRefresh()
            requestRefreshIfNeeded()
            out = true
        }

        return out
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
        var filesURL: [URL] = []
        var url: URL?

        let pasteBoard = sender.draggingPasteboard

        if let urls = pasteBoard.readObjects(forClasses: [NSURL.self]) as? [URL] {
            // process URL drop
            if urls.count == 1, let droppedURL = urls.first, !droppedURL.isFileURL {
                url = droppedURL
            } else {
                filesURL = urls
            }
        }

        if !filesURL.isEmpty {
            // swiftformat:disable all
            env["DROPPED_FILES"] = filesURL.compactMap{$0.absoluteString.URLEncoded}.joined(separator: ",")
            // swiftformat:enable all
        }

        if let url {
            env["DROPPED_URL"] = url.absoluteString
        }

        guard let scriptPath = plugin?.file,
              env.keys.contains("DROPPED_FILES") || env.keys.contains("DROPPED_URL")
        else { return false }
        env["LAUNCHED_FROM_DROP_ACTION"] = "TRUE"
        AppShared.runInTerminal(script: scriptPath, runInBackground: true, env: env, runInBash: plugin?.metadata?.shouldRunInBash ?? true)
        return true
    }
}

extension MenubarItem: NSPopoverDelegate {
    func popoverShouldDetach(_: NSPopover) -> Bool {
        true
    }

    func popoverDidDetach(_ popover: NSPopover) {
        // For webPopover, configure the detached window properly
        if popover == webPopover, let window = popover.contentViewController?.view.window {
            // Set the window to have proper controls
            window.styleMask = [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
            ]
            window.isReleasedWhenClosed = false

            // Set a minimum window size to ensure controls are visible
            window.minSize = NSSize(width: 300, height: 200)

            // Set window title to match the plugin name
            window.title = "‎ SwiftBar: \(plugin?.name ?? "")"

            // Stop the popup monitor when detached to prevent auto-closing on outside clicks
            stopPopupMonitor()
        }
    }
}
