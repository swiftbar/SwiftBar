import Cocoa
import HotKey

struct MenuLineParameters {
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
            .sorted { (s1, s2) -> Bool in s1.localizedStandardCompare(s2) == .orderedAscending }
        for key in sortedParams {
            guard let param = params[key] else { continue }
            out.append(param.escaped())
        }
        return out
    }

    var terminal: Bool {
        params["terminal"] != "false"
    }

    var refresh: Bool {
        params["refresh"] == "true"
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

    var size: CGFloat? {
        guard let sizeStr = params["size"], let pSize = Int(sizeStr) else { return nil }
        return CGFloat(pSize)
    }
    
    var sfsize: CGFloat? {
        guard let sizeStr = params["sfsize"], let pSize = Int(sizeStr) else { return nil }
        return CGFloat(pSize)
    }

    var dropdown: Bool {
        params["dropdown"] != "false"
    }

    var trim: Bool {
        params["trim"] != "false"
    }

    var checked: Bool {
        params["checked"] == "true"
    }

    var length: Int? {
        guard let lengthStr = params["length"], let pLength = Int(lengthStr) else { return nil }
        return pLength
    }

    var alternate: Bool {
        params["alternate"] == "true"
    }

    var image: NSImage? {
        if #available(OSX 11.0, *) {
            if let sfString = params["sfimage"] {
                let config = NSImage.SymbolConfiguration(scale: .large)
                return NSImage(systemSymbolName: sfString, accessibilityDescription: nil)?.withSymbolConfiguration(config)
            }
        }

        let image = NSImage.createImage(from: params["image"] ?? params["templateimage"], isTemplate: params["templateimage"] != nil)
        if let widthStr = params["width"], let width = Float(widthStr),
           let heightStr = params["height"], let height = Float(heightStr)
        {
            return image?.resizedCopy(w: CGFloat(width), h: CGFloat(height))
        }

        return image
    }

    var emojize: Bool {
        params["emojize"] != "false"
    }

    var symbolize: Bool {
        if #available(OSX 11.0, *) {
            return params["symbolize"] != "false"
        }
        return false
    }

    var ansi: Bool {
        params["ansi"] == "true"
    }

    var tooltip: String? {
        params["tooltip"]
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
