import Cocoa

struct MenuLineParameters {
    let title: String
    let href: String?
    let bash: String?
    let refresh: Bool
    let color: NSColor?
    let font: String?
    let size: CGFloat?
    let dropdown: Bool
    let trim: Bool
    let length: Int?
    let alternate: Bool
    let image: NSImage?
    let emojize: Bool

    init(line: String) {
        guard let index = line.range(of: "|") else {
            title = line
            href = nil
            bash = nil
            refresh = false
            color = nil
            font = nil
            size = nil
            dropdown = true
            trim = true
            length = nil
            alternate = false
            image = nil
            emojize = true
            return
        }
        title = String(line[...index.lowerBound].dropLast())
        let pairs = String(line[index.upperBound...]).trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
        var params: [String:String] = [:]
        pairs.forEach{ pair in
            guard let index = pair.firstIndex(of: "=") else {return}
            let key = pair[...pair.index(index, offsetBy: -1)].trimmingCharacters(in: .whitespaces)
            let value = pair[pair.index(index, offsetBy: 1)...].trimmingCharacters(in: .whitespaces)
            params[key] = value
        }

        href = params["href"]
        bash = params["bash"]
        refresh = (params["refresh"] == "true")
        color = NSColor.webColor(from: params["color"])
        font = params["font"]
        if let sizeStr = params["size"], let pSize = Int(sizeStr) {
            size = CGFloat(pSize)
        } else {
            size = nil
        }
        dropdown = (params["dropdown"] != "false")
        trim = (params["trim"] != "false")
        if let lengthStr = params["length"], let pLength = Int(lengthStr) {
            length = pLength
        } else {
            length = nil
        }
        alternate = (params["alternate"] == "true")
        image = NSImage.createImage(from: params["image"] ?? params["templateImage"], isTemplate: params["templateImage"] != nil)
        emojize = (params["emojize"] != "false")
    }
}
