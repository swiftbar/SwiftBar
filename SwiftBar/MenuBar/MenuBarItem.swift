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
        // The action must fire on mouse *up*: on mouse down the button cell is
        // still inside trackMouse(_:inRect:ofView:untilMouseUp:), and an action
        // that opens the menu from there lets the menu's tracking session
        // consume the physical mouse-up. The cell's tracking loop then resumes
        // waiting for a mouse-up that never arrives and silently swallows
        // subsequent clicks until the cursor leaves the button.
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        return item
    }()

    let statusBarMenu: NSMenu
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
    /// One-shot: the current showMenu() was initiated by an option-click,
    /// so menuWillOpen must reveal the hidden standard items even if the
    /// option key is released between the mouse-up and the menu opening.
    /// Consumed in menuWillOpen, like hotkeyTrigger.
    var pendingOptionClickReveal = false
    /// Reads the live hardware modifier state. `NSApp.currentEvent` is not
    /// reliable in `menuWillOpen`: during status-item menu tracking on
    /// macOS 27 it holds an unrelated event (e.g. mouse-moved) whose flags
    /// never contain `.option`, so option-click detection must query
    /// `NSEvent.modifierFlags` instead. Injectable for tests.
    var optionKeyIsPressed: () -> Bool = { NSEvent.modifierFlags.contains(.option) }

    /// Tracks the current tree of parsed menu nodes for incremental diffing.
    var currentMenuTree: [MenuItemNode] = []
    /// Header lines from the last rendered content, used to detect header changes.
    var currentHeaderLines: [String] = []
    /// Number of NSMenuItems that belong to plugin content (header + separator + body).
    var pluginItemCount: Int = 0

    /// Tracks which fold parent NSMenuItems are currently expanded.
    private var expandedFoldItems: Set<ObjectIdentifier> = []
    /// Fold expansion state tracked by working line, survives full rebuilds.
    private var expandedFoldLines: Set<String> = []
    /// NSMenuItems injected as fold children, keyed by parent NSMenuItem identity.
    private var foldChildItems: [ObjectIdentifier: [NSMenuItem]] = [:]
    private weak var highlightedFoldItem: NSMenuItem?

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

    init(title: String, plugin: Plugin? = nil, visibilityDidChange: ((Bool) -> Void)? = nil, statusBarMenu: NSMenu = NSMenu(title: "")) {
        self.visibilityDidChange = visibilityDidChange
        self.statusBarMenu = statusBarMenu
        super.init()
        barItem.button?.action = #selector(barItemClicked)
        barItem.button?.target = self
        guard plugin != nil else {
            barItem.button?.title = title
            buildStandardMenu()
            syncMenuAttachment()
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

        if plugin != nil {
            let removedKeys = removeStatusItemVisibilityKeys()
            for key in removedKeys {
                os_log("Removed NSStatusItem visibility key after menu item visibility change: %{public}@", log: Log.diagnostics, type: .info, key)
            }
        }

        guard visibilityChanged else { return }
        visibilityDidChange?(isVisible)
    }
}

extension MenubarItem: NSMenuDelegate {
    func menuWillOpen(_: NSMenu) {
        isOpen = true
        showsAllStandardItemsWhileOpen = pendingOptionClickReveal || (!hotkeyTrigger && optionKeyIsPressed())

        if #available(macOS 12, *) {
            // nothing todo here
        } else if !AppShared.isReduceTransparencyEnabled {
            var params = MenuLineParameters(line: currentTitleLine)
            params.params["color"] = "white"
            params.params["sfcolor"] = "white"
            barItem.button?.attributedTitle = atributedTitle(with: params, pad: true).title
        }

