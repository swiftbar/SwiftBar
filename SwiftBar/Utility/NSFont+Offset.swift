import Cocoa

extension NSFont {
    var menuBarOffset: CGFloat {
        // Adjusted values to better center text vertically
        // Reduced offsets to fix alignment issues in SwiftBar 2.0
        switch pointSize {
        case 0 ..< 2:
            1.5
        case 2 ..< 5:
            1.0
        case 5 ..< 8:
            0.5
        case 8 ..< 10:
            0.5
        case 10 ..< 13:
            0
        case 13 ..< 15:
            0
        case 15 ..< 17:
            0
        case 17 ..< 20:
            -0.5
        case 20 ..< 22:
            -1.0
        case 22 ..< 24:
            -1.5
        case 24 ..< 26:
            -2.0
        case 26 ..< 28:
            -2.5
        default:
            0
        }
    }

    var twoLineMenuBarOffset: CGFloat {
        // Adjust offset for 2-line content (move up slightly to center better)
        menuBarOffset - (pointSize * 0.15)
    }
}
