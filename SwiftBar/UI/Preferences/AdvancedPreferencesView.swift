import SwiftUI

struct AdvancedPreferencesView: View {
    @EnvironmentObject var preferences: PreferencesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsPaneSection {
                SettingsPaneRow(title: Localizable.Preferences.Terminal.localized) {
                    EnumPicker(selected: $preferences.terminal, title: "")
                        .frame(width: 140)
                }

                SettingsPaneRow(title: Localizable.Preferences.Shell.localized) {
                    EnumPicker(selected: $preferences.shell, title: "")
                        .frame(width: 140)
                }
            }

            SettingsPaneSection {
                SettingsPaneRow(title: "") {
                    Toggle("", isOn: $preferences.swiftBarIconIsHidden)
                        .labelsHidden()
                    Text(Localizable.Preferences.HideSwiftBarIcon.localized)
                }

                SettingsPaneRow(title: "") {
                    Toggle("", isOn: $preferences.stealthMode)
                        .labelsHidden()
                    Text(Localizable.Preferences.StealthMode.localized)
                }
            }
        }
        .padding(18)
        .frame(width: 500, alignment: .topLeading)
    }
}
