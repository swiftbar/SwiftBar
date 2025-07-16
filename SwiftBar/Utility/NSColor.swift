import Cocoa

extension NSColor {
    private static let cssColors: [String: String] = [
        "lightseagreen": "20b2aa", "floralwhite": "fffaf0", "lightgray": "d3d3d3", "darkgoldenrod": "b8860b", "paleturquoise": "afeeee", "goldenrod": "daa520", "skyblue": "87ceeb", "indianred": "cd5c5c", "darkgray": "a9a9a9", "khaki": "f0e68c", "blue": "0000ff", "darkred": "8b0000", "lightyellow": "ffffe0", "midnightblue": "191970", "chartreuse": "7fff00", "lightsteelblue": "b0c4de", "slateblue": "6a5acd", "firebrick": "b22222", "moccasin": "ffe4b5", "salmon": "fa8072", "sienna": "a0522d", "slategray": "708090", "teal": "008080", "lightsalmon": "ffa07a", "pink": "ffc0cb", "burlywood": "deb887", "gold": "ffd700", "springgreen": "00ff7f", "lightcoral": "f08080", "black": "000000", "blueviolet": "8a2be2", "chocolate": "d2691e", "aqua": "00ffff", "darkviolet": "9400d3", "indigo": "4b0082", "darkcyan": "008b8b", "orange": "ffa500", "antiquewhite": "faebd7", "peru": "cd853f", "silver": "c0c0c0", "purple": "800080", "saddlebrown": "8b4513", "lawngreen": "7cfc00", "dodgerblue": "1e90ff", "lime": "00ff00", "linen": "faf0e6", "lightblue": "add8e6", "darkslategray": "2f4f4f", "lightskyblue": "87cefa", "mintcream": "f5fffa", "olive": "808000", "hotpink": "ff69b4", "papayawhip": "ffefd5", "mediumseagreen": "3cb371", "mediumspringgreen": "00fa9a", "cornflowerblue": "6495ed", "plum": "dda0dd", "seagreen": "2e8b57", "palevioletred": "db7093", "bisque": "ffe4c4", "beige": "f5f5dc", "darkorchid": "9932cc", "royalblue": "4169e1", "darkolivegreen": "556b2f", "darkmagenta": "8b008b", "orange red": "ff4500", "lavender": "e6e6fa", "fuchsia": "ff00ff", "darkseagreen": "8fbc8f", "lavenderblush": "fff0f5", "wheat": "f5deb3", "steelblue": "4682b4", "lightgoldenrodyellow": "fafad2", "lightcyan": "e0ffff", "mediumaquamarine": "66cdaa", "turquoise": "40e0d0", "dark blue": "00008b", "darkorange": "ff8c00", "brown": "a52a2a", "dimgray": "696969", "deeppink": "ff1493", "powderblue": "b0e0e6", "red": "ff0000", "darkgreen": "006400", "ghostwhite": "f8f8ff", "white": "ffffff", "navajowhite": "ffdead", "navy": "000080", "ivory": "fffff0", "palegreen": "98fb98", "whitesmoke": "f5f5f5", "gainsboro": "dcdcdc", "mediumslateblue": "7b68ee", "olivedrab": "6b8e23", "mediumpurple": "9370db", "darkslateblue": "483d8b", "blanchedalmond": "ffebcd", "darkkhaki": "bdb76b", "green": "008000", "limegreen": "32cd32", "snow": "fffafa", "tomato": "ff6347", "darkturquoise": "00ced1", "orchid": "da70d6", "yellow": "ffff00", "green yellow": "adff2f", "azure": "f0ffff", "mistyrose": "ffe4e1", "cadetblue": "5f9ea0", "oldlace": "fdf5e6", "gray": "808080", "honeydew": "f0fff0", "peachpuff": "ffdab9", "tan": "d2b48c", "thistle": "d8bfd8", "palegoldenrod": "eee8aa", "mediumorchid": "ba55d3", "rosybrown": "bc8f8f", "mediumturquoise": "48d1cc", "lemonchiffon": "fffacd", "maroon": "800000", "mediumvioletred": "c71585", "violet": "ee82ee", "yellow green": "9acd32", "coral": "ff7f50", "lightgreen": "90ee90", "cornsilk": "fff8dc", "mediumblue": "0000cd", "aliceblue": "f0f8ff", "forestgreen": "228b22", "aquamarine": "7fffd4", "deepskyblue": "00bfff", "lightslategray": "778899", "darksalmon": "e9967a", "crimson": "dc143c", "sandybrown": "f4a460", "lightpink": "ffb6c1", "seashell": "fff5ee",
    ]

    public static func webColor(from colorString: String?) -> NSColor? {
        guard let colorString else { return nil }

        if colorString.hasPrefix("#") {
            return fromHexString(hex: colorString)
        }

        if let color = NSColor.cssColors[colorString] {
            return fromHexString(hex: color)
        }

        return nil
    }

    class func fromHex(hex: Int, alpha _: Float) -> NSColor {
        let red = CGFloat((hex & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((hex & 0xFF00) >> 8) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1.0)
    }

    class func fromHexString(hex: String, alpha _: Float = 1) -> NSColor? {
        var cleanedString = hex
        if hex.hasPrefix("0x") {
            cleanedString = String(hex.dropFirst(2))
        } else if hex.hasPrefix("#") {
            cleanedString = String(hex.dropFirst())
        }
        // Ensure it only contains valid hex characters 0
        let validHexPattern = "[a-fA-F0-9]+"
        if cleanedString.conformsTo(pattern: validHexPattern) {
            var theInt: UInt32 = 0
            let scanner = Scanner(string: cleanedString)
            scanner.scanHexInt32(&theInt)
            let red = CGFloat((theInt & 0xFF0000) >> 16) / 255.0
            let green = CGFloat((theInt & 0xFF00) >> 8) / 255.0
            let blue = CGFloat(theInt & 0xFF) / 255.0
            return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1.0)

        } else {
            return nil
        }
    }
}

extension String {
    func conformsTo(pattern: String) -> Bool {
        let pattern = NSPredicate(format: "SELF MATCHES %@", pattern)
        return pattern.evaluate(with: self)
    }
}

extension NSColor {
    static func colorForAnsi256ColorIndex(index: Int) -> NSColor? {
        var r: CGFloat
        var g: CGFloat
        var b: CGFloat

        if index >= 16, index < 232 {
            let i = CGFloat(index - 16)
            r = (i / 36.0) > 1.0 ? ((i / 36.0) * 40.0 + 55.0) / 255.0 : 0.0
            if i.truncatingRemainder(dividingBy: 36) / 6.0 > 1 {
                g = ((i.truncatingRemainder(dividingBy: 36) / 6.0) * 40.0 + 55.0) / 255.0
            } else {
                g = 0.0
            }
            if i.truncatingRemainder(dividingBy: 6) > 1 {
                b = (i.truncatingRemainder(dividingBy: 36) * 40.0 + 55.0) / 255.0
            } else {
                b = 0.0
            }
        } else if index >= 232, index < 256 {
            let i = CGFloat(index - 232)
            r = (i * 10 + 8) / 255.0
            g = (i * 10 + 8) / 255.0
            b = (i * 10 + 8) / 255.0
        } else {
            return nil
        }
        return NSColor(deviceRed: r, green: g, blue: b, alpha: 1.0).usingColorSpace(.sRGB)
    }
}
