import SwiftUI

struct PluginErrorView: View {
    var plugin: Plugin
    var lastUpdateDate: String {
        let date = plugin.lastUpdated ?? Date.distantPast
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    var body: some View {
        ScrollView(showsIndicators: true) {
            Form {
                LabelView(label: "Plugin:", value: plugin.name)
                LabelView(label: "File:", value: plugin.file)
                LabelView(label: "Runned at:", value: lastUpdateDate)
                LabelView(label: "Error:", value: errorMessage())
                LabelView(label: "Script Output:", value: errorOutput())
            }.padding()
                .frame(width: 500)
        }
    }

    func errorMessage() -> String {
        switch plugin.type {
        case .Executable, .Streamable:
            (plugin.error as? ShellOutError)?.message ?? "none"
        case .Shortcut:
            (plugin.error as? RunShortcutError)?.message ?? "none"
        case .Ephemeral:
            "none"
        }
    }

    func errorOutput() -> String {
        switch plugin.type {
        case .Executable, .Streamable:
            (plugin.error as? ShellOutError)?.output ?? "none"
        case .Shortcut, .Ephemeral:
            "none"
        }
    }
}

struct PluginErrorView_Previews: PreviewProvider {
    static var previews: some View {
        PluginErrorView(plugin: ExecutablePlugin(fileURL: URL(string: "/Users/melonamin/Downloads/bitbar-scripts-copy/mounted.5s.sh")!))
    }
}
