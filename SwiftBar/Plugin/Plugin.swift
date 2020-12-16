import Foundation
import ShellOut

enum PluginType {
    case Executable
    case Streamable
}

enum PluginState {
    case Loading
    case Success
    case Failed
}

typealias PluginID = String

protocol Plugin {
    var id: PluginID { get }
    var type: PluginType { get }
    var name: String { get }
    var file: String { get }
    var enabled: Bool { get }
    var metadata: PluginMetadata? { get }
    var updateInterval: Double { get }
    var lastUpdated: Date? { get set }
    var lastState: PluginState { get set }
    var content: String? { get set }
    var error: ShellOutError? { get set }
    func refresh()
    func terminate()
    func invoke(params: [String]) -> String?
}

extension Plugin {
    var executablePlugin: ExecutablePlugin? {
        self as? ExecutablePlugin
    }

    var description: String {
        """
        id: \(id)
        type: \(type)
        name: \(name)
        path: \(file)
        metadata:
            name: \(metadata?.name ?? "")
            author: \(metadata?.author ?? "")
            version: \(metadata?.version ?? "")
            github: \(metadata?.github ?? "")
            desc: \(metadata?.desc ?? "")
            previewImageURL: \(metadata?.previewImageURL?.absoluteString ?? "")
            dependencies: \(metadata?.dependencies?.joined(separator: ",") ?? "")
            aboutURL: \(metadata?.aboutURL?.absoluteString ?? "")
        """
    }
}
