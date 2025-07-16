import Preferences
import SwiftUI

struct PluginsPreferencesView: View {
    @ObservedObject var pluginManager: PluginManager

    var body: some View {
        VStack {
            if pluginManager.plugins.isEmpty {
                Text(Localizable.Preferences.NoPluginsMessage.localized)
                    .font(.largeTitle)
                    .padding(.bottom, 50)
            } else {
                PluginsView(plugin: pluginManager.plugins.first!, plugins: pluginManager.plugins.filter { $0.type == .Streamable || $0.type == .Executable })
            }
        }.frame(width: 750, height: 400)
    }
}

struct PluginsView: View {
    @State var plugin: Plugin

    var plugins: [Plugin]

    var body: some View {
        PluginPreferencesSplitView(master: {
            SidebarView(plugins: plugins, selectedPlugin: $plugin)
        }, detail: {
            PluginDetailsView(md: plugin.metadata ?? .empty(), plugin: plugin)
        })
    }
}

struct SidebarView: View {
    var plugins: [Plugin]
    @Binding var selectedPlugin: Plugin
    var body: some View {
        List {
            ForEach(plugins, id: \.id) { plugin in
                PluginRowView(plugin: plugin, selected: selectedPlugin.id == plugin.id)
                    .onTapGesture {
                        selectedPlugin = plugin
                        print(plugin.id)
                    }
                    .listRowBackground(Group {
                        if selectedPlugin.id == plugin.id {
                            Color(NSColor.selectedContentBackgroundColor).mask(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        } else { Color.clear }
                    })
            }
        }.listStyle(SidebarListStyle())
            .frame(minWidth: 200)
    }
}

struct PluginRowView: View {
    @State private var enabled: Bool = false
    var label: String {
        guard let name = plugin.metadata?.name, !name.isEmpty else {
            return plugin.name
        }
        return name
    }

    let plugin: Plugin
    var selected: Bool = false
    var body: some View {
        HStack(alignment: .center) {
            Toggle("", isOn: $enabled.onUpdate(updatePluginStatus))

            if selected {
                Text(label)
                    .foregroundColor(Color.white)
            } else {
                Text(label)
            }
        }.onAppear {
            enabled = plugin.enabled
        }.padding(5)
    }

    private func updatePluginStatus() {
        enabled ? delegate.pluginManager.enablePlugin(plugin: plugin) :
            delegate.pluginManager.disablePlugin(plugin: plugin)
    }
}

struct PluginPreferencesSplitView<Master: View, Detail: View>: View {
    var master: Master
    var detail: Detail

    init(@ViewBuilder master: () -> Master, @ViewBuilder detail: () -> Detail) {
        self.master = master()
        self.detail = detail()
    }

    var body: some View {
        let viewControllers = [NSHostingController(rootView: master), NSHostingController(rootView: detail)]
        return SplitViewController(viewControllers: viewControllers)
    }
}

struct SplitViewController: NSViewControllerRepresentable {
    typealias NSViewControllerType = NSSplitViewController

    var viewControllers: [NSViewController]

    func makeNSViewController(context _: Context) -> NSSplitViewController {
        NSSplitViewController()
    }

    func updateNSViewController(_ splitController: NSSplitViewController, context _: Context) {
        splitController.children = viewControllers
    }
}
