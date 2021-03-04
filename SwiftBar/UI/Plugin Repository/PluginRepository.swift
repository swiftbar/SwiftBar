import Foundation
import os

class PluginRepository: ObservableObject {
    static let shared = PluginRepository()
    let prefs = Preferences.shared

    @Published var repository: [RepositoryEntry] {
        didSet {
            categories = Array(Set(repository.map(\.category))).sorted()
        }
    }

    var categories: [String]

    init() {
        guard let repository = PluginRepository.parseRepositoryFile()
        else {
            self.repository = []
            categories = []
            refreshRepository()
            return
        }

        self.repository = repository
        categories = Array(Set(repository.map(\.category))).sorted()
    }

    func getPlugins(for category: String) -> [RepositoryEntry.PluginEntry] {
        repository.filter { $0.category == category }.flatMap(\.plugins)
    }

    func refreshRepository() {
        guard let pluginDirectoryURL = prefs.pluginDirectoryResolvedURL else { return }

        os_log("Refreshing plugin repository...", log: Log.repository)
        let url = URL(string: "https://raw.githubusercontent.com/swiftbar/swiftbar-plugins/main/repository.json")!

        let downloadTask = URLSession.shared.downloadTask(with: url) { [weak self] fileURL, _, _ in
            guard let fileURL = fileURL else {
                os_log("Failed to download plugin repository manifest.", log: Log.repository)
                return
            }
            os_log("Plugin repository manifest downloaded!", log: Log.repository)
            do {
                let targetURL = pluginDirectoryURL.appendingPathComponent(".repository.json")
                try FileManager.default.moveItem(atPath: fileURL.path, toPath: targetURL.path)
                guard let rep = PluginRepository.parseRepositoryFile() else { return }
                self?.categories = Array(Set(rep.map(\.category))).sorted()
                DispatchQueue.main.async {
                    self?.repository = rep
                }
            } catch {
                os_log("Failed to refresh plugin repository \n%{public}@", log: Log.repository, type: .error, error.localizedDescription)
            }
        }
        downloadTask.resume()
    }

    static func parseRepositoryFile() -> [RepositoryEntry]? {
        guard let pluginDirectoryPath = Preferences.shared.pluginDirectoryResolvedPath else { return nil }
        let url = URL(fileURLWithPath: pluginDirectoryPath).appendingPathComponent(".repository.json")

        guard let jsonStr = try? String(contentsOfFile: url.path),
              let data = jsonStr.data(using: .utf8),
              let repository = try? JSONDecoder().decode([RepositoryEntry].self, from: data)
        else { return nil }
        return repository
    }

    static func categorySFImage(_ category: String) -> String {
        switch category.lowercased() {
        case "aws":
            return "bolt"
        case "cryptocurrency":
            return "bitcoinsign.circle"
        case "dev":
            return "hammer"
        case "e-commerce":
            return "bag.circle"
        case "email":
            return "envelope"
        case "environment":
            return "leaf"
        case "finance":
            return "dollarsign.circle"
        case "games":
            return "gamecontroller"
        case "lifestyle":
            return "face.smiling.fill"
        case "messenger":
            return "message"
        case "music":
            return "music.note"
        case "network":
            return "network"
        case "politics":
            return "person.2"
        case "science":
            return "graduationcap"
        case "sports":
            return "sportscourt"
        case "system":
            return "gear"
        case "time":
            return "clock"
        case "tools":
            return "paintbrush"
        case "travel":
            return "briefcase"
        case "tutorial":
            return "bubble.left.and.bubble.right"
        case "weather":
            return "cloud.sun"
        case "web":
            return "globe"
        default:
            return "questionmark.circle"
        }
    }
}

struct RepositoryEntry: Codable {
    enum Category: String, Codable {
        case Music
    }

    struct PluginEntry: Codable, Hashable {
        let title: String
        let author: String
        let github: String?
        let desc: String?
        let image: URL?
        let dependencies: String?
        let aboutURL: URL?
        let source: String
        let version: String?

        enum CodingKeys: String, CodingKey {
            case title
            case author
            case github = "author.github"
            case desc
            case image
            case dependencies
            case aboutURL
            case source
            case version
        }
    }

    let category: String
    let plugins: [PluginEntry]
}
