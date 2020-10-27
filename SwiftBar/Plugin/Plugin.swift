import Foundation

enum PluginType {
    case Executable
    case Streamable
}

typealias PluginID = String

protocol Plugin {
    var id: PluginID { get }
    var type: PluginType { get }
    var name: String { get }
    var file: String { get }
    var metadata: PluginMetadata? { get }
    func refresh()
    func terminate()
    func invoke(params: [String]) -> String?
}

extension Plugin {
    var description: String {
        return """
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
            previewImageURL: \(metadata?.previewImageURL ?? "")
            dependencies: \(metadata?.dependencies.joined(separator: ",") ?? "")
            aboutURL: \(metadata?.aboutURL?.absoluteString ?? "")
        """
    }
}
