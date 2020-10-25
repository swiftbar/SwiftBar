import Cocoa

struct MenubarItem {
    let barItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    init(title: String) {
        barItem.button?.title = title
    }

    func refresh() {
        barItem
    }

    func show() {
        barItem.isVisible = true
    }

    func hide() {
        barItem.isVisible = false
    }
}
