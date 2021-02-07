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
                    .padding(5)
                HStack {
                    Spacer()
                    Button(Localizable.Preferences.EnableAll.localized) {
                        delegate.pluginManager.enableAllPlugins()
                    }
                    .padding(.trailing)
                }
                Text(Localizable.Preferences.PluginsFootnote.localized)
                    .font(.footnote)
            }
        }
    }
}

struct PluginsView: View {
    @EnvironmentObject var preferences: Preferences

    var plugins: [Plugin] {
        delegate.pluginManager.sortedPlugins
    }

    var body: some View {
        List {
            ForEach(plugins, id: \.id) { plugin in
                VStack {
                    PluginRowView(plugin: plugin)
                    Divider()
                }
            }.onMove(perform: move)
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        preferences.pluginsOrder.move(fromOffsets: source, toOffset: destination)
    }
}

struct PluginRowView: View {
    @EnvironmentObject var preferences: Preferences
    @State private var enabled: Bool = false
    @State private var showPopover: Bool = false

    var lastUpdated: String? {
        guard let date = plugin.lastUpdated else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date()).capitalized
    }

    let plugin: Plugin
    var body: some View {
        HStack {
            Toggle("", isOn: $enabled.onUpdate(updatePluginStatus))
            VStack(alignment: .leading) {
                HStack(spacing: 1) {
                    Text(plugin.metadata?.name ?? plugin.name)
                    if let version = plugin.metadata?.version {
                        Text("(\(version))")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                HStack(alignment: .bottom, spacing: 1) {
                    Text(plugin.id)
                        .onTapGesture {
                            App.openPluginFolder(path: plugin.file)
                        }
                    if let author = plugin.metadata?.author {
                        Text(", by " + author)
                    }
                }
                .font(.footnote)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
            Spacer()
            if let md = plugin.metadata, !md.isEmpty {
                Text("ⓘ")
                    .onTapGesture {
                        self.showPopover = true
                    }.popover(
                        isPresented: self.$showPopover,
                        arrowEdge: .bottom
                    ) { AboutPluginView(md: md) }
            }
            if #available(OSX 11.0, *) {
                Image(systemName: "line.horizontal.3")
            }
        }.onAppear {
            enabled = plugin.enabled
        }
    }

    private func updatePluginStatus() {
        enabled ? delegate.pluginManager.enablePlugin(plugin: plugin) :
            delegate.pluginManager.disablePlugin(plugin: plugin)
    }
}
