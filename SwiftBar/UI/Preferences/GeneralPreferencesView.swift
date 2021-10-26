import LaunchAtLogin
import Preferences
import SwiftUI

struct GeneralPreferencesView: View {
    @EnvironmentObject var preferences: PreferencesStore
    @State private var launchAtLogin = true

    var body: some View {
        Preferences.Container(contentWidth: 500) {
            Preferences.Section(title: "\(Localizable.Preferences.LaunchAtLogin.localized):") {
                LaunchAtLogin.Toggle {
                    Text(Localizable.Preferences.LaunchAtLogin.localized)
                }
            }
            Preferences.Section(title: "\(Localizable.Preferences.PluginsFolder.localized):", verticalAlignment: .top) {
                Button(Localizable.Preferences.ChangePath.localized) {
                    AppShared.changePluginFolder()
                }
                Text(preferences.pluginDirectoryPath ?? Localizable.Preferences.PathIsNone.localized)
                    .preferenceDescription()
            }
            Preferences.Section(title: "\(Localizable.Preferences.Terminal.localized):", verticalAlignment: .top) {
                EnumPicker(selected: $preferences.terminal, title: "")
                    .frame(width: 120.0)
            }
            Preferences.Section(title: "\(Localizable.Preferences.Shell.localized):", bottomDivider: true) {
                EnumPicker(selected: $preferences.shell, title: "")
                    .frame(width: 120.0)
            }
        
            Preferences.Section(title: "\(Localizable.Preferences.UpdateLabel.localized):", verticalAlignment: .top) {
                HStack{
                    Button(Localizable.Preferences.CheckForUpdates.localized) {
                        AppShared.checkForUpdates()
                    }
                }
            }
        }
    }
}
