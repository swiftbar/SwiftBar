import Cocoa

extension NSFont {
    var menuBarOffset: CGFloat {
        switch pointSize {
        case 0 ..< 2:
            2.5
        case 2 ..< 5:
            2
        case 5 ..< 8:
            1.5
        case 8 ..< 10:
            1
        case 10 ..< 13:
            0.5
        case 13 ..< 15:
            0
        case 15 ..< 17:
            -0.5
        case 17 ..< 20:
            -1
        case 20 ..< 22:
            -1.5
        case 22 ..< 24:
            -2
        case 24 ..< 26:
            -2.5
        case 26 ..< 28:
            -3
        default:
            0
        }
    }

    var twoLineMenuBarOffset: CGFloat {
        // Adjust offset for 2-line content (move up slightly to center better)
        menuBarOffset - (pointSize * 0.15)
    }
}
