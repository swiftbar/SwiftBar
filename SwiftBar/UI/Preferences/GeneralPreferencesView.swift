import LaunchAtLogin
import Preferences
import SwiftUI

enum ShellOptions: String, CaseIterable {
    case Terminal
    case iTerm
}

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
            Preferences.Section(title: "\(Localizable.Preferences.PluginsFolder.localized):") {
                Button(Localizable.Preferences.ChangePath.localized) {
                    AppShared.changePluginFolder()
                }
                Text(preferences.pluginDirectoryPath ?? Localizable.Preferences.PathIsNone.localized)
                    .preferenceDescription()
            }
            Preferences.Section(title: "\(Localizable.Preferences.Shell.localized):") {
                EnumPicker(selected: $preferences.terminal, title: "")
                    .frame(width: 120.0)
            }
            Preferences.Section(title: "\(Localizable.Preferences.UpdateLabel.localized):") {
                Button(Localizable.Preferences.CheckForUpdates.localized) {
                    AppShared.checkForUpdates()
                }.frame(width: 140.0)
            }
        }
    }
}
