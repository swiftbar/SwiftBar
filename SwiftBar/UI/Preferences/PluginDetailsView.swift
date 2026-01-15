import Preferences
import SwiftUI

struct PluginDetailsView: View {
    @ObservedObject var md: PluginMetadata
    let plugin: Plugin
    @State var isEditing: Bool = false
    @State var dependencies: String = ""
    @State var userVariableValues: [String: String] = [:]
    let screenProportion: CGFloat = 0.3
    let width: CGFloat = 400
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
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

                    Preferences.Section(bottomDivider: !md.variables.isEmpty, label: {
                        HStack {
                            PluginDetailsToggleView(label: "SwiftBar",
                                                    state: $md.hideSwiftBar,
                                                    width: width * screenProportion)

                            PluginDetailsToggleView(label: "Disable Plugin",
                                                    state: $md.hideDisablePlugin,
                                                    width: width * screenProportion)
                        }
                    }, content: {})
                }

                // Plugin Variables Section
                if !md.variables.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Plugin Variables:")
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)

                        ForEach(md.variables) { variable in
                            PluginVariableEditorView(
                                variable: variable,
                                value: bindingForVariable(variable),
                                width: width * screenProportion
                            )
                            .padding(.horizontal)
                        }

                        Divider()
                            .padding(.top, 8)
                    }
                }

                // Buttons section
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
                .padding()
            }
        }
        .onAppear {
            loadUserVariableValues()
        }
        .onChange(of: plugin.id) { _ in
            loadUserVariableValues()
        }
        .id(plugin.id)
    }

    private func loadUserVariableValues() {
        userVariableValues = PluginVariableStorage.loadUserValues(pluginFile: plugin.file)
        // Fill in defaults for any missing values
        for variable in md.variables where userVariableValues[variable.name] == nil {
            userVariableValues[variable.name] = variable.defaultValue
        }
    }

    private func bindingForVariable(_ variable: PluginVariable) -> Binding<String> {
        Binding(
            get: { userVariableValues[variable.name] ?? variable.defaultValue },
            set: { newValue in
                userVariableValues[variable.name] = newValue
                PluginVariableStorage.saveUserValues(userVariableValues, pluginFile: plugin.file)
                // Refresh the plugin to apply changes
                plugin.refresh(reason: .PluginSettings)
            }
        )
    }
}

struct PluginVariableEditorView: View {
    let variable: PluginVariable
    @Binding var value: String
    let width: CGFloat

    // Local state for text editing to avoid refreshing on every keystroke
    @State private var editingText: String = ""
    @State private var debounceWorkItem: DispatchWorkItem?

    var body: some View {
        HStack {
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(variable.name):")
                    if !variable.description.isEmpty {
                        Text(variable.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }.frame(width: width)

            switch variable.type {
            case .boolean:
                Toggle("", isOn: Binding(
                    get: { value.lowercased() == "true" },
                    set: { value = $0 ? "true" : "false" }
                ))
                Spacer()
            case .select:
                Picker("", selection: $value) {
                    ForEach(variable.options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .frame(maxWidth: 150)
                Spacer()
            case .string, .number:
                TextField("", text: $editingText)
                    .onAppear { editingText = value }
                    .onChange(of: editingText) { newText in
                        scheduleCommit(newText: newText)
                    }
                    .onChange(of: value) { newValue in
                        // External value change - update local text if different
                        if editingText != newValue {
                            debounceWorkItem?.cancel()
                            editingText = newValue
                        }
                    }
                Spacer()
            }
        }
    }

    private func scheduleCommit(newText: String) {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            if editingText == newText && newText != value {
                value = newText
            }
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
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
