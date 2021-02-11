import SwiftUI

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
        .frame(width: tabSelectedIndex == .plugins ? 700 : 500,
               height: tabSelectedIndex == .plugins ? 470 : 400)
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
