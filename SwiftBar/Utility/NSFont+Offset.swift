import Cocoa

extension NSFont {
    var menuBarOffset: CGFloat {
        switch pointSize {
        case 0 ..< 2:
            return 2.5
        case 2 ..< 5:
            return 2
        case 5 ..< 8:
            return 1.5
        case 8 ..< 10:
            return 1
        case 10 ..< 13:
            return 0.5
        case 13 ..< 15:
            return 0
        case 15 ..< 17:
            return -0.5
        case 17 ..< 20:
            return -1
        case 20 ..< 22:
            return -1.5
        case 22 ..< 24:
            return -2
        case 24 ..< 26:
            return -2.5
        case 26 ..< 28:
            return -3
        default:
            return 0
        }
    }
}
