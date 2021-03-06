import os
import SwiftUI

struct PluginRepositoryView: View {
    @ObservedObject var pluginRepository = PluginRepository.shared
    var body: some View {
        if pluginRepository.repository.isEmpty {
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
                SplitView(categories: pluginRepository.categories)
                    .frame(minWidth: 1150, maxWidth: .infinity, minHeight: 700, maxHeight: .infinity)
            } else {
                SearchlScrollView(searchString: $pluginRepository.searchString)
                    .frame(minWidth: 1150, maxWidth: .infinity, minHeight: 700, maxHeight: .infinity)
            }
        }
    }
}

struct CategoryDetailScrollView: View {
    let category: String
    private let size: CGFloat = 150
    private let padding: CGFloat = 5
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
                    }
                }.padding(padding)
            } else {
                ForEach(plugins, id: \.self) { plugin in
                    PluginEntryView(pluginEntry: plugin)
                        .padding()
                        .shadow(radius: 20)
                        .id(plugins.firstIndex(of: plugin))
                }
            }
        }.frame(minWidth: 100, maxWidth: .infinity)
    }
}

struct SearchlScrollView: View {
    @Binding var searchString: String
    private let size: CGFloat = 150
    private let padding: CGFloat = 5
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
    let categories: [String]
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
                            Text(category)
                                .font(.headline)
                        }
                    }
                }
            }.listStyle(SidebarListStyle())
        }
    }
}
