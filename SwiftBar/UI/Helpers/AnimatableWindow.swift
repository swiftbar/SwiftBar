import AppKit
import Foundation

class AnimatableWindow: NSWindow {
    var lastContentSize: CGSize = .zero

    override func setContentSize(_ size: NSSize) {
        if lastContentSize == size { return }
        lastContentSize = size
        animator().setFrame(NSRect(origin: frame.origin, size: size), display: true, animate: true)
    }
}
