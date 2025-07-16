import Combine
import Foundation
import os

class PluginRepository: ObservableObject {
    static let shared = PluginRepository()
    let prefs = PreferencesStore.shared

    @Published var searchString: String = ""
    var cancellables: Set<AnyCancellable> = []

    @Published var categories: [String] = []
    @Published var plugins: [String: [RepositoryPlugin.Plugin]] = [:]

    init() {
        refreshRepositoryData()

        if #available(OSX 11.0, *) {
            NotificationCenter.default.publisher(for: .repositoirySearchUpdate)
                .compactMap { $0.userInfo?["query"] as? String }
                .map { $0 }
                .debounce(for: 0.2, scheduler: RunLoop.main)
                .assign(to: &$searchString)
        }
    }

    func getPlugins(for category: String) -> [RepositoryPlugin.Plugin] {
        plugins[category]?.sorted(by: { $0.title > $1.title }) ?? []
    }

    func searchPlugins(with searchString: String) -> [RepositoryPlugin.Plugin] {
        plugins.flatMap(\.value)
            .filter { $0.bagOfWords.contains(searchString.lowercased()) }
            .sorted(by: { $0.title > $1.title })
    }

    func refreshRepositoryData(ignoreCache: Bool = false) {
        PluginRepositoryAPI.categories(ignoreCache: ignoreCache)
            .map(\.categories)
            .sink(receiveCompletion: { _ in },
                  receiveValue: { [weak self] in
                      let cats = $0.map(\.text)
                      self?.categories = cats
                      cats.forEach { self?.getPlugins(category: $0, ignoreCache: ignoreCache) }
                  })
            .store(in: &cancellables)
    }

    func getPlugins(category: String, ignoreCache: Bool = false) {
        PluginRepositoryAPI.plugins(category: category, ignoreCache: ignoreCache)
            .map(\.plugins)
            .sink(receiveCompletion: { _ in },
                  receiveValue: { [weak self] in
                      self?.plugins[category] = $0
                  })
            .store(in: &cancellables)
    }

    static func categorySFImage(_ category: String) -> String {
        switch category.lowercased() {
        case "aws":
            "bolt"
        case "cryptocurrency":
            "bitcoinsign.circle"
        case "dev":
            "hammer"
        case "e-commerce":
            "bag.circle"
        case "email":
            "envelope"
        case "environment":
            "leaf"
        case "finance":
            "dollarsign.circle"
        case "games":
            "gamecontroller"
        case "lifestyle":
            "face.smiling"
        case "messenger":
            "message"
        case "music":
            "music.note"
        case "network":
            "network"
        case "politics":
            "person.2"
        case "science":
            "graduationcap"
        case "sports":
            "sportscourt"
        case "system":
            "gear"
        case "time":
            "clock"
        case "tools":
            "paintbrush"
        case "travel":
            "briefcase"
        case "tutorial":
            "bubble.left.and.bubble.right"
        case "weather":
            "cloud.sun"
        case "web":
            "globe"
        default:
            "questionmark.circle"
        }
    }
}

struct RepositoryCategory: Codable {
    struct Category: Codable {
        let path: String
        let text: String
        let lastUpdated: String
    }

    let version: String
    let lastUpdated: String
    let categories: [Category]
}

struct RepositoryPlugin: Codable {
    struct Plugin: Codable, Hashable {
        struct Author: Codable, Hashable {
            let name: String
            let githubUsername: String?
            let imageURL: String?
            let bio: String?
            let primary: Bool
        }

        let path: String
        let filename: String
        let dir: String
        let docsPlugin: String
        let docsCategory: String
        let title: String
        let version: String
        let desc: String
        let imageURL: String
        let dependencies: [String]?
        var authors: [Author]
        let aboutURL: String

        var image: URL? {
            URL(string: imageURL)
        }

        var gitHubURL: URL? {
            let url = PreferencesStore.shared.pluginSourceCodeURL
            return url.appendingPathComponent(path)
        }

        var sourceFileURL: URL? {
            let url = PreferencesStore.shared.pluginRepositoryURL
            if url.absoluteString.hasPrefix("https://xbarapp.com/") {
                return URL(string: "https://raw.githubusercontent.com/matryer/xbar-plugins/master/\(path)")
            }

            return url.appendingPathComponent(path)
        }

        var mainAuthor: Author? {
            authors.first { $0.primary }
        }

        var author: String {
            mainAuthor?.name ?? ""
        }

        var github: String? {
            mainAuthor?.githubUsername
        }

        var bagOfWords: [String] {
            var out: [String] = []
            [title, author, desc].compactMap { $0 }.forEach { str in
                out.append(contentsOf: str.lowercased().components(separatedBy: .whitespaces))
            }
            return out
        }
    }

    let version: String
    let lastUpdated: String
    let plugins: [Plugin]
}
