import Cocoa

private var ANSIForeground: [Int: NSColor] = [
    // foreground
    39: .labelColor,
    30: .black,
    31: .systemRed,
    32: .systemGreen,
    33: .systemYellow,
    34: .systemBlue,
    35: .magenta,
    36: .cyan,
    37: .white,
    90: .darkGray,
    91: .red,
    92: .green,
    93: .yellow,
    94: .blue,
    95: .magenta,
    96: .cyan,
    97: .white,
]

private var ANSIBackground: [Int: NSColor] = [
    // background
    40: .black,
    41: .systemRed,
    42: .systemGreen,
    43: .systemYellow,
    44: .systemBlue,
    45: .magenta,
    46: .cyan,
    47: .systemGray,
    49: .textBackgroundColor,
    100: .darkGray,
    101: .red,
    102: .green,
    103: .yellow,
    104: .blue,
    105: .magenta,
    106: .cyan,
    107: .white,
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
        var foreground = false
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

            if code == 1 {
                self[.font] = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
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
