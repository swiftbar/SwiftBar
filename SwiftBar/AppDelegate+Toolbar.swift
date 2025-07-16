import AppKit

extension NSToolbarItem.Identifier {
    static let sendFeedback = NSToolbarItem.Identifier(rawValue: "sendFeedback")
    static let search = NSToolbarItem.Identifier(rawValue: "search")
    static let refresh = NSToolbarItem.Identifier(rawValue: "refresh")
}

extension NSToolbar {
    static let repositoryToolbar: NSToolbar = {
        let toolbar = NSToolbar(identifier: "RepositoryToolbar")
        toolbar.displayMode = .iconOnly
        return toolbar
    }()
}

extension AppDelegate: NSToolbarDelegate {
    func setupToolbar() {
        NSToolbar.repositoryToolbar.delegate = self
        if #available(OSX 11.0, *) {
            repositoryToolbarSearchItem = NSSearchToolbarItem(itemIdentifier: .search)
            guard let searchField = (repositoryToolbarSearchItem as? NSSearchToolbarItem)?.searchField else { return }
            searchField.delegate = self
        }
    }

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .flexibleSpace, .search, .sendFeedback, .refresh]
    }

    func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .flexibleSpace, .search, .sendFeedback, .refresh]
    }

    func toolbar(_: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar _: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .sendFeedback:
            var button = if #available(OSX 11.0, *) {
                NSButton(image: NSImage(systemSymbolName: "ant", accessibilityDescription: "")!, target: nil, action: #selector(sendFeedback))
            } else {
                NSButton(title: "Feedback", target: nil, action: #selector(sendFeedback))
            }
            button.bezelStyle = .texturedRounded
            return customToolbarItem(itemIdentifier: .sendFeedback, label: Localizable.MenuBar.SendFeedback.localized,
                                     paletteLabel: Localizable.MenuBar.SendFeedback.localized, toolTip: "", itemContent: button)
        case .search:
            return repositoryToolbarSearchItem
        case .refresh:
            var button = if #available(OSX 11.0, *) {
                NSButton(image: NSImage(systemSymbolName: "arrow.counterclockwise.circle", accessibilityDescription: "")!, target: nil, action: #selector(refresh))
            } else {
                NSButton(title: "Refresh", target: nil, action: #selector(refresh))
            }
            button.bezelStyle = .texturedRounded
            return customToolbarItem(itemIdentifier: .refresh, label: Localizable.MenuBar.GetPlugins.localized,
                                     paletteLabel: Localizable.MenuBar.GetPlugins.localized, toolTip: "", itemContent: button)
        default:
            return nil
        }
    }

    @objc func sendFeedback() {
        NSWorkspace.shared.open(URL(string: "https://github.com/matryer/bitbar-plugins/issues")!)
    }

    @objc func refresh() {
        AppShared.refreshRepositoryData()
    }

    func customToolbarItem(
        itemIdentifier: NSToolbarItem.Identifier,
        label: String,
        paletteLabel: String,
        toolTip: String,
        itemContent: NSButton
    ) -> NSToolbarItem? {
        let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)

        toolbarItem.label = label
        toolbarItem.paletteLabel = paletteLabel
        toolbarItem.toolTip = toolTip
        toolbarItem.view = itemContent

        let menuItem = NSMenuItem()
        menuItem.submenu = nil
        menuItem.title = label
        toolbarItem.menuFormRepresentation = menuItem

        return toolbarItem
    }
}

extension AppDelegate: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        if #available(OSX 11.0, *) {
            guard let searchField = (repositoryToolbarSearchItem as? NSSearchToolbarItem)?.searchField,
                  obj.object as? NSSearchField === searchField
            else { return }
            let searchString = searchField.stringValue
            NotificationCenter.default.post(name: .repositoirySearchUpdate, object: nil, userInfo: ["query": searchString])
        }
    }
}
