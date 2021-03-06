import SwiftUI

struct PluginsPreferencesView: View {
    @EnvironmentObject var preferences: Preferences

    var body: some View {
        VStack {
            if delegate.pluginManager.sortedPlugins.isEmpty {
                Text(Localizable.Preferences.NoPluginsMessage.localized)
                    .font(.largeTitle)
                    .padding(.bottom, 50)
            } else {
                PluginsView()
                HStack {
                    Text(Localizable.Preferences.PluginsFootnote.localized)
                        .font(.footnote)
                        .padding([.leading, .top], 5)
                    Spacer()
                }
            }
        }
    }
}

struct PluginsView: View {
    @EnvironmentObject var preferences: Preferences
    @State var showingDetail = false
    @State var selection: Int? = nil
    var plugins: [Plugin] {
        delegate.pluginManager.sortedPlugins
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(plugins, id: \.id) { plugin in
                    NavigationLink(
                        destination: PluginDetailsView(md: plugin.metadata ?? .empty(), plugin: plugin),
                        tag: plugins.firstIndex(where: { $0.id == plugin.id }) ?? 0,
                        selection: $selection,
                        label: {
                            PluginRowView(plugin: plugin)
                        }
                    )
                }.onMove(perform: move)
            } // .listStyle(SidebarListStyle())
            .onAppear(perform: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    selection = 1
                }
            })
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        preferences.pluginsOrder.move(fromOffsets: source, toOffset: destination)
    }
}

struct PluginRowView: View {
    @EnvironmentObject var preferences: Preferences
    @State private var enabled: Bool = false
    var label: String {
        guard let name = plugin.metadata?.name, !name.isEmpty else {
            return plugin.name
        }
        return name
    }

    let plugin: Plugin
    var body: some View {
        HStack(alignment: .center) {
            Toggle("", isOn: $enabled.onUpdate(updatePluginStatus))
            Text(label)
        }.onAppear {
            enabled = plugin.enabled
        }
    }

    private func updatePluginStatus() {
        enabled ? delegate.pluginManager.enablePlugin(plugin: plugin) :
            delegate.pluginManager.disablePlugin(plugin: plugin)
    }
}
