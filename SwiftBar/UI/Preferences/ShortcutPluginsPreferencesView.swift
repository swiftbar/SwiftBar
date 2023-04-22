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
                        PluginStateView(plugin: plugin, pluginManager: pluginManager)
                    }.width(10)
                    TableColumn(Localizable.Preferences.ShortcutsColumnName.localized, value: \.name) { plugin in
                        Text(plugin.name).font(.body)
                    }
                    TableColumn(Localizable.Preferences.ShortcutsColumnShortcut.localized, value: \.shortcut) { plugin in
                        Text("\(plugin.shortcut)").font(.body)
                    }
                    TableColumn(Localizable.Preferences.ShortcutsColumnRepeat.localized) { plugin in
                        Text("\(plugin.repeatString)").font(.body)
                    }.width(60)

                    TableColumn("") { plugin in
                        PluginStateRefreshView(plugin: plugin, pluginManager: pluginManager)
                    }.width(40)
                }
                .onChange(of: sorting) { pluginManager.shortcutPlugins.sort(using: $0) }
                .font(.title)
                Spacer()
            }.padding(8)
            Divider()

            HStack {
                Button(Localizable.Preferences.ShortcutsDeleteButton.localized, role: .destructive) {
                    isPresentingConfirm.toggle()
                }.confirmationDialog(Localizable.Preferences.ShortcutsDeleteConfirmation.localized.replacingOccurrences(of: "<selectedPlugin>", with: "\(selectedPlugin?.name ?? "")"),
                                     isPresented: $isPresentingConfirm) {
                    Button(Localizable.Preferences.ShortcutsDeleteButton.localized, role: .destructive) {
                        guard let selectedPlugin else { return }
                        pluginManager.removeShortcutPlugin(plugin: selectedPlugin.persistentPlugin)
                    }
                }.disabled(selecting == nil)

                Spacer()
                Button(Localizable.Preferences.ShortcutsAddButton.localized) {
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
struct PluginStateView: View {
    @ObservedObject var plugin: ShortcutPlugin
    var pluginManager: PluginManager
    var body: some View {
        VStack {
            Spacer()
            Button(action: {
                pluginManager.togglePlugin(plugin: plugin)
                plugin.enabled.toggle()
            }, label: {
                Circle()
                    .foregroundColor($plugin.enabled.wrappedValue ? .green : .red)
            }).help(Localizable.Preferences.ShortcutsColumnToggleHelp.localized)
            Spacer()
        }
    }
}

@available(macOS 12.0, *)
struct PluginStateRefreshView: View {
    @ObservedObject var plugin: ShortcutPlugin
    var pluginManager: PluginManager
    var body: some View {
        Button(action: {
            pluginManager.menuBarItems[plugin.id]?.dimOnManualRefresh()
            plugin.refresh(reason: .PluginSettings)
        }, label: {
            Image(systemName: "arrow.triangle.2.circlepath")
        }).buttonStyle(.link)
            .disabled(!$plugin.enabled.wrappedValue)
            .help(Localizable.Preferences.ShortcutsColumnRefreshHelp.localized)
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
            Text(Localizable.Preferences.AddShortcutPluginHeader.localized)
                .font(.headline)
            Group {
                VStack {
                    HStack {
                        Text(Localizable.Preferences.AddShortcutPluginName.localized)
                        TextField("", text: $name)
                    }
                    HStack {
                        Picker(Localizable.Preferences.AddShortcutPluginFolder.localized, selection: $prefs.shortcutsFolder, content: {
                            ForEach(shortcutsManager.folders, id: \.self) { shortcut in
                                Text(shortcut)
                            }
                        })
                        Picker(Localizable.Preferences.AddShortcutPluginShortcut.localized, selection: $selectedShortcut, content: {
                            ForEach(shortcutsManager.shortcuts, id: \.self) { shortcut in
                                Text(shortcut)
                            }
                        })
                        HStack(spacing: 0) {
                            Button(action: {
                                shortcutsManager.refresh()
                            }, label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }).help(Localizable.Preferences.AddShortcutPluginRefreshHelp.localized)

                            if !selectedShortcut.isEmpty {
                                Button(action: {
                                    shortcutsManager.viewCurrentShortcut(shortcut: selectedShortcut)
                                }, label: {
                                    Image(systemName: "slider.horizontal.3")
                                }).help(Localizable.Preferences.AddShortcutPluginOpenHelp.localized)
                            }

                            Button(action: {
                                shortcutsManager.createShortcut()
                            }, label: {
                                Image(systemName: "plus")
                            }).help(Localizable.Preferences.AddShortcutPluginNewHelp.localized)
                        }
                    }
                }
                HStack {
                    Text(Localizable.Preferences.AddShortcutPluginRefreshInterval.localized)
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
                Button(Localizable.MenuBar.GetPlugins.localized) {
                    AppShared.getPlugins()
                }.hidden()
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
