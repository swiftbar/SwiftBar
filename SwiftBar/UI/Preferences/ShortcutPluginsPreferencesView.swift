import Combine
import Preferences
import SwiftUI

@available(macOS 12.0, *)
struct ShortcutPluginsPreferencesView: View {
    @ObservedObject var pluginManager: PluginManager
    @EnvironmentObject var shortcutsManager: ShortcutsManager
    @State private var showingSheet = false
    @State private var isPresentingConfirm: Bool = false
    @State var sorting = [KeyPathComparator(\ShortcutPlugin.name)]
    @State var selecting: ShortcutPlugin.ID?
    var selectedPlugin: ShortcutPlugin? {
        guard let selecting else { return nil }
        return pluginManager.shortcutPlugins.first(where: { $0.id == selecting })
    }

    var body: some View {
        VStack {
            HStack {
                Table(pluginManager.shortcutPlugins, selection: $selecting, sortOrder: $sorting) {
                    TableColumn("") { plugin in
                        VStack {
                            Spacer()
                            Button(action: {
                                pluginManager.togglePlugin(plugin: plugin)
                            }, label: {
                                Circle()
                                    .foregroundColor(plugin.enabled ? .green : .red)
                            }).help("Enable/Disable menu bar item")
                            Spacer()
                        }
                    }.width(15)
                    TableColumn("Name", value: \.name) { plugin in
                        Text(plugin.name).font(.title2)
                    }
                    TableColumn("Shortcut", value: \.shortcut) { plugin in
                        Text("\(plugin.shortcut)").font(.title2)
                    }
                    TableColumn("Repeat") { plugin in
                        Text("\(plugin.repeatString)").font(.title2)
                    }.width(60)

                    TableColumn("") { plugin in
                        Button(action: {
                            pluginManager.menuBarItems[plugin.id]?.dimOnManualRefresh()
                            plugin.refresh(reason: .PluginSettings)
                        }, label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }).buttonStyle(.link)
                            .help("Refresh menu bar item")
                    }.width(40)
                }
                .onChange(of: sorting) { pluginManager.shortcutPlugins.sort(using: $0) }
                .font(.title)
                Spacer()
            }.padding(8)
            Divider()

            HStack {
                Button("Delete", role: .destructive) {
                    isPresentingConfirm.toggle()
                }.confirmationDialog("Deleting \("selectedPlugin"). Are you sure?",
                                     isPresented: $isPresentingConfirm) {
                    Button("Delete", role: .destructive) {
                        guard let selectedPlugin else { return }
                        pluginManager.removeShortcutPlugin(plugin: selectedPlugin.persistentPlugin)
                    }
                }.disabled(selecting == nil)

                Spacer()
                Button("Add") {
                    showingSheet.toggle()
                }
                .sheet(isPresented: $showingSheet) {
                    AddShortcutPluginView(pluginManager: pluginManager, isPresented: $showingSheet)
                }
            }.padding([.trailing, .leading], 20)
                .padding(.bottom, 10)
        }.frame(width: 750, height: 400)
    }
}

@available(macOS 12.0, *)
struct AddShortcutPluginView: View {
    @ObservedObject var pluginManager: PluginManager
    @Binding var isPresented: Bool
    @State var selectedShortcut: String = ""
    @State var name: String = ""
    @State var refreshValue: String = "1"

    @State var refreshUnit: String = "s"
    @ObservedObject var shortcutsManager = ShortcutsManager.shared
    @ObservedObject var prefs = PreferencesStore.shared

    var body: some View {
        VStack {
            Text("Add Plugin")
                .font(.headline)
            Group {
                VStack {
                    HStack {
                        Text("Name:")
                        TextField("Unique Plugin Name...", text: $name)
                        Spacer()
                    }
                    HStack {
                        Picker("Folder:", selection: $prefs.shortcutsFolder, content: {
                            ForEach(shortcutsManager.folders, id: \.self) { shortcut in
                                Text(shortcut)
                            }
                        })
                        Picker("Shortcut:", selection: $selectedShortcut, content: {
                            ForEach(shortcutsManager.shortcuts, id: \.self) { shortcut in
                                Text(shortcut)
                            }
                        })
                        HStack(spacing: 0) {
                            Button(action: {
                                shortcutsManager.refresh()
                            }, label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }).help("Refresh Shortcuts List")

                            if !selectedShortcut.isEmpty {
                                Button(action: {
                                    shortcutsManager.viewCurrentShortcut(shortcut: selectedShortcut)
                                }, label: {
                                    Image(systemName: "slider.horizontal.3")
                                }).help("Open in Shortcuts.app")
                            }

                            Button(action: {
                                shortcutsManager.createShortcut()
                            }, label: {
                                Image(systemName: "plus")
                            }).help("Create New Shortcut")
                        }
                    }
                }
                HStack {
                    Text("Refresh every:")
                    HStack(spacing: 0) {
                        TextField("1", text: $refreshValue)
                            .frame(width: 40)
                        Picker("", selection: $refreshUnit, content: {
                            ForEach(["s", "m", "h"], id: \.self) { shortcut in
                                Text(shortcut)
                            }
                        }).pickerStyle(SegmentedPickerStyle())
                            .frame(width: 80)
                    }
                    Spacer()
                }
            }.padding(8)

            Divider()
            HStack {
                Button("Get Plugins...") {
                    AppShared.getPlugins()
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    isPresented = false
                }
                Button("Save") {
                    isPresented = false
                    let plugin = PersistentShortcutPlugin(id: UUID().uuidString, name: name, shortcut: selectedShortcut, repeatString: refreshValue + refreshUnit, cronString: "")
                    pluginManager.addShortcutPlugin(plugin: plugin)
                }.disabled(selectedShortcut.isEmpty || name.isEmpty || refreshValue.isEmpty || refreshValue.contains(where: { !$0.isNumber }))
            }.padding(8)
        }.onAppear { shortcutsManager.getShortcuts() }
    }
}

@available(macOS 12.0, *)
struct ShortcutPluginsPreferencesView_Previews: PreviewProvider {
    @State static var isPresented: Bool = true
    static var previews: some View {
        Group {
            ShortcutPluginsPreferencesView(pluginManager: PluginManager.shared)
            AddShortcutPluginView(pluginManager: PluginManager.shared, isPresented: $isPresented)
        }
    }
}
