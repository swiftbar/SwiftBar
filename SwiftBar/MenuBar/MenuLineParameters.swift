import Cocoa
import HotKey
import SwiftUI

extension Scanner {
    func peekChar() -> Character? {
        guard !isAtEnd else { return nil }

        let currentIndex = currentIndex
        guard let char = scanCharacter() else { return nil }

        self.currentIndex = currentIndex

        return char
    }
}

struct MenuLineParameters: Codable {
    let title: String
    var params: [String: String]

    init(line: String) {
        guard let index = line.range(of: "|") else {
            title = line
            params = [:]
            return
        }
        title = String(line[...index.lowerBound].dropLast())
        params = MenuLineParameters.getParams(from: String(line[index.upperBound...]).trimmingCharacters(in: .whitespaces))
    }

    var json: String? {
        guard let jsonData = try? JSONEncoder().encode(self),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else { return nil }
        return jsonString
    }

    init?(json: Data) {
        guard let item = try? JSONDecoder().decode(MenuLineParameters.self, from: json) else { return nil }
        title = item.title
        params = item.params
    }

    static func getParams(from line: String) -> [String: String] {
        // Manual parameter parser that properly handles quoted values with spaces
        var params: [String: String] = [:]
        let chars = Array(line)
        var currentPos = 0

        while currentPos < chars.count {
            // Skip whitespace
            while currentPos < chars.count && (chars[currentPos] == " " || chars[currentPos] == "\t") {
                currentPos += 1
            }

            // End of string?
            if currentPos >= chars.count {
                break
            }

            // Extract key
            let keyStart = currentPos
            while currentPos < chars.count && chars[currentPos] != "=" {
                currentPos += 1
            }

            // If we didn't find an equals sign, this isn't a valid parameter
            if currentPos >= chars.count || chars[currentPos] != "=" {
                break
            }

            let keyString = String(chars[keyStart ..< currentPos]).trimmingCharacters(in: .whitespaces).lowercased()
            currentPos += 1 // Skip the equals sign

            // Skip whitespace after equals sign
            while currentPos < chars.count, chars[currentPos] == " " || chars[currentPos] == "\t" {
                currentPos += 1
            }

            // Extract value
            var value = ""

            // Check if value is quoted
            if currentPos < chars.count, chars[currentPos] == "\"" || chars[currentPos] == "'" {
                let quoteChar = chars[currentPos]
                currentPos += 1 // Skip opening quote

                // Parse until closing quote
                var escaped = false
                while currentPos < chars.count {
                    let c = chars[currentPos]

                    if escaped {
                        // For escaped characters, we need to preserve both the backslash
                        // and the character exactly as provided in the parameter
                        value.append("\\")
                        value.append(c)
                        escaped = false
                    } else if c == "\\" {
                        // Start of an escape sequence
                        escaped = true
                    } else if c == quoteChar {
                        // End of quoted section
                        currentPos += 1
                        break
                    } else {
                        // Regular character
                        value.append(c)
                    }

                    currentPos += 1
                }
            } else {
                // Unquoted value - read until next whitespace
                let valueStart = currentPos
                while currentPos < chars.count, chars[currentPos] != " ", chars[currentPos] != "\t" {
                    currentPos += 1
                }

                value = String(chars[valueStart ..< currentPos])
            }

            // Add the parameter to our dictionary
            params[keyString] = value
        }

        return params
    }

    struct SFConfig: Codable {
        enum RenderingMode: String, Codable {
            case Hierarchical
            case Palette
        }

        enum Scale: String, Codable {
            case small
            case medium
            case large
        }

        enum Weight: String, Codable {
            case ultralight
            case thin
            case light
            case regular
            case medium
            case semibold
            case bold
            case heavy
            case black
        }

        var renderingMode: RenderingMode
        var colors: [String]
        var scale: Scale?
        var weight: Weight?
        var variableValue: Double?

        func getColors() -> [NSColor] {
            colors.compactMap { NSColor.webColor(from: $0) }
        }

        @available(macOS 11.0, *)
        func getScale() -> NSImage.SymbolScale {
            switch scale {
            case .small:
                .small
            case .medium:
                .medium
            case .large:
                .large
            case .none:
                .large
            }
        }

