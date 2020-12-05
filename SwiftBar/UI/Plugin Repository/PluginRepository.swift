import Foundation
import os

class PluginRepository: ObservableObject {
    static let shared = PluginRepository()
    let prefs = Preferences.shared

    @Published var repository: [RepositoryEntry] {
        didSet {
            categories = Array(Set(repository.map{$0.category})).sorted()
        }
    }

    var categories: [String]

    init() {
        guard let repository = PluginRepository.parseRepositoryFile()
        else {
            self.repository = []
            self.categories = []
            refreshRepository()
            return
        }

        self.repository = repository
        self.categories = Array(Set(repository.map{$0.category})).sorted()
    }

    func getPlugins(for category: String) -> [RepositoryEntry.PluginEntry] {
        repository.filter{$0.category == category}.flatMap{$0.plugins}
    }

    func refreshRepository() {
        guard let pluginDirectoryPath = prefs.pluginDirectoryPath else {return}
        let pluginDirectoryURL = URL(fileURLWithPath: pluginDirectoryPath)

        os_log("Refreshing plugin repository...", log: Log.repository)
        let url = URL(string: "https://raw.githubusercontent.com/swiftbar/swiftbar-plugins/main/repository.json")!
        
        let downloadTask = URLSession.shared.downloadTask(with: url) {[weak self] fileURL, _, _ in
            guard let fileURL = fileURL else {
                os_log("Failed to download plugin repository manifest.", log: Log.repository)
                return
            }
            os_log("Plugin repository manifest downloaded!", log: Log.repository)
            do {
                let targetURL = pluginDirectoryURL.appendingPathComponent(".repository.json")
                try FileManager.default.moveItem(atPath: fileURL.path, toPath: targetURL.path)
                guard let rep = PluginRepository.parseRepositoryFile() else {return}
                self?.categories = Array(Set(rep.map{$0.category})).sorted()
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
        guard let pluginDirectoryPath = Preferences.shared.pluginDirectoryPath else {return nil}
        let url = URL(fileURLWithPath: pluginDirectoryPath).appendingPathComponent(".repository.json")

        guard let jsonStr = try? String(contentsOfFile: url.path),
            let data = jsonStr.data(using: .utf8),
            let repository = try? JSONDecoder().decode([RepositoryEntry].self, from: data)
        else {return nil}
        return repository
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

        enum CodingKeys : String, CodingKey {
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
