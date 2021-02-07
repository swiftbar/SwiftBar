import SwiftUI

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
