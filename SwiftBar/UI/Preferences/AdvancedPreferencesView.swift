import Preferences
import SwiftUI

struct AdvancedPreferencesView: View {
    @EnvironmentObject var preferences: PreferencesStore
    @State private var launchAtLogin = true

    var body: some View {
        Preferences.Container(contentWidth: 350) {
            Preferences.Section(title: "\(Localizable.Preferences.Terminal.localized):", verticalAlignment: .top) {
                EnumPicker(selected: $preferences.terminal, title: "")
                    .frame(width: 120.0)
            }
            Preferences.Section(title: "\(Localizable.Preferences.Shell.localized):", bottomDivider: true) {
                EnumPicker(selected: $preferences.shell, title: "")
                    .frame(width: 120.0)
            }
            Preferences.Section(title: "\(Localizable.Preferences.HideSwiftBarIcon.localized):", verticalAlignment: .top) {
                Toggle("", isOn: $preferences.swiftBarIconIsHidden)
            }
            Preferences.Section(title: "\(Localizable.Preferences.StealthMode.localized):", verticalAlignment: .top) {
                Toggle("", isOn: $preferences.stealthMode)
            }
        }
    }
}
