import SwiftUI
import os

struct PluginRepositoryView: View {
    @ObservedObject var pluginRepository = PluginRepository.shared
    var body: some View {
        if pluginRepository.repository.isEmpty {
            VStack {
                Text("Refreshing repository data...")
                    .font(.largeTitle)
                    .padding()

                Image(nsImage: NSImage(named: "AppIcon")!)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(0.6)

            }.frame(width: 400, height: 200)

        } else {
            SplitView(categories: pluginRepository.categories)
                .frame(minWidth: 900, maxWidth: .infinity, minHeight: 700, maxHeight: .infinity)
        }
    }
}

struct PluginEntryView: View {
    enum InstallStatus: String {
        case Install
        case Installed
        case Failed
        case Downloading
    }
    @State var installStatus: InstallStatus = .Install
    var installButtonColor: Color? {
        switch installStatus {
            case .Install, .Downloading:
                return nil
            case .Installed:
                return .green
            case .Failed:
                return .red
        }
    }
    let pluginEntry: RepositoryEntry.PluginEntry
    var githubURL: URL? {
        guard let name = pluginEntry.github else {return nil}
        return URL(string: "https://github.com/\(name)")
    }
    var pluginSourceURL: URL? {
        URL(string: "https://github.com/matryer/bitbar-plugins/blob/master/\(pluginEntry.source.dropFirst(2))")
    }

    var rawPluginSourceURL: URL? {
        URL(string: "https://raw.githubusercontent.com/matryer/bitbar-plugins/master/\(pluginEntry.source.dropFirst(2))")
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .foregroundColor(Color(NSColor.darkGray))
            HStack {
                if let image = pluginEntry.image {
                    ImageView(withURL: image, width: 350, height: 200)
                } else {
                    Image(nsImage: NSImage(named: "AppIcon")!)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .opacity(0.6)
                        .frame(width: 350, height: 200)
                }

                VStack(alignment: .leading) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(pluginEntry.title)
                                .font(.title)
                                .foregroundColor(.white)
                            Text("by \(pluginEntry.author)")
                                .font(.callout)
                                .foregroundColor(.white)
                        }
                        Spacer()
                        VStack {
                            Button(installStatus.rawValue) {
                                os_log("User requested to install plugin from PLugin repository", log: Log.repository)
                                if let url = rawPluginSourceURL {
                                    installStatus = .Downloading
                                    delegate.pluginManager.importPlugin(from: url) { result in
                                        switch result {
                                            case .success( _):
                                                installStatus = .Installed
                                            case .failure( _):
                                                installStatus = .Failed
                                        }
                                    }
                                }
                            }.foregroundColor(installButtonColor)

                            if let version = pluginEntry.version {
                                Text(version)
                                    .font(.footnote)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    if let desc = pluginEntry.desc {
                        Text(desc)
                            .font(.body)
                            .foregroundColor(.white)
                            .padding([.bottom, .top], 1)
                    }

                    if let dependencies = pluginEntry.dependencies {
                        Text("Dependencies: \(dependencies)")
                            .font(.body)
                            .foregroundColor(.white)
                            .padding(.bottom, 1)
                    }

                    HStack {
                        if let githubName = pluginEntry.github, let url = githubURL {
                            URLTextView(text: "@\(githubName)", url: url)
                                .foregroundColor(.white)
                        }

                        if let url = pluginSourceURL {
                            URLTextView(text: "Source", url: url)
                                .foregroundColor(.white)
                        }

                        if let url = pluginEntry.aboutURL {
                            URLTextView(text: "About", url: url)
                                .foregroundColor(.white)
                        }
                    }
                }
            }.padding()
        }
    }
}

struct CategoryDetailScrollView: View {
    let category: String
    var body: some View {
        let plugins = PluginRepository.shared.getPlugins(for: category)
        ScrollView(showsIndicators: true) {
            ForEach(plugins, id: \.self) { plugin in
                PluginEntryView(pluginEntry: plugin)
                    .padding()
                    .shadow(radius: 20)
                    .id(plugins.firstIndex(of: plugin))
            }
        }.frame(minWidth: 100, maxWidth: .infinity)
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

struct Category {
    let category: String
    var contentView: CategoryDetailView {
        return CategoryDetailView(category: category)
    }
}

struct SplitView: View {
    let categories: [String]
    @State var selectedCategory: Category = Category(category: "AWS")
    var body: some View {
        HSplitView {
            VStack(alignment: .leading) {
                Text("Category")
                    .font(.headline)
                    .padding([.top, .leading])
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading) {
                        ForEach(categories, id: \.self) { category in
                            Text(category)
                                .padding([.leading, .trailing])
                                .padding(.bottom, 2)
                                .foregroundColor(category == selectedCategory.category ?
                                                    .orange:Color(NSColor.labelColor)
                                )
                                .onTapGesture {
                                    selectedCategory = Category(category: category)
                                }
                        }
                    }
                }
                .padding(.top)
                .frame(minWidth: 128)
            }
            selectedCategory.contentView
                .frame(minWidth: 100, maxWidth: .infinity)
        }
    }
}

struct PluginRepositoryView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PluginRepositoryView()
        }

//        CategoryDetailView(plugins: [RepositoryEntry.PluginEntry(
//                                        title: "iTunes Lite",
//                                        author: "Padraic Renaghan",
//                                        github: "prenagha",
//                                        desc: "Display current track info from iTunes Display current track info from iTunes Display current track info from iTunes",
//                                        image: URL(string: "https://github.com/prenagha/bitbar-itunes/raw/master/bbitunes.png"),
//                                        dependencies: "iTunes Lite applescript",
//                                        aboutURL: URL(string: "https://github.com/prenagha/bitbar-itunes"),
//                                        source: "./Music/bbitunes.10s.sh", version: "v1.2.5")])
//            .previewLayout(.fixed(width: 700, height: 400))
    }
}
