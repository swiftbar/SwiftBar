import Foundation

struct MenuLineParameters {
    let title: String
    let href: String?
    let bash: String?
    let refresh: Bool
    let color: String?
    let font: String?
    let size: Int?
    let dropdown: Bool
    let trim: Bool
    let length: Int?

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
            trim = false
            length = nil
            return
        }
        title = String(line[...index.lowerBound].dropLast())
        let pairs = String(line[index.upperBound...]).trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
        var params: [String:String] = [:]
        pairs.forEach{ pair in
            let set = pair.components(separatedBy: "=")
            guard set.count == 2 else {return}
            params[set[0].trimmingCharacters(in: .whitespaces)] = set[1].trimmingCharacters(in: .whitespaces)
        }

        href = params["href"]
        bash = params["bash"]
        refresh = (params["refresh"] == "true")
        color = params["href"]
        font = params["href"]
        size = nil
        dropdown = (params["trim"] != "false")
        trim = (params["trim"] == "true")
        length = nil
    }
}

