import Foundation

struct ExecutablePlugin: Plugin {
    var id: PluginID {
        return file
    }
    let type: PluginType = .Executable
    let name: String
    let file: String
    let metadata: PluginMetadata

    func refresh() {

    }

    func terminate() {

    }

    func invoke(params : [String]) {
        
    }
}
