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
            }
        }
    }
}

struct PluginRowView: View {
    @EnvironmentObject var preferences: Preferences
    var enabled: Bool {
        !preferences.disabledPlugins.contains(plugin.id)
    }

    let plugin: Plugin
    var body: some View {
        HStack {
            Circle()
                .frame(width: 15, height: 15, alignment: .center)
                .foregroundColor(enabled ? .green : .red)
                .padding(.leading)
            VStack(alignment: .leading) {
                Text(plugin.name)
                Text(plugin.id)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if enabled {
                Button("Disable") {
                    preferences.disabledPlugins.append(plugin.id)
                }
            } else {
                Button("Enable") {
                    preferences.disabledPlugins.removeAll(where: { $0 == plugin.id })
                }
            }
        }
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
