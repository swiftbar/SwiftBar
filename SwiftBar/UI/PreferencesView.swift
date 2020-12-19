import LaunchAtLogin
import SwiftUI

enum ShellOptions: String, CaseIterable {
    case Terminal
    case iTerm
}

struct GeneralPreferencesView: View {
    @EnvironmentObject var preferences: Preferences
    @State private var launchAtLogin = true

    var body: some View {
        Form {
            Section {
                LaunchAtLogin.Toggle()
                    .padding(.bottom)
            }
            Section(header: Text("Plugin Folder")) {
                HStack(alignment: .top) {
                    Text("Path: ")
                    Text(preferences.pluginDirectoryPath ?? "None")
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.top)
                HStack {
                    Spacer()
                    Button("Change") {
                        App.changePluginFolder()
                    }
                }
            }
            Section(header: Text("Shell")) {
                EnumPicker(selected: $preferences.terminal, title: "")
            }
            Section {
                Toggle(isOn: $preferences.swiftBarIconIsHidden) {
                    Text("Hide SwiftBar Icon")
                }.padding(.top)
            }
            Section {
                HStack {
                    Spacer()
                    Button("Check for updates") {
                        App.checkForUpdates()
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 350, height: 100)
    }
}

struct PluginsPreferencesView: View {
    @EnvironmentObject var preferences: Preferences

    var body: some View {
        VStack {
            if delegate.pluginManager.plugins.isEmpty {
                Text("Plugins folder is empty")
                    .font(.largeTitle)
                    .padding(.bottom, 50)
            } else {
                PluginsView()
                    .padding()
                HStack {
                    Spacer()
                    Button("Reset All") {
                        preferences.disabledPlugins.removeAll()
                    }.padding()
                }
                Text("Enabled plugins appear in the menu bar.")
                    .font(.footnote)
            }
        }
    }
}

struct PluginsView: View {
    @EnvironmentObject var preferences: Preferences

    var plugins: [Plugin] {
        delegate.pluginManager.plugins
    }

    var body: some View {
        ScrollView(showsIndicators: true) {
            Form {
                Section {
                    ForEach(plugins, id: \.id) { plugin in
                        VStack {
                            PluginRowView(plugin: plugin)
                            Divider()
                        }
                    }
                }
            }.padding(.trailing)
        }
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
            if let md = plugin.metadata {
                Text("ⓘ")
                    .onTapGesture {
                        self.showPopover = true
                    }.popover(
                        isPresented: self.$showPopover,
                        arrowEdge: .bottom
                    ) { AboutPluginView(md: md) }
            }
        }.onAppear {
            enabled = !preferences.disabledPlugins.contains(plugin.id)
        }
    }

    private func updatePluginStatus() {
        enabled ? preferences.disabledPlugins.removeAll(where: { $0 == plugin.id }) :
            preferences.disabledPlugins.append(plugin.id)
    }
}

struct PreferencesView: View {
    @EnvironmentObject var preferences: Preferences
    enum Tabs: Hashable {
        case general, plugins
    }

    var body: some View {
        TabView {
            GeneralPreferencesView()
                .tabItem {
                    Text("General")
                }
                .tag(Tabs.general)
            PluginsPreferencesView()
                .tabItem {
                    Text("Plugins")
                }
                .tag(Tabs.plugins)
        }
        .padding(20)
        .frame(width: 500, height: 400)
    }
}

struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PreferencesView()
                .environmentObject(Preferences.shared)
            PreferencesView()
                .environmentObject(Preferences.shared)
        }
    }
}
