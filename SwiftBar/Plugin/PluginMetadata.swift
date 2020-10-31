import Foundation

struct PluginMetadata {
    let name: String?
    let version: String?
    let author: String?
    let github: String?
    let desc: String?
    let previewImageURL: URL?
    let dependencies: [String]?
    let aboutURL: URL?

    var isEmpty: Bool {
        return name == nil
        && version == nil
        && author == nil
        && github == nil
        && desc == nil
        && previewImageURL == nil
        && dependencies == nil
        && aboutURL == nil
    }

    init(name: String? = nil, version: String? = nil, author: String? = nil, github: String? = nil, desc: String? = nil, previewImageURL: URL? = nil, dependencies: [String]? = nil, aboutURL: URL? = nil) {
        self.name = name
        self.version = version
        self.author = author
        self.github = github
        self.desc = desc
        self.previewImageURL = previewImageURL
        self.dependencies = dependencies
        self.aboutURL = aboutURL
    }

    static func bitbarParser(script: String) -> Self {
        func getTagValue(tag: String) -> String? {
            let openTag = "<bitbar.\(tag)>"
            let closeTag = "</bitbar.\(tag)>"
            return script.slice(from: openTag, to: closeTag)
        }
        var imageURL: URL? = nil
        if let imageStr = getTagValue(tag: "image") {
            imageURL = URL(string: imageStr)
        }
        var aboutURL: URL? = nil
        if let imageStr = getTagValue(tag: "about") {
            aboutURL = URL(string: imageStr)
        }
        return PluginMetadata(name: getTagValue(tag: "title"),
                              version: getTagValue(tag: "version"),
                              author: getTagValue(tag: "author"),
                              github: getTagValue(tag: "github"),
                              desc: getTagValue(tag: "desc"),
                              previewImageURL: imageURL,
                              dependencies: getTagValue(tag: "dependencies")?.components(separatedBy: ","),
                              aboutURL: aboutURL)
    }
}

extension String {
    func slice(from: String, to: String) -> String? {
        return (range(of: from)?.upperBound).flatMap { substringFrom in
            (range(of: to, range: substringFrom..<endIndex)?.lowerBound).map { substringTo in
                String(self[substringFrom..<substringTo])
            }
        }
    }
}
