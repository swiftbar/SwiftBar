import os
import SwiftUI

struct PluginRepositoryView: View {
    @ObservedObject var pluginRepository = PluginRepository.shared
    @State var pluginModalPresented = false

    var body: some View {
        if pluginRepository.categories.isEmpty {
            VStack {
                Text(Localizable.PluginRepository.RefreshingDataMessage.localized)
                    .font(.largeTitle)
                    .padding()

                Image(nsImage: NSImage(named: "AppIcon")!)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(0.6)

            }.frame(width: 400, height: 200)

        } else {
            if pluginRepository.searchString.isEmpty {
                SplitView(categories: $pluginRepository.categories)
                    .frame(minWidth: 1150, maxWidth: .infinity, minHeight: 700, maxHeight: .infinity)
            } else {
                SearchScrollView(searchString: $pluginRepository.searchString)
                    .frame(minWidth: 1150, maxWidth: .infinity, minHeight: 700, maxHeight: .infinity)
            }
        }
    }
}

struct CategoryDetailScrollView: View {
    let category: String
    private let size: CGFloat = 150
    private let padding: CGFloat = 5
    @State var pluginModalPresented = false
    @State var index: Int = 0

    var body: some View {
        let plugins = PluginRepository.shared.getPlugins(for: category)
        ScrollView(showsIndicators: true) {
            if #available(OSX 11.0, *) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 300, maximum: 300))],
                    spacing: padding
                ) {
                    ForEach(plugins, id: \.self) { plugin in
                        PluginEntryView(pluginEntry: plugin)
                            .padding()
                            .shadow(radius: 5)
                            .id(plugins.firstIndex(of: plugin))
                            .onTapGesture {
                                pluginModalPresented = true
                                index = plugins.firstIndex(of: plugin) ?? 0
                            }
                            .sheet(isPresented: $pluginModalPresented, content: {
                                PluginEntryModalView(modalPresented: $pluginModalPresented, pluginEntry: plugins[index])
                            })
                    }
                }.padding(padding)
            } else {
                ForEach(plugins, id: \.self) { plugin in
                    PluginEntryView(pluginEntry: plugin)
                        .padding()
                        .shadow(radius: 20)
                        .id(plugins.firstIndex(of: plugin))
                        .onTapGesture {
                            pluginModalPresented = true
                            index = plugins.firstIndex(of: plugin) ?? 0
                        }
                        .sheet(isPresented: $pluginModalPresented, content: {
                            PluginEntryModalView(modalPresented: $pluginModalPresented, pluginEntry: plugins[index])
                        })
                }
            }
        }.frame(minWidth: 100, maxWidth: .infinity)
    }
}

struct SearchScrollView: View {
    @Binding var searchString: String
    private let size: CGFloat = 150
    private let padding: CGFloat = 5
    @State var pluginModalPresented = false
    @State var index: Int = 0

    var body: some View {
        let plugins = PluginRepository.shared.searchPlugins(with: searchString)
        if plugins.isEmpty {
            Text("No plugins found")
                .font(.title)
        } else {
            ScrollView(showsIndicators: true) {
                if #available(OSX 11.0, *) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 300, maximum: 300))],
                        spacing: padding
                    ) {
                        ForEach(plugins, id: \.self) { plugin in
                            PluginEntryView(pluginEntry: plugin)
                                .padding()
                                .shadow(radius: 5)
                                .id(plugins.firstIndex(of: plugin))
                                .onTapGesture {
                                    pluginModalPresented = true
                                    index = plugins.firstIndex(of: plugin) ?? 0
                                }
                                .sheet(isPresented: $pluginModalPresented, content: {
                                    PluginEntryModalView(modalPresented: $pluginModalPresented, pluginEntry: plugins[index])
                                })
                        }
                    }.padding(padding)
                }
            }
        }
    }
}

struct CategoryDetailView: View {
    let category: String
    var body: some View {
        if #available(OSX 11.0, *) {
            ScrollViewReader { proxy in
                CategoryDetailScrollView(category: category)
                    .onChange(of: category) { _ in
                        proxy.scrollTo(0, anchor: .top)
                    }
            }
        } else {
            CategoryDetailScrollView(category: category)
        }
    }
}

struct SplitView: View {
    @Binding var categories: [String]
    @State var selectedCategory: String?
    var body: some View {
        NavigationView {
            List {
                ForEach(categories, id: \.self) { category in
                    NavigationLink(
                        destination: CategoryDetailView(category: category).frame(minWidth: 950),
                        tag: category,
                        selection: $selectedCategory
                    ) {
                        HStack {
                            if #available(OSX 11.0, *) {
                                Image(systemName: PluginRepository.categorySFImage(category))
                                    .frame(width: 20)
                            }
                            Text(Localizable.Categories(rawValue: "CAT_\(category.uppercased())")?.localized ?? category)
                                .font(.headline)
                        }
                    }
                }
            }.listStyle(SidebarListStyle())
                .frame(minWidth: 180)
        }
    }
}