        @available(macOS 11.0, *)
        func getWeight() -> NSFont.Weight {
            switch weight {
            case .ultralight:
                .ultraLight
            case .thin:
                .thin
            case .light:
                .light
            case .regular:
                .regular
            case .medium:
                .medium
            case .semibold:
                .semibold
            case .bold:
                .bold
            case .heavy:
                .heavy
            case .black:
                .black
            case .none:
                .regular
            }
        }
    }

    var href: String? {
        params["href"]
    }

    var bash: String? {
        params["bash"] ?? params["shell"]
    }

    var bashParams: [String] {
        var out: [String] = []

        let sortedParams = params.keys
            .filter { $0.hasPrefix("param") }
            .sorted { s1, s2 -> Bool in s1.localizedStandardCompare(s2) == .orderedAscending }
        for key in sortedParams {
            guard let param = params[key] else { continue }
            out.append(param)
        }
        return out
    }

    var terminal: Bool {
        params["terminal"]?.lowercased() != "false"
    }

    var refresh: Bool {
        params["refresh"]?.lowercased() == "true"
    }

    var color: NSColor? {
        let colors = params["color"]?.components(separatedBy: ",")
        let lightColor = colors?.first?.lowercased()
        let darkColor = colors?.last?.lowercased()
        return NSColor.webColor(from: AppShared.isDarkTheme ? darkColor : lightColor)
    }

    var sfcolor: NSColor? {
        let colors = params["sfcolor"]?.components(separatedBy: ",")
        let lightColor = colors?.first
        let darkColor = colors?.last
        return NSColor.webColor(from: AppShared.isDarkTheme ? darkColor : lightColor)
    }

    var sfcolors: [NSColor] {
        var out: [NSColor?] = []
        out.append(sfcolor)
        for i in 1 ... 10 {
            guard let colors = params["sfcolor\(i)"]?.components(separatedBy: ",") else { continue }
            let lightColor = colors.first
            let darkColor = colors.last
            out.append(NSColor.webColor(from: AppShared.isDarkTheme ? darkColor : lightColor))
        }
        return out.compactMap { $0 }
    }

    var font: String? {
        params["font"]
    }

    var md: Bool {
        params["md"]?.lowercased() == "true"
    }

    var size: CGFloat? {
        guard let sizeStr = params["size"], let pSize = Int(sizeStr) else { return nil }
        return CGFloat(pSize)
    }

    var sfsize: CGFloat? {
        guard let sizeStr = params["sfsize"], let pSize = Int(sizeStr) else { return nil }
        return CGFloat(pSize)
    }

    var dropdown: Bool {
        params["dropdown"]?.lowercased() != "false"
    }

    var trim: Bool {
        params["trim"]?.lowercased() != "false"
    }

    var checked: Bool {
        params["checked"]?.lowercased() == "true"
    }

    var length: Int? {
        guard let lengthStr = params["length"], let pLength = Int(lengthStr) else { return nil }
        return pLength
    }

    var alternate: Bool {
        params["alternate"]?.lowercased() == "true"
    }

    func getSFConfig() -> SFConfig? {
        guard let base64 = params["sfconfig"]?.data(using: .utf8),
              let decodedData = Data(base64Encoded: base64),
              case let sfmc = try? JSONDecoder().decode(SFConfig.self, from: decodedData)
        else { return nil }
        return sfmc
    }

    var image: NSImage? {
        if #available(OSX 11.0, *) {
            if let sfString = params["sfimage"] {
                let sfmc = getSFConfig()
                var config = NSImage.SymbolConfiguration(scale: .large)
                if #available(OSX 12.0, *), let sfmc {
                    switch sfmc.renderingMode {
                    case .Hierarchical:
                        config = config.applying(NSImage.SymbolConfiguration(hierarchicalColor: sfmc.getColors().first ?? NSColor(Color.primary)))
                    case .Palette:
                        config = config.applying(NSImage.SymbolConfiguration(paletteColors: sfmc.getColors()))
                    }
                    config = config.applying(NSImage.SymbolConfiguration(pointSize: 0, weight: sfmc.getWeight(), scale: sfmc.getScale()))
                }

                // Check for variable value from either sfconfig or sfvalue parameter
                let variableValue = sfmc?.variableValue ?? sfvalue
                
                let image: NSImage?
                if #available(macOS 13.0, *), let variableValue = variableValue {
                    // Create image with variable value for symbols that support it
                    image = NSImage(systemSymbolName: sfString, variableValue: variableValue, accessibilityDescription: nil)?.withSymbolConfiguration(config)
                } else {
                    // Fallback to regular symbol creation
                    image = NSImage(systemSymbolName: sfString, accessibilityDescription: nil)?.withSymbolConfiguration(config)
                }
                
