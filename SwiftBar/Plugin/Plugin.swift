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
    var metadata: PluginMetadata { get }
    func refresh()
    func terminate()
    func invoke(params: [String])
}
