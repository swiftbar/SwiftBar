import os
import SwiftUI

struct PluginEntryView: View {
    enum InstallStatus: String {
        case Install
        case Installed
        case Failed
        case Downloading

        var localized: String {
            switch self {
            case .Install:
                return Localizable.PluginRepository.InstallStatusInstall.localized
            case .Installed:
                return Localizable.PluginRepository.InstallStatusInstalled.localized
            case .Failed:
                return Localizable.PluginRepository.InstallStatusFailed.localized
            case .Downloading:
                return Localizable.PluginRepository.InstallStatusDownloading.localized
            }
        }
    }

    @State var installStatus: InstallStatus = .Install
    var installButtonColor: Color? {
        switch installStatus {
        case .Install, .Downloading:
            return .blue
        case .Installed:
            return .green
        case .Failed:
            return .red
        }
    }

    let pluginEntry: RepositoryEntry.PluginEntry
    var githubURL: URL? {
        guard let name = pluginEntry.github else { return nil }
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
            RoundedRectangle(cornerRadius: 15)
                .foregroundColor(Color(NSColor.darkGray))
            VStack(alignment: .leading) {
                VStack(alignment: .leading) {
                    Text(pluginEntry.title)
                        .font(.headline)
                        .foregroundColor(.white)
                    if let url = githubURL {
                        URLTextView(text: "\(Localizable.PluginRepository.AuthorPreposition.localized) \(pluginEntry.author)", url: url)
                            .font(.callout)
                            .foregroundColor(.white)
                    } else {
                        Text(Localizable.PluginRepository.AuthorPreposition.localized + " \(pluginEntry.author)")
                            .font(.callout)
                            .foregroundColor(.white)
                    }
                }
                HStack {
                    if let image = pluginEntry.image {
                        ImageView(withURL: image, width: 80, height: 60)
                    } else {
                        Image(nsImage: NSImage(named: "AppIcon")!)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .opacity(0.6)
                            .frame(width: 80, height: 60)
                    }

                    VStack(alignment: .leading) {
                        if let desc = pluginEntry.desc {
                            Text(desc)
                                .font(.body)
                                .foregroundColor(.white)
                                .lineLimit(3)
                                .padding([.bottom, .top], 1)
                        }
                    }
                }.padding(.bottom, 5)
                Spacer()
                HStack(alignment: .top) {
                    if let url = pluginSourceURL {
                        URLTextView(text: Localizable.PluginRepository.PluginSource.localized, url: url, sfSymbol: "chevron.left.slash.chevron.right")
                            .foregroundColor(.white)
                    }

                    if let url = pluginEntry.aboutURL {
                        URLTextView(text: Localizable.PluginRepository.AboutPlugin.localized, url: url, sfSymbol: "info.circle")
                            .foregroundColor(.white)
                    }
                    Spacer()
                    VStack {
                        Button(action: {
                            os_log("User requested to install plugin from PLugin repository", log: Log.repository)
                            if let url = rawPluginSourceURL {
                                installStatus = .Downloading
                                delegate.pluginManager.importPlugin(from: url) { result in
                                    switch result {
                                    case .success:
                                        installStatus = .Installed
                                    case .failure:
                                        installStatus = .Failed
                                    }
                                }
                            }
                        }) {
                            HStack {
                                if #available(OSX 11.0, *) {
                                    Image(systemName: "icloud.and.arrow.down")
                                    Text(installStatus.localized)
                                } else {
                                    Text(installStatus.localized)
                                }
                            }
                        }.background(installButtonColor)

                        if let version = pluginEntry.version {
                            Text(version)
                                .font(.footnote)
                                .foregroundColor(.white)
                        }
                    }
                }
            }.padding()
        }
    }
}

struct PluginEntryView_Previews: PreviewProvider {
    static var previews: some View {
        PluginEntryView(pluginEntry: RepositoryEntry.PluginEntry(
            title: "iTunes Lite",
            author: "Padraic Renaghan",
            github: "prenagha",
            desc: "Display current track info from iTunes Display current track info from iTunes Display current track info from iTunes",
            image: URL(string: "https://github.com/prenagha/bitbar-itunes/raw/master/bbitunes.png"),
            dependencies: "iTunes Lite applescript",
            aboutURL: URL(string: "https://github.com/prenagha/bitbar-itunes"),
            source: "./Music/bbitunes.10s.sh", version: "v1.2.5"
        )).previewLayout(.fixed(width: 300, height: 200))
    }
}
