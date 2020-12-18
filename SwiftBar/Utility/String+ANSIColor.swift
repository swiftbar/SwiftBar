import Cocoa

private var ANSIForeground: [Int: NSColor] = [
    // foreground
    39: NSColor.labelColor,
    30: NSColor.black,
    31: NSColor.red,
    32: NSColor.green,
    33: NSColor.yellow,
    34: NSColor.blue,
    35: NSColor.magenta,
    36: NSColor.cyan,
    37: NSColor.lightGray,
    90: NSColor.darkGray,
    91: NSColor.red,
    92: NSColor.green,
    93: NSColor.yellow,
    94: NSColor.blue,
    95: NSColor.magenta,
    96: NSColor.cyan,
    97: NSColor.white,
]

private var ANSIBackground: [Int: NSColor] = [
    // background
    40: NSColor.black,
    41: NSColor.red,
    42: NSColor.green,
    43: NSColor.yellow,
    44: NSColor.blue,
    45: NSColor.magenta,
    46: NSColor.cyan,
    47: NSColor.lightGray,
    49: NSColor.textBackgroundColor,
    100: NSColor.darkGray,
    101: NSColor.red,
    102: NSColor.green,
    103: NSColor.yellow,
    104: NSColor.blue,
    105: NSColor.magenta,
    106: NSColor.cyan,
    107: NSColor.white,
]

extension String {
    func colorizedWithANSIColor() -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        var attributes: [NSAttributedString.Key: Any] = [:]
        let parts = replacingOccurrences(of: "\\e", with: "\u{1B}")
            .components(separatedBy: "\u{1B}[")
        out.append(NSAttributedString(string: parts.first ?? ""))

        for part in parts[1...] {
            guard part.count > 0 else { continue }

            let sequence = part.components(separatedBy: "m")
            var text = sequence.last ?? ""

            guard sequence.count >= 2 else {
                out.append(NSAttributedString(string: text, attributes: attributes))
                continue
            }

            text = sequence[1...].joined(separator: "m")
            attributes.attributesForANSICodes(codes: sequence[0])

            out.append(NSAttributedString(string: text, attributes: attributes))
        }

        return out
    }
}

extension Dictionary where Key == NSAttributedString.Key, Value == Any {
    mutating func attributesForANSICodes(codes: String) {
        var color256 = false
        var foreground: Bool = false
        let font = self[.font]

        for codeString in codes.components(separatedBy: ";") {
            guard var code = Int(codeString) else { continue }
            if color256 {
                color256 = false
                if let color = NSColor.colorForAnsi256ColorIndex(index: code) {
                    self[foreground ? .foregroundColor : .backgroundColor] = color
                    foreground = false
                    continue
                }

                if code >= 8, code < 16 {
                    code -= 8
                }
                code += foreground ? 30 : 40
            } else if code == 5 {
                color256 = true
                continue
            }

            if code == 0 {
                removeAll()
                self[.font] = font
                continue
            }
            if code == 38 {
                foreground = true
                continue
            }
            if code == 39 {
                removeValue(forKey: .foregroundColor)
                continue
            }
            if code == 48 {
                foreground = false
                continue
            }
            if code == 49 {
                removeValue(forKey: .backgroundColor)
                continue
            }
            if let color = ANSIForeground[code] {
                self[.foregroundColor] = color
                continue
            }
            if let color = ANSIBackground[code] {
                self[.backgroundColor] = color
                continue
            }
        }
    }
}
