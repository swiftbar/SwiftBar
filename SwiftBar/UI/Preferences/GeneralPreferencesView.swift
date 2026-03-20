import SwiftUI

struct GeneralPreferencesView: View {
    @EnvironmentObject var preferences: PreferencesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsPaneSection {
                SettingsPaneRow(title: Localizable.Preferences.LaunchAtLogin.localized) {
                    ModernLaunchAtLogin.Toggle {
                        Text(Localizable.Preferences.LaunchAtLogin.localized)
                    }
                    .labelsHidden()
                }

                SettingsPaneRow(title: Localizable.Preferences.MenuBarItem.localized) {
                    Toggle("", isOn: $preferences.dimOnManualRefresh)
                        .labelsHidden()
                    Text(Localizable.Preferences.DimOnManualRefresh.localized)
                }
            }

            SettingsPaneSection {
                SettingsPaneRow(title: Localizable.Preferences.PluginsFolder.localized, alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Button(Localizable.Preferences.ChangePath.localized) {
                            AppShared.changePluginFolder()
                        }

                        Text(preferences.pluginDirectoryPath ?? Localizable.Preferences.PathIsNone.localized)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            SettingsPaneSection {
                SettingsPaneRow(title: Localizable.Preferences.UpdateLabel.localized) {
                    Button(Localizable.Preferences.CheckForUpdates.localized) {
                        AppShared.checkForUpdates()
                    }
                }

                SettingsPaneRow(title: "") {
                    Toggle("", isOn: $preferences.includeBetaUpdates)
                        .labelsHidden()
                    Text(Localizable.Preferences.IncludeBetaUpdates.localized)
                }
            }
        }
        .padding(18)
        .frame(width: 500, alignment: .topLeading)
    }
}

struct SettingsPaneSection<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

struct SettingsPaneRow<Content: View>: View {
    let title: String
    let alignment: VerticalAlignment
    @ViewBuilder let content: Content

    init(
        title: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: 12) {
            if title.isEmpty {
                Spacer()
                    .frame(width: 148)
            } else {
                Text("\(title):")
                    .foregroundColor(.secondary)
                    .frame(width: 148, alignment: .trailing)
            }

            HStack(alignment: .center, spacing: 8) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