        hotkeyTrigger = false
        pendingOptionClickReveal = false
        reapplyOpenMenuStateIfNeeded()
    }

    func menuDidClose(_ menu: NSMenu) {
        isOpen = false
        showsAllStandardItemsWhileOpen = false
        // Also resyncs the menu attachment (isOpen is false again): items
        // whose clicks are handled in barItemClicked get the menu detached,
        // everyone else keeps it attached so AppKit handles the next click
        // natively.
        setMenuTitle(title: currentTitleLine)
        hotKeys.forEach { $0.isPaused = false }
        if let foldView = highlightedFoldItem?.view as? FoldableMenuItemView {
            foldView.setHighlighted(false)
        }
        highlightedFoldItem = nil

        // Plugins can opt out of fold state persistence with the
        // collapseOnClose metadata flag: every fold section returns to
        // collapsed when the menu closes, so the next open starts compact.
        if plugin?.metadata?.collapseOnClose == true {
            collapseAllFolds()
        }

        // if plugin was refreshed when menu was opened refresh on menu close
        if refreshOnClose {
            menuUpdateQueue.addOperation { [weak self] in
                self?.refreshOnClose = false
                self?.disableTitleCycle()
                self?.updateMenu(content: self?.plugin?.content)
            }
        }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        if Self.shouldRewriteAttributedTitlesDuringMenuTracking() {
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
        // On macOS 26 and later a colored attributed title is left alone while
        // the menu tracks. Swapping its foreground color for the highlight and
        // calling itemChanged(_:) made AppKit redraw the row in the default
        // label color once the highlight moved on, and only reopening the menu
        // brought the color back (#541). A plain attributed title keeps its
        // color through the highlight instead, the way an ansi= row already does.

        if let previousFoldView = highlightedFoldItem?.view as? FoldableMenuItemView {
            previousFoldView.setHighlighted(false)
        }
        if let nextFoldView = item?.view as? FoldableMenuItemView {
            nextFoldView.setHighlighted(true)
            highlightedFoldItem = item
        } else {
            highlightedFoldItem = nil
        }
    }

    static func shouldRewriteAttributedTitlesDuringMenuTracking(
        on operatingSystemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> Bool {
        // Replacing an attributed title while AppKit is tracking a macOS 26+
        // menu can clip its final row. It also removes inline image attachments.
        operatingSystemVersion.majorVersion < 26
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
        let copySystemReportItem = NSMenuItem(title: Localizable.MenuBar.CopySystemReport.localized, action: #selector(copySystemReport), keyEquivalent: "")
        let openSystemReportItem = NSMenuItem(title: Localizable.MenuBar.OpenSystemReport.localized, action: #selector(openSystemReport), keyEquivalent: "")
        let aboutSwiftbarItem = NSMenuItem(title: Localizable.MenuBar.AboutPlugin.localized, action: #selector(aboutSwiftBar), keyEquivalent: "")
        let quitItem = NSMenuItem(title: Localizable.App.Quit.localized, action: #selector(quit), keyEquivalent: "q")
        let showErrorItem = NSMenuItem(title: Localizable.MenuBar.ShowError.localized, action: #selector(showErrorPopover), keyEquivalent: "")
        for item in [refreshAllItem, enableAllItem, disableAllItem, preferencesItem, openPluginFolderItem, changePluginFolderItem, getPluginsItem, quitItem, disablePluginItem, debugPluginItem, terminatePluginItem, aboutItem, aboutSwiftbarItem, runInTerminalItem, showErrorItem, sendFeedbackItem, copySystemReportItem, openSystemReportItem] {
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
        menu.addItem(copySystemReportItem)
        menu.addItem(openSystemReportItem)
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

    @objc func copySystemReport() {
        _ = delegate.pluginManager.copyLatestSystemReportToPasteboard()
    }

    @objc func openSystemReport() {
        delegate.pluginManager.openLatestSystemReport()
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
        // The attachment decision depends on plugin metadata (refreshOnOpen,
        // type), which can change without a title change — the incremental
        // path skips setMenuTitle then, so re-sync on every content update.
        defer { syncMenuAttachment() }

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
        expandedFoldItems.removeAll()
        foldChildItems.removeAll()
        // Note: expandedFoldLines is intentionally NOT cleared here
        // so that fold state survives full rebuilds.
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

        // Build the tree first so fold items know their children at construction time
        let tree = MenuItemNode.buildMenuTree(from: parts.body)
        for node in tree {
            if node.isSeparator {
                statusBarMenu.addItem(NSMenuItem.separator())
            } else if let item = buildMenuItem(params: MenuLineParameters(line: node.workingLine)) {
                statusBarMenu.addItem(item)
                buildSubmenuItems(for: item, from: node, into: statusBarMenu)
            }
        }

        // Track how many items belong to the plugin content.
        // Includes title/header items + optional separator + body root-level items + fold children.
        // Standard menu items (SwiftBar submenu, etc.) are appended after this point.
        currentHeaderLines = parts.header
        currentMenuTree = tree
        pluginItemCount = statusBarMenu.items.count
        syncHotKeys()
        buildStandardMenu()
    }

    /// Body-only incremental update for use while the menu is open.
    /// Patches body items in-place without touching the header or title.
    /// Called from the content subscriber when the menu is open.
    /// Incremental update: diffs old vs new tree and patches the live menu.
    /// This runs while the menu may be open, enabling live content updates
    /// without waiting for the menu to close and rebuild.
    private func incrementalUpdateMenu(content: String, header: [String], body: [String], newTree: [MenuItemNode]) {
        dispatchPrecondition(condition: .onQueue(.main))

        if body.isEmpty || header.count != currentHeaderLines.count {
            fullRebuildMenu(content: content)
            return
        }

        // Update header/title in-place if content changed (avoids full rebuild)
        if header != currentHeaderLines {
            titleLines = header
            currentHeaderLines = header
            setMenuTitle(title: header.first ?? "")
            // Patch header items in the menu for multi-line titles
            if header.count > 1 {
                for (index, line) in header.enumerated() {
                    guard index < statusBarMenu.items.count else { break }
                    let item = statusBarMenu.items[index]
                    guard !item.isSeparatorItem else { break }
                    patchMenuItem(item, with: MenuLineParameters(line: line))
                }
            }
        }

        // Calculate the base index in statusBarMenu where body items start.
        // Layout: [title items...] [separator] [body items...] [standard items...]
        let oldBodyCount = countMenuItems(in: currentMenuTree, for: statusBarMenu)
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
        pluginItemCount = pluginItemCount - oldBodyCount + countMenuItems(in: newTree, for: statusBarMenu)
        currentMenuTree = newTree
        restoreTitleCycleIfNeeded()
        syncHotKeys()
        if isOpen {
            reapplyOpenMenuStateIfNeeded()
        } else {
            updateLastUpdatedItem()
        }
    }

    /// Count the NSMenuItems in the flat menu that belong to the plugin content.
    /// Includes root-level nodes plus any fold children injected as siblings.
    /// Counts only fold children that are actually inserted into the target menu.
    private func countMenuItems(in nodes: [MenuItemNode], for menu: NSMenu) -> Int {
        var uniqueChildren = Set<ObjectIdentifier>()
        for items in foldChildItems.values {
            for item in items {
                guard item.menu === menu else { continue }
                uniqueChildren.insert(ObjectIdentifier(item))
            }
        }
        return nodes.count + uniqueChildren.count
    }

    /// Apply a diff to a live NSMenu, patching items in-place.
    private func applyDiff(_ changes: [MenuItemChange], oldTree: [MenuItemNode], newTree: [MenuItemNode], to menu: NSMenu, baseIndex: Int) {
        applyRemovals(changes, oldTree: oldTree, to: menu, baseIndex: baseIndex)
        applyUpdatesAndInserts(changes, oldTree: oldTree, newTree: newTree, to: menu, baseIndex: baseIndex)
    }

    /// Compute the actual menu index for a node index, accounting for fold children
    /// inserted as siblings before this position.
    private func actualMenuIndex(for nodeIndex: Int, in menu: NSMenu, baseIndex: Int, nodes: [MenuItemNode]) -> Int {
        var offset = 0
        for i in 0 ..< nodeIndex {
            let itemIndex = baseIndex + i + offset
            guard itemIndex < menu.items.count else { break }
            let item = menu.items[itemIndex]
            let key = ObjectIdentifier(item)
            if let children = foldChildItems[key] {
                offset += children.count
            }
        }
        return baseIndex + nodeIndex + offset
    }

    /// Remove items from the menu. Removals arrive in reverse index order from
    /// diffMenuNodes so that earlier indices are not invalidated.
    private func applyRemovals(_ changes: [MenuItemChange], oldTree: [MenuItemNode], to menu: NSMenu, baseIndex: Int) {
        for change in changes {
            if case .remove(let oldIndex) = change {
                let menuIndex = actualMenuIndex(for: oldIndex, in: menu, baseIndex: baseIndex, nodes: oldTree)
                guard menuIndex < menu.items.count else { continue }
                let item = menu.items[menuIndex]

                // Remove fold children first (in reverse to preserve indices)
                let key = ObjectIdentifier(item)
                if let children = foldChildItems.removeValue(forKey: key) {
                    for child in children.reversed() {
                        if let childIndex = menu.items.firstIndex(of: child) {
                            // Clean up nested fold state
                            let childKey = ObjectIdentifier(child)
                            foldChildItems.removeValue(forKey: childKey)
                            expandedFoldItems.remove(childKey)
                            if let childParams = child.representedObject as? MenuLineParameters {
                                expandedFoldLines.remove(childParams.title)
                            }
                            menu.removeItem(at: childIndex)
                        }
                    }
                }
                expandedFoldItems.remove(key)
                if let params = item.representedObject as? MenuLineParameters {
                    expandedFoldLines.remove(params.title)
                }
                menu.removeItem(at: menu.index(of: item))
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
                let menuIndex = actualMenuIndex(for: newIndex, in: menu, baseIndex: baseIndex, nodes: newTree)
                applyUpdate(menu: menu, menuIndex: menuIndex, oldNode: oldTree[oldIndex], newNode: newTree[newIndex])

            case .insert(let newIndex):
                let menuIndex = actualMenuIndex(for: newIndex, in: menu, baseIndex: baseIndex, nodes: newTree)
                applyInsert(menu: menu, menuIndex: menuIndex, newNode: newTree[newIndex])

            case .remove:
                break // Already handled in applyRemovals
            }
        }
    }

    /// Update a single existing menu item to match a new node.
    private func applyUpdate(menu: NSMenu, menuIndex: Int, oldNode: MenuItemNode, newNode: MenuItemNode) {
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
                menu.insertItem(newItem, at: menuIndex)
                buildSubmenuItems(for: newItem, from: newNode, into: menu)
            }
        } else {
            let oldParams = MenuLineParameters(line: oldNode.workingLine)
            let newParams = MenuLineParameters(line: newNode.workingLine)
            if !oldNode.contentEqual(to: newNode) {
                if let foldView = existingItem.view as? FoldableMenuItemView, newParams.fold {
                    let titleInfo = foldableTitleInfo(with: newParams)
                    foldView.update(
                        attributedTitle: titleInfo.normal,
                        highlightedTitle: titleInfo.highlighted,
                        image: newParams.image,
                        badge: newParams.badge
                    )
                    // Keep the title-keyed fold state working after a rename:
                    // toggleFoldItem and collapseNestedFolds read the title
                    // from representedObject.
                    moveFoldExpansionKey(for: existingItem, to: newParams)
                    existingItem.representedObject = newParams
                } else {
                    patchMenuItem(existingItem, with: newParams)
                }
            }
            let foldModeChanged = oldParams.fold != newParams.fold
            if oldNode.children != newNode.children || foldModeChanged {
                if newParams.fold {
                    if foldModeChanged {
                        existingItem.submenu = nil
                    }
                    if updateFoldChildren(of: existingItem, from: newNode, oldNode: oldNode, in: menu) {
                        // The fold subtree cannot be patched in place. Rebuild it
                        // from this outermost fold item so every ancestor list in
                        // foldChildItems is refreshed together; parent expansion
                        // state survives via expandedFoldItems/expandedFoldLines.
                        transferFoldExpansionState(of: existingItem, from: oldNode, to: newNode)
                        removeFoldChildren(of: existingItem, from: menu)
                        buildFoldChildren(for: existingItem, from: newNode, into: menu)
                    }
                } else if oldParams.fold {
                    // Transitioning from fold to submenu: clean up fold children first
                    removeFoldChildren(of: existingItem, from: menu)
                    existingItem.view = nil
                    updateSubmenu(of: existingItem, oldChildren: [], newChildren: newNode.children)
                } else {
                    updateSubmenu(of: existingItem, oldChildren: oldNode.children, newChildren: newNode.children)
                }
            }
            configureAction(on: existingItem, for: newParams)
        }
    }

    /// Insert a new menu item for a node that did not exist in the old tree.
    private func applyInsert(menu: NSMenu, menuIndex: Int, newNode: MenuItemNode) {
        let clampedIndex = min(menuIndex, menu.items.count)
        if newNode.isSeparator {
            menu.insertItem(NSMenuItem.separator(), at: clampedIndex)
        } else if let newItem = buildMenuItem(params: MenuLineParameters(line: newNode.workingLine)) {
            menu.insertItem(newItem, at: clampedIndex)
            buildSubmenuItems(for: newItem, from: newNode, into: menu)
        }
    }

    /// Update fold children for an existing fold item when its children change.
    /// Patches existing fold child NSMenuItems in-place to preserve object identity
    /// (and thus fold expansion state).
    ///
    /// Returns true when the subtree cannot be patched in place — a child count
    /// changed or a child switched between fold and submenu modes, at any depth.
    /// The caller must then rebuild from the outermost fold item: ancestors'
    /// `foldChildItems` lists are flat and include nested grandchildren, so a
    /// local rebuild at a nested level would strand the ancestors' references
    /// to the replaced NSMenuItems. Across such rebuilds, nested expansion
    /// state survives only via `expandedFoldLines`, which is keyed by title
    /// by design; see `transferFoldExpansionState`.
    private func updateFoldChildren(of item: NSMenuItem, from newNode: MenuItemNode, oldNode: MenuItemNode?, in menu: NSMenu) -> Bool {
        // The item's own view is already patched by the caller: applyUpdate
        // for the outermost fold item, the child loop below for nested ones.

        guard let directItems = directFoldChildItems(of: item) else {
            // No existing fold children — build from scratch. This can only be
            // the outermost fold item: the caller's pre-scan rejects children
            // whose fold-parent state changed, so the recursion below is only
            // entered for children that already have an entry. Building here
            // therefore cannot strand ancestor bookkeeping.
            buildFoldChildren(for: item, from: newNode, into: menu)
            return false
        }

        // Patch direct children in-place where possible
        let newRendered = Self.renderableFoldChildren(of: newNode)
        let oldRendered = oldNode.map(Self.renderableFoldChildren)

        // Child count changed — the subtree must be rebuilt from the top.
        guard directItems.count == newRendered.count else {
            return true
        }

        // Detect shape changes among direct children before patching anything;
        // these also require a rebuild from the top.
        for (idx, entry) in newRendered.enumerated() {
            // A child switching between separator and regular item cannot be
            // patched in place.
            if directItems[idx].isSeparatorItem != entry.node.isSeparator {
                return true
            }
            guard let childParams = entry.params else { continue }
            let wasFoldParent = foldChildItems[ObjectIdentifier(directItems[idx])] != nil
            let isFoldParent = childParams.fold && !entry.node.children.isEmpty
            if wasFoldParent != isFoldParent {
                return true
            }
        }

        // Expansion-key moves are batched and applied atomically after the
        // loop, so sibling renames that exchange titles keep both keys. When
        // the loop bails into a rebuild instead, pending moves are dropped:
        // transferFoldExpansionState recomputes every move from the node trees.
        var keyMoves: [(remove: String, insert: String)] = []

        for (idx, entry) in newRendered.enumerated() {
            let existingChild = directItems[idx]

            guard let childParams = entry.params else {
                // Separators don't need patching
                continue
            }

            let newChild = entry.node
            let isFoldParent = childParams.fold && !newChild.children.isEmpty

            if let foldView = existingChild.view as? FoldableMenuItemView, childParams.fold {
                let titleInfo = foldableTitleInfo(with: childParams)
                foldView.update(
                    attributedTitle: titleInfo.normal,
                    highlightedTitle: titleInfo.highlighted,
                    image: childParams.image,
                    badge: childParams.badge
                )
                // Keep the title-keyed fold state working after a rename:
                // toggleFoldItem and collapseNestedFolds read the title from
                // representedObject.
                if let move = foldExpansionKeyMove(for: existingChild, to: childParams) {
                    keyMoves.append(move)
                }
                existingChild.representedObject = childParams
            } else if existingChild.view == nil {
                patchMenuItem(existingChild, with: childParams)
            }

            let oldChild: MenuItemNode? = if let oldRendered, oldRendered.indices.contains(idx) {
                oldRendered[idx].node
            } else {
                nil
            }

            // Recursively update nested fold children
            if isFoldParent {
                if updateFoldChildren(of: existingChild, from: newChild, oldNode: oldChild, in: menu) {
                    return true
                }
            } else if let oldChild, oldChild.children != newChild.children {
                // A fold child can itself be a submenu parent. Mirror the
                // non-fold update path: refresh its submenu contents (clearing
                // it when the children are gone) and restore action ownership.
                updateSubmenu(of: existingChild, oldChildren: oldChild.children, newChildren: newChild.children)
                configureAction(on: existingChild, for: childParams)
            }
        }
        applyFoldExpansionKeyMoves(keyMoves)
        return false
    }

    /// The expansion-key move an in-place rename of a fold parent requires,
    /// or nil when no key moves. `expandedFoldLines` must track the current
    /// title, both so a later rebuild can restore the expansion and so
    /// collapsing evicts the current key instead of stranding the old one.
    /// Keys move only for expanded folds: a collapsed fold owns no key, and
    /// removing its old title could strip the key from an unrelated expanded
    /// fold sharing it. Must be computed before `representedObject` is
    /// replaced — the old title is read from it.
    private func foldExpansionKeyMove(for item: NSMenuItem, to newParams: MenuLineParameters) -> (remove: String, insert: String)? {
        guard let oldParams = item.representedObject as? MenuLineParameters,
              oldParams.title != newParams.title,
              expandedFoldItems.contains(ObjectIdentifier(item))
        else { return nil }
        return (oldParams.title, newParams.title)
    }

    /// Apply a batch of expansion-key moves atomically: all removals first,
    /// then all insertions, so sibling renames that exchange titles cannot
    /// clobber a just-inserted destination key.
    private func applyFoldExpansionKeyMoves(_ moves: [(remove: String, insert: String)]) {
        expandedFoldLines.subtract(moves.map(\.remove))
        expandedFoldLines.formUnion(moves.map(\.insert))
    }

    private func moveFoldExpansionKey(for item: NSMenuItem, to newParams: MenuLineParameters) {
        guard let move = foldExpansionKeyMove(for: item, to: newParams) else { return }
        applyFoldExpansionKeyMoves([move])
    }

    /// Collect the expansion keys owned by a departing fold subtree so they
    /// cannot pre-expand unrelated folds that reuse the titles later.
    private func evictFoldExpansionKeys(of item: NSMenuItem, into removals: inout Set<String>) {
        guard let children = directFoldChildItems(of: item) else { return }
        if expandedFoldItems.contains(ObjectIdentifier(item)),
           let params = item.representedObject as? MenuLineParameters {
            removals.insert(params.title)
        }
        for child in children {
            evictFoldExpansionKeys(of: child, into: &removals)
        }
    }

    /// Fold-child nodes that render as NSMenuItems, paired with their parsed
    /// parameters (nil for separators). buildMenuTree already excludes
    /// dropdown=false lines from the node tree, but the predicate lives in
    /// one place so every fold update path counts children exactly as
    /// buildFoldChildren renders them and the paths cannot drift.
    private static func renderableFoldChildren(of node: MenuItemNode) -> [(node: MenuItemNode, params: MenuLineParameters?)] {
        node.children.compactMap { child in
            if child.isSeparator {
                return (child, nil)
            }
            let params = MenuLineParameters(line: child.workingLine)
            guard params.dropdown else { return nil }
            return (child, params)
        }
    }

    /// Direct fold child NSMenuItems of a fold parent, skipping the nested
    /// grandchildren that share the same flat `foldChildItems` list.
    private func directFoldChildItems(of item: NSMenuItem) -> [NSMenuItem]? {
        guard let existingChildren = foldChildItems[ObjectIdentifier(item)] else { return nil }
        var directItems: [NSMenuItem] = []
        var index = 0
        while index < existingChildren.count {
            let child = existingChildren[index]
            directItems.append(child)
            if let nestedChildren = foldChildItems[ObjectIdentifier(child)] {
                index += 1 + nestedChildren.count
            } else {
                index += 1
            }
        }
        return directItems
    }

    /// Carry fold expansion state over to renamed fold parents before a
    /// subtree rebuild. Rebuilt NSMenuItems lose their `expandedFoldItems`
    /// identity, so expansion survives only via the title-keyed
    /// `expandedFoldLines` — an expanded fold whose title changes in the same
    /// update would otherwise come back collapsed.
    ///
    /// Children are matched per level by equal title first; those pairs keep
    /// their state through `expandedFoldLines` untouched. The leftovers are
    /// treated as renames only when the unmatched old and new children pair
    /// 1:1 in relative order; a rename amid simultaneous sibling inserts or
    /// removals cannot be paired reliably, so those folds surrender their
    /// keys and come back collapsed (best effort). One rule throughout: keys
    /// move only for expanded folds, all removals apply before all
    /// insertions so crossing renames cannot clobber a just-moved key, and
    /// departing expanded folds surrender their keys so they cannot
    /// pre-expand an unrelated later fold.
    private func transferFoldExpansionState(of item: NSMenuItem, from oldNode: MenuItemNode?, to newNode: MenuItemNode) {
        var removals = Set<String>()
        var insertions = Set<String>()
        collectFoldExpansionTransfers(of: item, from: oldNode, to: newNode, removals: &removals, insertions: &insertions)
        expandedFoldLines.subtract(removals)
        expandedFoldLines.formUnion(insertions)
    }

    private func collectFoldExpansionTransfers(
        of item: NSMenuItem,
        from oldNode: MenuItemNode?,
        to newNode: MenuItemNode,
        removals: inout Set<String>,
        insertions: inout Set<String>
    ) {
        guard let oldNode, let directItems = directFoldChildItems(of: item) else { return }

        var oldEntries: [(node: MenuItemNode, item: NSMenuItem, title: String)] = []
        for (entry, childItem) in zip(Self.renderableFoldChildren(of: oldNode), directItems) {
            guard let params = entry.params else { continue }
            oldEntries.append((entry.node, childItem, params.title))
        }
        let newEntries: [(node: MenuItemNode, title: String)] = Self.renderableFoldChildren(of: newNode)
            .compactMap { entry in entry.params.map { (entry.node, $0.title) } }

        var matchedNewIndices = Set<Int>()
        var unmatchedOld: [(node: MenuItemNode, item: NSMenuItem, title: String)] = []
        for entry in oldEntries {
            let match = newEntries.indices.first {
                !matchedNewIndices.contains($0) && newEntries[$0].title == entry.title
            }
            if let match {
                matchedNewIndices.insert(match)
                collectFoldExpansionTransfers(of: entry.item, from: entry.node, to: newEntries[match].node,
                                              removals: &removals, insertions: &insertions)
            } else {
                unmatchedOld.append(entry)
            }
        }
        let unmatchedNew = newEntries.indices
            .filter { !matchedNewIndices.contains($0) }
            .map { newEntries[$0] }

        guard unmatchedOld.count == unmatchedNew.count else {
            // Siblings were inserted or removed: the leftovers cannot be
            // paired reliably, so departing expanded folds surrender their
            // keys instead of leaving them to pre-expand future look-alikes.
            for old in unmatchedOld {
                evictFoldExpansionKeys(of: old.item, into: &removals)
            }
            return
        }
        for (old, new) in zip(unmatchedOld, unmatchedNew) {
            // Keys move only for expanded folds: a leaf row or collapsed fold
            // owns no key, and evicting its title could strip the key from an
            // unrelated expanded fold sharing it.
            if foldChildItems[ObjectIdentifier(old.item)] != nil,
               expandedFoldItems.contains(ObjectIdentifier(old.item)) {
                removals.insert(old.title)
                insertions.insert(new.title)
            }
            collectFoldExpansionTransfers(of: old.item, from: old.node, to: new.node,
                                          removals: &removals, insertions: &insertions)
        }
    }

    /// Remove all fold children of an item from the menu.
    private func removeFoldChildren(of item: NSMenuItem, from menu: NSMenu) {
        let key = ObjectIdentifier(item)
        if let children = foldChildItems.removeValue(forKey: key) {
            for child in children.reversed() {
                // Recursively remove nested fold children
                let childKey = ObjectIdentifier(child)
                if foldChildItems[childKey] != nil {
                    removeFoldChildren(of: child, from: menu)
                }
                expandedFoldItems.remove(childKey)
                if let idx = menu.items.firstIndex(of: child) {
                    menu.removeItem(at: idx)
                }
            }
        }
    }

    private func configureAction(on item: NSMenuItem, for params: MenuLineParameters) {
        if params.hasAction || params.color != nil {
            item.target = self
            item.action = #selector(perfomMenutItemAction)
        } else if params.fold {
            item.target = self
            item.action = #selector(toggleFoldItem(_:))
        } else if let submenu = item.submenu {
            // AppKit owns actionless submenu routing. Reattaching restores its
            // submenuAction/target pair after a SwiftBar action is removed.
            let isAppKitOwned = item.target === submenu
                && item.action.map(NSStringFromSelector) == "submenuAction:"
            guard !isAppKitOwned else { return }
            item.submenu = nil
            item.target = nil
            item.action = nil
            item.submenu = submenu
        } else {
            item.target = nil
            item.action = nil
        }
    }

    /// Patch an existing NSMenuItem's visible properties to match new parameters.
    private func patchMenuItem(_ item: NSMenuItem, with params: MenuLineParameters) {
        configureAction(on: item, for: params)
        item.representedObject = params

        let title = atributedTitle(with: params)
        configureMenuImage(on: item, title: title.title, params: params)

        item.toolTip = params.tooltip?.replacingOccurrences(of: "\\n", with: "\n")
        if let length = params.length, length < title.title.string.count {
            item.toolTip = title.tooltip
        }

        item.isAlternate = params.alternate

        item.state = params.checked ? .on : .off

        if #available(macOS 14.0, *) {
            item.badge = params.badge.isEmpty ? nil : NSMenuItemBadge(string: params.badge)
        }
    }

    private func foldableTitleInfo(with params: MenuLineParameters) -> (normal: NSAttributedString, highlighted: NSAttributedString) {
        let normalTitle = atributedTitle(with: params).title
        guard !params.ansi else { return (normalTitle, normalTitle) }

        let highlightedTitle = NSMutableAttributedString(attributedString: normalTitle)
        highlightedTitle.addAttribute(
            .foregroundColor,
            value: NSColor.selectedMenuItemTextColor,
            range: NSRange(location: 0, length: highlightedTitle.length)
        )
        return (normalTitle, highlightedTitle)
    }

    enum MenuImagePresentation {
        case native
        case attributed
    }

    func configureMenuImage(
        on item: NSMenuItem,
        title: NSAttributedString,
        params: MenuLineParameters,
        presentation: MenuImagePresentation? = nil
    ) {
        let resolvedPresentation: MenuImagePresentation = if let presentation {
            presentation
        } else if #available(macOS 26.0, *) {
            .attributed
        } else {
            .native
        }

        let image = params.image
        switch resolvedPresentation {
        case .native:
            item.attributedTitle = title
            item.image = image
        case .attributed:
            item.attributedTitle = menuTitle(title, image: image)
            item.image = nil
        }
    }

    private func menuTitle(
        _ title: NSAttributedString,
        image: NSImage?
    ) -> NSAttributedString {
        guard let image else { return title }

        let font = title.length > 0 ? title.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil
        let menuFont = font ?? .menuFont(ofSize: 0)
        let result = NSMutableAttributedString(attachment: .centeredMenuImage(with: image, and: menuFont))
        let spacing = "  "
        result.append(NSAttributedString(string: spacing, attributes: [.font: menuFont]))
        result.append(title)

        let paragraphStyle = (title.length > 0
            ? title.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            : nil)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        paragraphStyle.headIndent = image.size.width + (spacing as NSString).size(withAttributes: [.font: menuFont]).width
        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))

        let firstLineBreak = (result.string as NSString).range(of: "\n")
        if firstLineBreak.location != NSNotFound, NSMaxRange(firstLineBreak) < result.length {
            let continuationStyle = paragraphStyle.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            continuationStyle.firstLineHeadIndent = paragraphStyle.headIndent
            let continuationRange = NSRange(
                location: NSMaxRange(firstLineBreak),
                length: result.length - NSMaxRange(firstLineBreak)
            )
            result.addAttribute(.paragraphStyle, value: continuationStyle, range: continuationRange)
        }
        return result
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
        statusBarMenu.update()
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
    /// When the node's params have `fold=true`, children are inserted as hidden
    /// siblings in the parent menu instead of being placed in an NSSubmenu.
    private func buildSubmenuItems(for item: NSMenuItem, from node: MenuItemNode, into menu: NSMenu? = nil) {
        guard !node.children.isEmpty else { return }

        let params = MenuLineParameters(line: node.workingLine)
        if params.fold, let targetMenu = menu ?? item.menu {
            buildFoldChildren(for: item, from: node, into: targetMenu)
        } else {
            item.submenu = NSMenu(title: "")
            guard let submenu = item.submenu else { return }
            for child in node.children {
                if child.isSeparator {
                    submenu.addItem(NSMenuItem.separator())
                } else if let childItem = buildMenuItem(params: MenuLineParameters(line: child.workingLine)) {
                    submenu.addItem(childItem)
                    buildSubmenuItems(for: childItem, from: child, into: submenu)
                }
            }
        }
    }

    /// Build fold children: insert child items as hidden siblings in the parent menu,
    /// and attach a FoldableMenuItemView to the parent item.
    private func buildFoldChildren(for item: NSMenuItem, from node: MenuItemNode, into menu: NSMenu) {
        let key = ObjectIdentifier(item)
        let params = MenuLineParameters(line: node.workingLine)
        // Check ObjectIdentifier first (incremental), fall back to line-based state (rebuild)
        let isExpanded = expandedFoldItems.contains(key) || expandedFoldLines.contains(params.title)
        if isExpanded {
            expandedFoldItems.insert(key)
        }

        // Attach the foldable view to the parent item
        let titleInfo = foldableTitleInfo(with: params)
        let foldView = FoldableMenuItemView(
            attributedTitle: titleInfo.normal,
            highlightedTitle: titleInfo.highlighted,
            image: params.image,
            badge: params.badge,
            isFolded: !isExpanded
        )
        foldView.onToggle = { [weak self] in
            self?.toggleFoldItem(item)
        }
        item.view = foldView

        // Build child items and insert them as siblings after the parent.
        // Track insertPos rather than using offset, because recursive nested fold
        // calls insert additional items that shift positions.
        var children: [NSMenuItem] = []
        var insertPos = (menu.index(of: item) != -1) ? menu.index(of: item) + 1 : menu.items.count

        for child in node.children {
            let childItem: NSMenuItem
            if child.isSeparator {
                childItem = NSMenuItem.separator()
            } else if let built = buildMenuItem(params: MenuLineParameters(line: child.workingLine)) {
                childItem = built
            } else {
                continue
            }

            childItem.isHidden = !isExpanded
            menu.insertItem(childItem, at: insertPos)
            children.append(childItem)
            insertPos += 1

            // Recursively handle nested folds or submenus
            if !child.children.isEmpty {
                buildSubmenuItems(for: childItem, from: child, into: menu)
                // Collect any fold children that were just added for this nested item
                let nestedKey = ObjectIdentifier(childItem)
                if let nestedChildren = foldChildItems[nestedKey] {
                    // Nested fold children are also hidden when outer fold is collapsed
                    if !isExpanded {
                        nestedChildren.forEach { $0.isHidden = true }
                    }
                    children.append(contentsOf: nestedChildren)
                    insertPos += nestedChildren.count
                }
            }
        }

        foldChildItems[key] = children
    }

    /// Toggle the fold state of a menu item.
    @objc func toggleFoldItem(_ item: NSMenuItem) {
        let key = ObjectIdentifier(item)
        let wasExpanded = expandedFoldItems.contains(key)
        if let foldView = item.view as? FoldableMenuItemView {
            foldView.isFolded = wasExpanded
        }

        if wasExpanded {
            expandedFoldItems.remove(key)
        } else {
            expandedFoldItems.insert(key)
        }

        // Also track by line for cross-rebuild persistence
        if let params = item.representedObject as? MenuLineParameters {
            if wasExpanded {
                expandedFoldLines.remove(params.title)
            } else {
                expandedFoldLines.insert(params.title)
            }
        }

        if let children = foldChildItems[key] {
            for child in children {
                child.isHidden = wasExpanded
            }
            // When collapsing, also collapse any nested folds
            if wasExpanded {
                collapseNestedFolds(in: children)
            }
        }

        if let menu = item.menu {
            menu.update()
        }
    }

    /// Recursively collapse nested fold items within a set of children.
    private func collapseNestedFolds(in items: [NSMenuItem]) {
        for item in items {
            let key = ObjectIdentifier(item)
            guard foldChildItems[key] != nil else { continue }
            expandedFoldItems.remove(key)
            if let params = item.representedObject as? MenuLineParameters {
                expandedFoldLines.remove(params.title)
            }
            if let view = item.view as? FoldableMenuItemView {
                view.isFolded = true
            }
            if let nestedChildren = foldChildItems[key] {
                nestedChildren.forEach { $0.isHidden = true }
                collapseNestedFolds(in: nestedChildren)
            }
        }
    }

    /// Collapse every fold section so the menu opens compact on the next open.
    /// Clears the saved expansion state wholesale, including entries for fold
    /// lines that are not present in the menu right now (a full rebuild keeps
    /// `expandedFoldLines` for lines it dropped, and a fold that turned into a
    /// submenu leaves no `foldChildItems` entry behind), then resets the fold
    /// views and children that are live in the menu.
    private func collapseAllFolds() {
        expandedFoldItems.removeAll()
        expandedFoldLines.removeAll()
        foldAllFoldViews(in: statusBarMenu)
    }

    /// Fold every FoldableMenuItemView and hide its children, recursing into
    /// submenus for fold sections nested inside regular submenu items.
    private func foldAllFoldViews(in menu: NSMenu) {
        for item in menu.items {
            if let view = item.view as? FoldableMenuItemView {
                view.isFolded = true
            }
            if let children = foldChildItems[ObjectIdentifier(item)] {
                children.forEach { $0.isHidden = true }
            }
            if let submenu = item.submenu {
                foldAllFoldViews(in: submenu)
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
        if let image = params.getImage(isMenuBarItem: true, menuBarAppearance: barItem.button?.effectiveAppearance) {
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
        syncMenuAttachment()
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

        let item = NSMenuItem(title: params.title,
                              action: nil,
                              keyEquivalent: "")
        configureAction(on: item, for: params)
        item.representedObject = params
        let title = atributedTitle(with: params)
        configureMenuImage(on: item, title: title.title, params: params)

        item.toolTip = params.tooltip?.replacingOccurrences(of: "\\n", with: "\n")

        if let length = params.length, length < title.title.string.count {
            item.toolTip = title.tooltip
        }

        if params.alternate {
            item.isAlternate = true
            item.keyEquivalentModifierMask = NSEvent.ModifierFlags.option
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
        // Defensive: with the menu attached to the status item AppKit owns
        // the whole click (including press-drag-release) and does not send
        // the button action, so this should never fire; if it ever does,
        // there is nothing to intercept. Either way an aborted dispatch
        // must consume the one-shot hotkey flag: left stale, it would make
        // the next real option-click read as hotkey-driven and run the
        // title action — the very bug #576 fixes.
        guard barItem.menu == nil, let event = NSApp.currentEvent else {
            hotkeyTrigger = false
            return
        }
        handleBarItemClick(eventType: event.type, eventFlagsContainOption: event.modifierFlags.contains(.option))
    }

    /// The detached-path click handler, split from barItemClicked so tests
    /// can drive it without an NSApp event. Unlike menuWillOpen (#564), the
    /// dispatching event is current in barItemClicked, so its flags are the
    /// primary option source; the live hardware state is OR-ed in for
    /// dispatch paths whose current event carries no flags.
    func handleBarItemClick(eventType: NSEvent.EventType, eventFlagsContainOption: Bool) {
        switch Self.routeForBarItemClick(
            eventType: eventType,
            eventFlagsContainOption: eventFlagsContainOption,
            hotkeyTriggered: hotkeyTrigger,
            optionKeyIsPressed: optionKeyIsPressed()
        ) {
        case let .openMenu(revealStandardItems):
            // performClick runs menu tracking synchronously, so menuWillOpen
            // sees the flag before the defer clears it; it is an instance
            // flag rather than an argument because it must also survive
            // refreshAndShowMenu's synchronous plugin invocation. The defer
            // keeps it from leaking into a later open — one that must
            // suppress the reveal, like a hotkey open — when no menu
            // tracking starts to consume it.
            pendingOptionClickReveal = revealStandardItems
            defer { pendingOptionClickReveal = false }
            showMenu()
        case .runTitleAction:
            if performItemAction(params: MenuLineParameters(line: currentTitleLine)) {
                // menuWillOpen never runs on this path, so consume the
                // one-shot hotkey flag here — otherwise the next real
                // option-click would still read as hotkey-driven.
                hotkeyTrigger = false
                return
            }
            showMenu()
        }
    }

    /// A right click always opens the menu, never the title line's action.
    /// The bar button dispatches its action on mouse up, but performClick-
    /// driven opens (hotkeys) dispatch with whatever event happens to be
    /// current — a stale right mouse down must still route to the menu.
    static func eventOpensMenuWithoutTitleAction(_ eventType: NSEvent.EventType) -> Bool {
        eventType == .rightMouseUp || eventType == .rightMouseDown
    }

    enum BarItemClickRoute: Equatable {
        case openMenu(revealStandardItems: Bool)
        case runTitleAction
    }

    /// Resolves a detached-path click. A left click runs the title line's
    /// action, which leaves no left-button route to the menu at all, so an
    /// option-click opens the menu instead and carries the standard-items
    /// reveal with it: option-click is the documented gesture for reaching
    /// the standard items (#560), and under StealthMode there is no fallback
    /// SwiftBar item to reach them through (#576). A hotkey-driven
    /// performClick dispatches with the hotkey's own key event current, so
    /// an option key held as part of the combo must not read as an
    /// option-click — the same suppression menuWillOpen applies through
    /// hotkeyTrigger.
    static func routeForBarItemClick(
        eventType: NSEvent.EventType,
        eventFlagsContainOption: Bool,
        hotkeyTriggered: Bool,
        optionKeyIsPressed: Bool
    ) -> BarItemClickRoute {
        let optionClick = !hotkeyTriggered && (eventFlagsContainOption || optionKeyIsPressed)
        return eventOpensMenuWithoutTitleAction(eventType) || optionClick
            ? .openMenu(revealStandardItems: optionClick)
            : .runTitleAction
    }

    /// Opens the menu for items on the detached path (title line with its
    /// own click action, or refreshOnOpen executables). Known limitation:
    /// because the button action dispatches on mouse up, the menu opens on
    /// release, and press-drag-release cannot select an item here — a menu
    /// opened programmatically cannot adopt an already-held press, and
    /// opening it during the press would let its tracking session consume
    /// the mouse-up the button cell is waiting for, leaving the cell
    /// swallowing every subsequent click. Only a menu attached to the
    /// status item before the press supports the full native gesture; see
    /// syncMenuAttachment().
    /// @objc so tests can override it: extension members are otherwise not
    /// overridable, and a stub is the only way to drive the click handler
    /// without starting real menu tracking.
    @objc func showMenu() {
        if refreshOnOpen, plugin?.type == .Executable {
            refreshAndShowMenu()
            return
        }
        barItem.menu = statusBarMenu
        barItem.button?.performClick(nil)
    }

    func refreshAndShowMenu() {
        dispatchPrecondition(condition: .onQueue(.main))
        os_log("Refreshing for refreshOnOpen plugin", log: Log.plugin, type: .info)
        // Cancel any in-flight or pending run (e.g. a scheduled wake-refresh
        // retry) so a stale result cannot overwrite the content produced here.
        plugin?.operation?.cancel()
        plugin?.lastRefreshReason = .MenuOpen
        let content = plugin?.invoke()
        // Keep plugin.content in sync with the displayed content so that subsequent
        // scheduled refreshes are not suppressed by the content didSet guard.
        plugin?.content = content
        _updateMenu(content: content)
        barItem.menu = statusBarMenu
        barItem.button?.performClick(nil)
    }

    /// Attaches the status bar menu directly to the status item whenever
    /// clicks don't need to be intercepted. With the menu attached, AppKit
    /// owns the whole click natively, so press-drag-release on a menu item
    /// runs its action (#559) — opening the detached menu with a simulated
    /// `performClick(nil)` starts a tracking session that never sees the
    /// still-held physical press and ignores the release. The menu stays
    /// detached when the title line has its own click action (a left click
    /// must run it instead of opening the menu) or when the plugin must
    /// regenerate its content before the menu is shown (`refreshOnOpen`);
    /// those keep the `barItemClicked`/`showMenu` path.
    func syncMenuAttachment() {
        guard !isOpen else { return }
        let attach = Self.shouldAttachMenuToBarItem(
            titleHasAction: !Self.actionKinds(for: MenuLineParameters(line: currentTitleLine)).isEmpty,
            refreshesOnOpen: refreshOnOpen && plugin?.type == .Executable
        )
        barItem.menu = attach ? statusBarMenu : nil
    }

    static func shouldAttachMenuToBarItem(titleHasAction: Bool, refreshesOnOpen: Bool) -> Bool {
        !titleHasAction && !refreshesOnOpen
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
            // The runInTerminal completion arrives on a background queue;
            // refresh is serialized on main.
            DispatchQueue.main.async {
                self?.plugin?.refresh(reason: .MenuAction)
            }
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
