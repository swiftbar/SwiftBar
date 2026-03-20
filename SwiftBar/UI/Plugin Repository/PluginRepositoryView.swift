import os
import SwiftUI

private let minWindowWidth: CGFloat = 1024
private let minWindowHeight: CGFloat = 700
private let minSidebarWidth: CGFloat = 180

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
                    .frame(minWidth: minWindowWidth, maxWidth: .infinity, minHeight: minWindowHeight, maxHeight: .infinity)
            } else {
                SearchScrollView(searchString: $pluginRepository.searchString)
                    .frame(minWidth: minWindowWidth, maxWidth: .infinity, minHeight: minWindowHeight, maxHeight: .infinity)
            }
        }
    }
}

struct CategoryDetailScrollView: View {
    let category: String
    private let padding: CGFloat = 5
    @State private var selectedPlugin: RepositoryPlugin.Plugin?

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
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedPlugin = plugin
                            }
                    }
                }.padding(padding)
            } else {
                ForEach(plugins, id: \.self) { plugin in
                    PluginEntryView(pluginEntry: plugin)
                        .padding()
                        .shadow(radius: 20)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedPlugin = plugin
                        }
                }
            }
        }
        .frame(minWidth: 100, maxWidth: .infinity)
        .sheet(item: $selectedPlugin) { plugin in
            PluginEntryModalView(pluginEntry: plugin)
        }
    }
}

struct SearchScrollView: View {
    @Binding var searchString: String
    private let padding: CGFloat = 5
    @State private var selectedPlugin: RepositoryPlugin.Plugin?

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
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedPlugin = plugin
                                }
                        }
                    }.padding(padding)
                }
            }
            .sheet(item: $selectedPlugin) { plugin in
                PluginEntryModalView(pluginEntry: plugin)
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
                        destination: CategoryDetailView(category: category).frame(minWidth: minWindowWidth - minSidebarWidth),
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
                .frame(minWidth: minSidebarWidth)
        }
    }
}
