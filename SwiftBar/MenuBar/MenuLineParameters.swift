import Cocoa
import HotKey
import SwiftUI

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
        let scanner = Scanner(string: line)
        let keyValueSeparator = CharacterSet(charactersIn: "=")
        let quoteSeparator = CharacterSet(charactersIn: "\"'")

        var params: [String: String] = [:]

        while !scanner.isAtEnd {
            var key: String? = ""
            var value: String? = ""
            key = scanner.scanUpToCharacters(from: keyValueSeparator)
            _ = scanner.scanCharacters(from: keyValueSeparator)
            if scanner.scanCharacters(from: quoteSeparator) != nil {
                value = scanner.scanUpToCharacters(from: quoteSeparator)
                _ = scanner.scanCharacters(from: quoteSeparator)
            } else {
                value = scanner.scanUpToString(" ")
            }

            if let key = key?.trimmingCharacters(in: .whitespaces).lowercased(),
               let value = value?.trimmingCharacters(in: .whitespaces)
            {
                params[key] = value
            }
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
            out.append(param.escaped())
        }
        return out.map { "'\($0)'" }
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
                if #available(OSX 12.0, *), let sfmc = sfmc {
                    switch sfmc.renderingMode {
                    case .Hierarchical:
                        config = config.applying(NSImage.SymbolConfiguration(hierarchicalColor: sfmc.getColors().first ?? NSColor(Color.primary)))
                    case .Palette:
                        config = config.applying(NSImage.SymbolConfiguration(paletteColors: sfmc.getColors()))
                    }
                    config = config.applying(NSImage.SymbolConfiguration(pointSize: 0, weight: sfmc.getWeight(), scale: sfmc.getScale()))
                }

                let image = NSImage(systemSymbolName: sfString, accessibilityDescription: nil)?.withSymbolConfiguration(config)
                image?.isTemplate = true
                return resizedImageIfRequested(image)
            }
        }

        if (params["image"] != nil) {
            let images = params["image"]?.components(separatedBy: ",")
            let lightImage = images?.first
            let darkImage = images?.last

            return resizedImageIfRequested(NSImage.createImage(from: AppShared.isDarkStatusBar || darkImage == nil ? lightImage : darkImage, isTemplate: false))
        }

        if (params["templateimage"] != nil) {
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
}
