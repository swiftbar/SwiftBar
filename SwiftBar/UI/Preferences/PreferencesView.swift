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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PluginsPreferencesView: View {
    @EnvironmentObject var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading) {
            if delegate.pluginManager.plugins.isEmpty {
                Text(Localizable.Preferences.NoPluginsMessage.localized)
                    .font(.largeTitle)
                    .padding(.bottom, 50)
            } else {
                PluginsView()
                Text(Localizable.Preferences.PluginsFootnote.localized)
                    .font(.footnote)
                    .padding(.leading, 5)
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
        NavigationView {
            List {
                ForEach(plugins, id: \.id) { plugin in
                    NavigationLink(
                        destination: PluginDetailsView(md: plugin.metadata ?? .empty()),
                        label: {
                            PluginRowView(plugin: plugin)
                        }
                    )
                }
            }
        }
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

    var lastUpdated: String? {
        guard let date = plugin.lastUpdated else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date()).capitalized
    }

    let plugin: Plugin
    var body: some View {
        HStack(alignment: .bottom) {
            Toggle("", isOn: $enabled.onUpdate(updatePluginStatus))
            Text(label)

            Spacer()
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

    @State var tabSelectedIndex: Tabs = .general
    var body: some View {
        TabView(selection: $tabSelectedIndex) {
            GeneralPreferencesView()
                .tabItem {
                    if #available(OSX 11.0, *) {
                        Label(Localizable.Preferences.General.localized, systemImage: "gear")
                    } else {
                        Text(Localizable.Preferences.General.localized)
                    }
                }
                .tag(Tabs.general)
            PluginsPreferencesView()
                .tabItem {
                    if #available(OSX 11.0, *) {
                        Label(Localizable.Preferences.Plugins.localized, systemImage: "list.bullet")
                    } else {
                        Text(Localizable.Preferences.Plugins.localized)
                    }
                }
                .tag(Tabs.plugins)
        }
        .padding(20)
        .frame(width: tabSelectedIndex == .plugins ? 700 : 500,
               height: tabSelectedIndex == .plugins ? 470 : 400)
    }
}

struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PreferencesView()
                .environmentObject(Preferences.shared)
        }
    }
}
