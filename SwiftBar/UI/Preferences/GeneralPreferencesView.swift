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
                        AppShared.changePluginFolder()
                    }
                }
            }
            Spacer()
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
                        AppShared.checkForUpdates()
                    }
                }
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
