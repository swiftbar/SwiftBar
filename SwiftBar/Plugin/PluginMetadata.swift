import Cocoa
import Foundation
import SwifCron

enum PluginMetadataType: String {
    case bitbar
    case xbar
    case swiftbar
}

enum PluginMetadataOption: String, CaseIterable {
    case title
    case version
    case author
    case github = "author.github"
    case desc
    case about
    case image
    case dependencies
    case droptypes
    case schedule
    case type
    case hideAbout
    case hideRunInTerminal
    case hideLastUpdated
    case hideDisablePlugin
    case hideSwiftBar
    case environment
    case runInBash
    case refreshOnOpen
    case useTrailingStreamSeparator

    var optionType: [PluginMetadataType] {
        switch self {
        case .title, .version, .author, .github, .desc, .about, .image, .dependencies:
            return [.bitbar, .xbar]
        case .runInBash, .environment, .droptypes, .schedule, .type, .hideAbout, .hideRunInTerminal, .hideLastUpdated, .hideDisablePlugin, .hideSwiftBar, .refreshOnOpen, .useTrailingStreamSeparator:
            return [.swiftbar]
        }
    }
}

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
    @Published var type: PluginType
    @Published var hideAbout: Bool
    @Published var hideRunInTerminal: Bool
    @Published var hideLastUpdated: Bool
    @Published var hideDisablePlugin: Bool
    @Published var hideSwiftBar: Bool
    @Published var environment: [String: String]
    @Published var runInBash: Bool
    @Published var refreshOnOpen: Bool
    @Published var useTrailingStreamSeparator: Bool

    var isEmpty: Bool {
        name.isEmpty
            && version.isEmpty
            && author.isEmpty
            && github.isEmpty
            && desc.isEmpty
            && previewImageURL != nil
            && dependencies.isEmpty
            && aboutURL != nil
    }

    var nextDate: Date? {
        // parse schedule string and return the minimum date
        let date = schedule.components(separatedBy: "|").compactMap { try? SwifCron($0).next() }.reduce(Date.distantFuture, min)
        return date == Date.distantFuture ? nil : date
    }

    init(name: String = "", version: String = "", author: String = "", github: String = "", desc: String = "", previewImageURL: URL? = nil, dependencies: [String] = [], aboutURL: URL? = nil, dropTypes: [String] = [], schedule: String = "", type: PluginType = .Executable, hideAbout: Bool = false, hideRunInTerminal: Bool = false, hideLastUpdated: Bool = false, hideDisablePlugin: Bool = false, hideSwiftBar: Bool = false, environment: [String: String] = [:], runInBash: Bool = true, refreshOnOpen: Bool = false, useTrailingStreamSeparator: Bool = false) {
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
        self.type = type
        self.hideAbout = hideAbout
        self.hideRunInTerminal = hideRunInTerminal
        self.hideLastUpdated = hideLastUpdated
        self.hideDisablePlugin = hideDisablePlugin
        self.hideSwiftBar = hideSwiftBar
        self.environment = environment
        self.runInBash = runInBash
        self.refreshOnOpen = refreshOnOpen
        self.useTrailingStreamSeparator = useTrailingStreamSeparator
    }

    var shouldRunInBash: Bool {
        if PreferencesStore.shared.disableBashWrapper {
            return false
        }
        return runInBash
    }

    static func parser(script: String) -> PluginMetadata {
        func getTagValue(tag: PluginMetadataOption) -> String {
            let values = tag.optionType.compactMap { prefix -> String? in
                let openTag = "<\(prefix).\(tag.rawValue)>"
                let closeTag = "</\(prefix).\(tag.rawValue)>"
                return script.slice(from: openTag, to: closeTag)
            }
            return values.last ?? ""
        }

        var imageURL: URL?
        if !getTagValue(tag: .image).isEmpty {
            imageURL = URL(string: getTagValue(tag: .image))
        }
        var aboutURL: URL?
        if !getTagValue(tag: .about).isEmpty {
            aboutURL = URL(string: getTagValue(tag: .about))
        }
        var environment: [String: String] = [:]
        if !getTagValue(tag: .environment).isEmpty {
            getTagValue(tag: .environment)
                .dropFirst()
                .dropLast()
                .split(separator: ",").forEach { str in
                    let pair = str.split(separator: "=").map { $0.trimmingCharacters(in: .whitespaces) }
                    guard pair.count == 2 else { return }
                    environment[pair[0]] = pair[1]
                }
        }

        return PluginMetadata(name: getTagValue(tag: .title),
                              version: getTagValue(tag: .version),
                              author: getTagValue(tag: .author),
                              github: getTagValue(tag: .github),
                              desc: getTagValue(tag: .desc),
                              previewImageURL: imageURL,
                              dependencies: getTagValue(tag: .dependencies).components(separatedBy: ","),
                              aboutURL: aboutURL,
                              dropTypes: getTagValue(tag: .droptypes).components(separatedBy: ","),
                              schedule: getTagValue(tag: .schedule),
                              type: PluginType(rawValue: getTagValue(tag: .type).capitalized) ?? .Executable,
                              hideAbout: getTagValue(tag: .hideAbout) == "true",
                              hideRunInTerminal: getTagValue(tag: .hideRunInTerminal) == "true",
                              hideLastUpdated: getTagValue(tag: .hideLastUpdated) == "true",
                              hideDisablePlugin: getTagValue(tag: .hideDisablePlugin) == "true",
                              hideSwiftBar: getTagValue(tag: .hideSwiftBar) == "true",
                              environment: environment,
                              runInBash: getTagValue(tag: .runInBash) == "false" ? false : true,
                              refreshOnOpen: getTagValue(tag: .refreshOnOpen) == "true" ? true : false,
                              useTrailingStreamSeparator: getTagValue(tag: .useTrailingStreamSeparator) == "true" ? true : false)
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

    static func writeMetadata(metadata: PluginMetadata, fileURL: URL) {
        let metadataString = metadata.genereteMetadataString()
        if let encodedString = metadataString.data(using: .utf8)?.base64EncodedData() {
            try? fileURL.setExtendedAttribute(data: encodedString, forName: "com.ameba.SwiftBar")
            return
        }
    }

    static func empty() -> PluginMetadata {
        PluginMetadata()
    }

    func genereteMetadataString() -> String {
        var result = ""
        PluginMetadataOption.allCases.forEach { option in
            var value = ""
            switch option {
            case .title:
                value = name
            case .version:
                value = version
            case .author:
                value = author
            case .github:
                value = github
            case .desc:
                value = desc
            case .about:
                value = aboutURL?.absoluteString ?? ""
            case .image:
                value = previewImageURL?.absoluteString ?? ""
            case .dependencies:
                value = dependencies.joined(separator: ",")
            case .droptypes:
                value = dropTypes.joined(separator: ",")
            case .schedule:
                value = schedule
            case .type:
                value = type == .Streamable ? type.rawValue : ""
            case .hideAbout:
                value = hideAbout ? "true" : ""
            case .hideRunInTerminal:
                value = hideRunInTerminal ? "true" : ""
            case .hideLastUpdated:
                value = hideLastUpdated ? "true" : ""
            case .hideDisablePlugin:
                value = hideDisablePlugin ? "true" : ""
            case .hideSwiftBar:
                value = hideSwiftBar ? "true" : ""
            case .environment:
                value = environment.map { "\($0.key):\($0.value)" }.joined(separator: ",")
            case .runInBash:
                value = runInBash ? "" : "false"
            case .refreshOnOpen:
                value = refreshOnOpen ? "true" : ""
            case .useTrailingStreamSeparator:
                value = useTrailingStreamSeparator ? "true" : ""
            }
            guard !value.isEmpty else { return }
            let tag = option
            let prefix = tag.optionType.last!.rawValue
            result.append("\n<\(prefix).\(tag)>\(value)</\(prefix).\(tag)>")
        }

        return result.trimmingCharacters(in: .whitespaces)
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