                image?.isTemplate = true
                return resizedImageIfRequested(image)
            }
        }

        if params["image"] != nil {
            let images = params["image"]?.components(separatedBy: ",")
            let lightImage = images?.first
            let darkImage = images?.last

            return resizedImageIfRequested(NSImage.createImage(from: AppShared.isDarkStatusBar || darkImage == nil ? lightImage : darkImage, isTemplate: false))
        }

        if params["templateimage"] != nil {
            return resizedImageIfRequested(NSImage.createImage(from: params["templateimage"], isTemplate: true))
        }

        return nil
    }

    private func resizedImageIfRequested(_ image: NSImage?) -> NSImage? {
        guard let widthStr = params["width"], let width = Float(widthStr),
              let heightStr = params["height"], let height = Float(heightStr)
        else {
            return image
        }
        return image?.resizedCopy(w: CGFloat(width), h: CGFloat(height))
    }

    var emojize: Bool {
        params["emojize"]?.lowercased() != "false"
    }

    var symbolize: Bool {
        if #available(OSX 11.0, *) {
            return params["symbolize"]?.lowercased() != "false"
        }
        return false
    }

    var ansi: Bool {
        params["ansi"]?.lowercased() == "true"
    }

    var tooltip: String? {
        params["tooltip"]
    }

    var webView: Bool {
        params["webview"]?.lowercased() == "true"
    }

    var webViewHeight: CGFloat {
        guard let sizeStr = params["webviewh"], let pSize = Int(sizeStr) else { return 400 }
        return CGFloat(pSize)
    }

    var webViewWidth: CGFloat {
        guard let sizeStr = params["webvieww"], let pSize = Int(sizeStr) else { return 500 }
        return CGFloat(pSize)
    }

    var webViewZoom: CGFloat {
        guard let zoomStr = params["zoom"] else { return 1.0 }
        if zoomStr.hasSuffix("%") {
            if let percentValue = Float(zoomStr.dropLast(1)) {
                return CGFloat(percentValue / 100.0)
            }
        } else if let directValue = Float(zoomStr) {
            return CGFloat(directValue)
        }
        return 1.0
    }

    var shortcut: KeyCombo? {
        guard let shortcut = params["shortcut"] else { return nil }
        var modifiers: NSEvent.ModifierFlags = []
        var maybeKeyStr: String?
        shortcut.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.forEach { modifier in
            switch modifier {
            case "shift":
                modifiers.insert(.shift)
            case "command", "cmd":
                modifiers.insert(.command)
            case "control", "ctrl":
                modifiers.insert(.control)
            case "option", "opt":
                modifiers.insert(.option)
            case "capslock":
                modifiers.insert(.capsLock)
            case "function", "fn":
                modifiers.insert(.function)
            default:
                maybeKeyStr = modifier
            }
        }
        guard let keyStr = maybeKeyStr,
              let key = Key(string: keyStr) else { return nil }

        return KeyCombo(key: key, modifiers: modifiers)
    }

    var hasAction: Bool {
        href != nil || bash != nil || refresh
    }

    var valign: CGFloat? {
        // Parse vertical alignment offset parameter
        // Positive values move text down, negative values move text up
        guard let valignStr = params["valign"], let offset = Float(valignStr) else { return nil }
        return CGFloat(offset)
    }
    
    var sfvalue: Double? {
        // Parse SF Symbol variable value parameter (0.0 to 1.0)
        guard let sfvalueStr = params["sfvalue"], let value = Double(sfvalueStr) else { return nil }
        return max(0.0, min(1.0, value)) // Clamp to 0.0-1.0 range
    }
}
