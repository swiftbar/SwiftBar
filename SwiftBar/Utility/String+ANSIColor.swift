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

extension [NSAttributedString.Key: Any] {
    mutating func attributesForANSICodes(codes: String) {
        var color256 = false
        var foreground = false
        // After 38 or 48 the next code selects the color format; 2 starts an `r;g;b` triplet.
        var expectsColorFormat = false
        var rgb: [Int]?
        let font = self[.font]

        for codeString in codes.components(separatedBy: ";") {
            guard var code = Int(codeString) else { continue }
            if var components = rgb {
                components.append(code)
                if components.count < 3 {
                    rgb = components
                    continue
                }
                rgb = nil
                self[foreground ? .foregroundColor : .backgroundColor] = NSColor(
                    srgbRed: CGFloat(components[0]) / 255, green: CGFloat(components[1]) / 255, blue: CGFloat(components[2]) / 255, alpha: 1
                )
                foreground = false
                continue
            }
            if expectsColorFormat {
                expectsColorFormat = false
                if code == 2 {
                    rgb = []
                    continue
                }
            }
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
                expectsColorFormat = true
                continue
            }
            if code == 39 {
                removeValue(forKey: .foregroundColor)
                continue
            }
            if code == 48 {
                foreground = false
                expectsColorFormat = true
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
