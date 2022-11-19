import Preferences
import SwiftUI

struct PluginDetailsView: View {
    @ObservedObject var md: PluginMetadata
    let plugin: Plugin
    @State var isEditing: Bool = false
    @State var dependencies: String = ""
    let screenProportion: CGFloat = 0.3
    let width: CGFloat = 400
    var body: some View {
        Preferences.Container(contentWidth: 500) {
            Preferences.Section(label: {
                HStack {
                    Text("About Plugin")
                    if #available(OSX 11.0, *) {
                        Button(action: {
                            AppShared.openPluginFolder(path: plugin.file)
                        }) {
                            Image(systemName: "folder")
                        }.padding(.trailing)
                    }
                    Spacer()
                }
            }, content: {})
            Preferences.Section(label: {
                PluginDetailsTextView(label: "Name",
                                      text: $md.name,
                                      width: width * screenProportion)
            }, content: {})
            Preferences.Section(label: {
                PluginDetailsTextView(label: "Description",
                                      text: $md.desc,
                                      width: width * screenProportion)
            }, content: {})
            Preferences.Section(label: {
                PluginDetailsTextView(label: "Dependencies",
                                      text: $dependencies,
                                      width: width * screenProportion)
                    .onAppear(perform: {
                        dependencies = md.dependencies.joined(separator: ",")
                    })
            }, content: {})
            Preferences.Section(label: {
                HStack {
                    PluginDetailsTextView(label: "GitHub",
                                          text: $md.github,
                                          width: width * screenProportion)
                    PluginDetailsTextView(label: "Author",
                                          text: $md.author,
                                          width: width * 0.2)
                }
            }, content: {})
            Preferences.Section(bottomDivider: true, label: {
                HStack {
                    PluginDetailsTextView(label: "Version",
                                          text: $md.version,
                                          width: width * screenProportion)
                    PluginDetailsTextView(label: "Schedule",
                                          text: $md.schedule,
                                          width: width * 0.2)
                }
            }, content: {})
            Preferences.Section(label: {
                HStack {
                    Text("Hide Menu Items:")
                    Spacer()
                }
            }, content: {})
            Preferences.Section(label: {
                HStack {
                    PluginDetailsToggleView(label: "About",
                                            state: $md.hideAbout,
                                            width: width * screenProportion)
                    PluginDetailsToggleView(label: "Run in Terminal",
                                            state: $md.hideRunInTerminal,
                                            width: width * screenProportion)
                    PluginDetailsToggleView(label: "Last Updated",
                                            state: $md.hideLastUpdated,
                                            width: width * screenProportion)
                }
            }, content: {})

            Preferences.Section(bottomDivider: true, label: {
                HStack {
                    PluginDetailsToggleView(label: "SwiftBar",
                                            state: $md.hideSwiftBar,
                                            width: width * screenProportion)

                    PluginDetailsToggleView(label: "Disable Plugin",
                                            state: $md.hideDisablePlugin,
                                            width: width * screenProportion)
                }
            }, content: {})

            Preferences.Section(title: "", content: {})
            Preferences.Section(label: {
                HStack {
                    if #available(macOS 11.0, *) {
                        Button(action: {
                            NSWorkspace.shared.open(URL(string: "https://github.com/swiftbar/SwiftBar#metadata-for-binary-plugins")!)
                        }, label: {
                            Image(systemName: "questionmark.circle")
                        }).buttonStyle(LinkButtonStyle())
                    }
                    Spacer()
                    Button("Reset", action: {
                        PluginMetadata.cleanMetadata(fileURL: URL(fileURLWithPath: plugin.file))
                        plugin.refreshPluginMetadata()
                    })
                    Button("Save in Plugin File", action: {
                        PluginMetadata.writeMetadata(metadata: md, fileURL: URL(fileURLWithPath: plugin.file))
                    })
                }

            }, content: {})
        }
    }
}

struct PluginDetailsTextView: View {
    @EnvironmentObject var preferences: PreferencesStore
    let label: String
    @Binding var text: String
    let width: CGFloat
    var body: some View {
        HStack {
            HStack {
                Spacer()
                Text("\(label):")
            }.frame(width: width)
            TextField("", text: $text)
                .disabled(!PreferencesStore.shared.pluginDeveloperMode)
            Spacer()
        }
    }
}

struct PluginDetailsToggleView: View {
    let label: String
    @Binding var state: Bool
    let width: CGFloat
    var body: some View {
        HStack {
            HStack {
                Spacer()
                Text("\(label):")
            }.frame(width: width)
            Toggle("", isOn: $state)
        }
    }
}
