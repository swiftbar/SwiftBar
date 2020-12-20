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
                LaunchAtLogin.Toggle {
                    Text(Localizable.Preferences.LaunchAtLogin.localized)
                }
                .padding(.bottom)
            }
            Section(header: Text(Localizable.Preferences.PluginsFolder.localized)) {
                HStack(alignment: .top) {
                    Text(Localizable.Preferences.Path.localized + ": ")
                    Text(preferences.pluginDirectoryPath ?? Localizable.Preferences.PathIsNone.localized)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.top)
                HStack {
                    Spacer()
                    Button(Localizable.Preferences.ChangePath.localized) {
                        App.changePluginFolder()
                    }
                }
            }
            Section(header: Text(Localizable.Preferences.Shell.localized)) {
                EnumPicker(selected: $preferences.terminal, title: "")
            }
            Section {
                Toggle(isOn: $preferences.swiftBarIconIsHidden) {
                    Text(Localizable.Preferences.HideSwiftBarIcon.localized)
                }.padding(.top)
            }
            Section {
                HStack {
                    Spacer()
                    Button(Localizable.Preferences.CheckForUpdates.localized) {
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
                Text(Localizable.Preferences.NoPluginsMessage.localized)
                    .font(.largeTitle)
                    .padding(.bottom, 50)
            } else {
                PluginsView()
                    .padding()
                HStack {
                    Spacer()
                    Button(Localizable.Preferences.EnableAll.localized) {
                        delegate.pluginManager.enableAllPlugins()
                    }.padding()
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
            enabled = plugin.enabled
        }
    }

    private func updatePluginStatus() {
        enabled ? delegate.pluginManager.enablePlugin(plugin: plugin) :
            delegate.pluginManager.disablePlugin(plugin: plugin)
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
                    Text(Localizable.Preferences.General.localized)
                }
                .tag(Tabs.general)
            PluginsPreferencesView()
                .tabItem {
                    Text(Localizable.Preferences.Plugins.localized)
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
