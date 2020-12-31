import Cocoa
import Foundation
import SwifCron

class PluginMetadata: ObservableObject {
    @Published var name: String
    @Published var version: String
    @Published var author: String
    @Published var github: String
    @Published var desc: String
    @Published var previewImageURL: URL?
    @Published var dependencies: [String]
    @Published var aboutURL: URL?
    @Published var dropTypes: [String]
    @Published var schedule: String
    @Published var hideAbout: Bool
    @Published var hideRunInTerminal: Bool
    @Published var hideLastUpdated: Bool
    @Published var hideDisablePlugin: Bool
    @Published var hideSwiftBar: Bool

    var isEmpty: Bool {
        name.isEmpty
            && version.isEmpty
            && author.isEmpty
            && github.isEmpty
            && desc.isEmpty
            && previewImageURL != nil
            && dependencies.isEmpty
            && aboutURL != nil
            && dropTypes.isEmpty
    }

    var nextDate: Date? {
        guard let cron = try? SwifCron(schedule)
        else { return nil }
        return try? cron.next()
    }

    init(name: String = "", version: String = "", author: String = "", github: String = "", desc: String = "", previewImageURL: URL? = nil, dependencies: [String] = [], aboutURL: URL? = nil, dropTypes: [String] = [], schedule: String = "", hideAbout: Bool = false, hideRunInTerminal: Bool = false, hideLastUpdated: Bool = false, hideDisablePlugin: Bool = false, hideSwiftBar: Bool = false) {
        self.name = name
        self.version = version
        self.author = author
        self.github = github
        self.desc = desc
        self.previewImageURL = previewImageURL
        self.dependencies = dependencies
        self.dropTypes = dropTypes
        self.schedule = schedule
        self.aboutURL = aboutURL
        self.hideAbout = hideAbout
        self.hideRunInTerminal = hideRunInTerminal
        self.hideLastUpdated = hideLastUpdated
        self.hideDisablePlugin = hideDisablePlugin
        self.hideSwiftBar = hideSwiftBar
    }

    static func parser(script: String) -> PluginMetadata {
        func getTagValue(tag: String, prefix: String) -> String {
            let openTag = "<\(prefix).\(tag)>"
            let closeTag = "</\(prefix).\(tag)>"
            return script.slice(from: openTag, to: closeTag) ?? ""
        }
        func getBitBarTagValue(tag: String) -> String {
            getTagValue(tag: tag, prefix: "bitbar")
        }
        func getSwiftBarTagValue(tag: String) -> String {
            getTagValue(tag: tag, prefix: "swiftbar")
        }
        var imageURL: URL?
        if !getBitBarTagValue(tag: "image").isEmpty {
            imageURL = URL(string: getBitBarTagValue(tag: "image"))
        }
        var aboutURL: URL?
        if !getBitBarTagValue(tag: "about").isEmpty {
            aboutURL = URL(string: getBitBarTagValue(tag: "about"))
        }

        return PluginMetadata(name: getBitBarTagValue(tag: "title"),
                              version: getBitBarTagValue(tag: "version"),
                              author: getBitBarTagValue(tag: "author"),
                              github: getBitBarTagValue(tag: "github"),
                              desc: getBitBarTagValue(tag: "desc"),
                              previewImageURL: imageURL,
                              dependencies: getBitBarTagValue(tag: "dependencies").components(separatedBy: ","),
                              aboutURL: aboutURL,
                              dropTypes: getBitBarTagValue(tag: "droptypes").components(separatedBy: ","),
                              schedule: getSwiftBarTagValue(tag: "schedule"),
                              hideAbout: getSwiftBarTagValue(tag: "hideAbout") == "true",
                              hideRunInTerminal: getSwiftBarTagValue(tag: "hideRunInTerminal") == "true",
                              hideLastUpdated: getSwiftBarTagValue(tag: "hideLastUpdated") == "true",
                              hideDisablePlugin: getSwiftBarTagValue(tag: "hideDisablePlugin") == "true",
                              hideSwiftBar: getSwiftBarTagValue(tag: "hideSwiftBar") == "true")
    }

    static func parser(fileURL: URL) -> PluginMetadata? {
        guard let base64 = try? fileURL.extendedAttribute(forName: "com.ameba.SwiftBar"),
              let decodedData = Data(base64Encoded: base64),
              let decodedString = String(data: decodedData, encoding: .utf8)
        else {
            return nil
        }
        return parser(script: decodedString)
    }

    static func empty() -> PluginMetadata {
        PluginMetadata()
    }
}

extension String {
    func slice(from: String, to: String) -> String? {
        (range(of: from)?.upperBound).flatMap { substringFrom in
            (range(of: to, range: substringFrom ..< endIndex)?.lowerBound).map { substringTo in
                String(self[substringFrom ..< substringTo])
            }
        }
    }
}
