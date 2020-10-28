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
        title = String(line[...index.lowerBound])
        let pairs = String(line[index.upperBound...]).components(separatedBy: .whitespaces)
        var params: [String:String] = [:]
        pairs.map{$0.components(separatedBy: "=")}.forEach { pair in
            guard params.count == 2 else {return}
            params[pair[0].trimmingCharacters(in: .whitespaces)] = pair[1].trimmingCharacters(in: .whitespaces)
        }

        href = params["href"]
        bash = params["bash"]
        refresh = (params["refresh"] == "true")
        color = params["href"]
        font = params["href"]
        size = nil
        dropdown = (params["refresh"] == "true")
        trim = (params["refresh"] == "true")
        length = nil
    }
}

