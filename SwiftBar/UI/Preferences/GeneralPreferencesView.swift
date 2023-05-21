import LaunchAtLogin
import Preferences
import SwiftUI

struct GeneralPreferencesView: View {
    @EnvironmentObject var preferences: PreferencesStore
    @State private var launchAtLogin = true

    var body: some View {
        Preferences.Container(contentWidth: 350) {
            Preferences.Section(title: "\(Localizable.Preferences.LaunchAtLogin.localized):") {
                LaunchAtLogin.Toggle {
                    Text(Localizable.Preferences.LaunchAtLogin.localized)
                }
            }
            Preferences.Section(title: "\(Localizable.Preferences.MenuBarItem.localized):", verticalAlignment: .top) {
                Toggle(Localizable.Preferences.DimOnManualRefresh.localized, isOn: $preferences.dimOnManualRefresh)
            }

            Preferences.Section(title: "\(Localizable.Preferences.PluginsFolder.localized):", verticalAlignment: .top) {
                Button(Localizable.Preferences.ChangePath.localized) {
                    AppShared.changePluginFolder()
                }
                Text(preferences.pluginDirectoryPath ?? Localizable.Preferences.PathIsNone.localized)
                    .preferenceDescription()
                Spacer()
            }
            Preferences.Section(title: "\(Localizable.Preferences.UpdateLabel.localized):", verticalAlignment: .top) {
                HStack {
                    Button(Localizable.Preferences.CheckForUpdates.localized) {
                        AppShared.checkForUpdates()
                    }
                }
                Toggle(Localizable.Preferences.IncludeBetaUpdates.localized, isOn: $preferences.includeBetaUpdates)
                Spacer()
            }
        }
    }
}
