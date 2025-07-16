import os
import SwiftUI

struct PluginEntryView: View {
    let pluginEntry: RepositoryPlugin.Plugin
    var githubURL: URL? {
        guard let name = pluginEntry.github else { return nil }
        return URL(string: "https://github.com/\(name)")
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15)
                .foregroundColor(Color(NSColor.controlColor))
            VStack(alignment: .leading) {
                VStack(alignment: .leading) {
                    Text(pluginEntry.title)
                        .font(.headline)
                    if let url = githubURL {
                        URLTextView(text: "\(Localizable.PluginRepository.AuthorPreposition.localized) \(pluginEntry.author)", url: url)
                            .font(.subheadline)
                    } else {
                        Text(Localizable.PluginRepository.AuthorPreposition.localized + " \(pluginEntry.author)")
                            .font(.subheadline)
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
                        if !pluginEntry.desc.isEmpty {
                            Text(pluginEntry.desc)
                                .font(.body)
                                .lineLimit(4)
                                .padding([.bottom, .top], 1)
                        } else {
                            Text("No description")
                                .font(.body)
                                .foregroundColor(Color(NSColor.secondaryLabelColor))
                                .padding([.bottom, .top], 1)
                        }
                    }
                }.padding(.bottom, 5)
                Spacer()
                HStack(alignment: .top) {
                    Spacer()
                    if let url = pluginEntry.gitHubURL {
                        URLTextView(text: Localizable.PluginRepository.PluginSource.localized, url: url, sfSymbol: "chevron.left.slash.chevron.right")
                    }

                    if let url = URL(string: pluginEntry.aboutURL) {
                        URLTextView(text: Localizable.PluginRepository.AboutPlugin.localized, url: url, sfSymbol: "info.circle")
                    }
                }
            }.padding()
        }
    }
}

struct PluginEntryModalView: View {
    @Binding var modalPresented: Bool
    enum InstallStatus: String {
        case Install
        case Installed
        case Failed
        case Downloading

        var localized: String {
            switch self {
            case .Install:
                Localizable.PluginRepository.InstallStatusInstall.localized
            case .Installed:
                Localizable.PluginRepository.InstallStatusInstalled.localized
            case .Failed:
                Localizable.PluginRepository.InstallStatusFailed.localized
            case .Downloading:
                Localizable.PluginRepository.InstallStatusDownloading.localized
            }
        }
    }

    @State var installStatus: InstallStatus = .Install
    var installButtonColor: Color? {
        switch installStatus {
        case .Install, .Downloading:
            .blue
        case .Installed:
            .green
        case .Failed:
            .red
        }
    }

    let pluginEntry: RepositoryPlugin.Plugin
    var githubURL: URL? {
        guard let name = pluginEntry.github else { return nil }
        return URL(string: "https://github.com/\(name)")
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15)
                .foregroundColor(Color(NSColor.controlColor))
            VStack(alignment: .leading) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(pluginEntry.title)
                            .font(.headline)
                        if let url = githubURL {
                            URLTextView(text: "\(Localizable.PluginRepository.AuthorPreposition.localized) \(pluginEntry.author)", url: url)
                                .font(.subheadline)
                        } else {
                            Text(Localizable.PluginRepository.AuthorPreposition.localized + " \(pluginEntry.author)")
                                .font(.subheadline)
                        }
                    }
                    Spacer()
                    if #available(OSX 11.0, *) {
                        ZStack {
                            Circle()
                                .foregroundColor(.blue)
                            Image(systemName: "xmark")
                                .foregroundColor(.white)
                        }.frame(width: 20, height: 20)
                            .onTapGesture {
                                modalPresented.toggle()
                            }

                    } else {
                        Button("Close", action: {
                            modalPresented.toggle()
                        })
                    }
                }
                VStack(alignment: .leading) {
                    HStack {
                        Spacer()
                        if let image = pluginEntry.image {
                            ImageView(withURL: image, width: 120, height: 120)
                        } else {
                            Image(nsImage: NSImage(named: "AppIcon")!)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .opacity(0.6)
                                .frame(width: 80, height: 60)
                        }

                        Spacer()
                    }

                    Text("Description")
                        .font(.headline)
                    if !pluginEntry.desc.isEmpty {
                        Text(pluginEntry.desc)
                            .font(.body)
                            .lineLimit(10)
                            .padding([.bottom, .top], 1)
                    } else {
                        Text("No description")
                            .font(.body)
                            .foregroundColor(Color(NSColor.secondaryLabelColor))
                            .padding([.bottom, .top], 1)
                    }
                    Text("Dependencies")
                        .font(.headline)
                    if let dep = pluginEntry.dependencies {
                        Text(dep.joined(separator: ","))
                            .font(.body)
                            .lineLimit(10)
                            .padding([.bottom, .top], 1)
                    } else {
                        Text("No dependencies")
                            .font(.body)
                            .foregroundColor(Color(NSColor.secondaryLabelColor))
                            .padding([.bottom, .top], 1)
                    }
                }.padding(.bottom, 5)
                Spacer()
                HStack(alignment: .top) {
                    if let url = pluginEntry.gitHubURL {
                        URLTextView(text: Localizable.PluginRepository.PluginSource.localized, url: url)
                    }
                    Spacer()
                    VStack {
                        Button(action: {
                            os_log("User requested to install plugin from PLugin repository", log: Log.repository)
                            if let url = pluginEntry.sourceFileURL {
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
                                    switch installStatus {
                                    case .Install, .Downloading:
                                        Image(systemName: "icloud.and.arrow.down")
                                    case .Installed:
                                        Image(systemName: "checkmark.icloud")
                                    case .Failed:
                                        Image(systemName: "xmark.icloud")
                                    }
                                    Text(installStatus.localized)
                                } else {
                                    Text(installStatus.localized)
                                }
                            }
                        }
                    }
                }
            }.padding()
        }
    }
}

// struct PluginEntryView_Previews: PreviewProvider {
//    static var previews: some View {
//        PluginEntryModalView(modalPresented: .constant(true), pluginEntry: RepositoryEntry.PluginEntry(
//            title: "iTunes Lite",
//            author: "Padraic Renaghan",
//            github: "prenagha",
//            desc: "Display current track info from iTunes Display current track info from iTunes Display current track info from iTunes",
//            image: URL(string: "https://github.com/prenagha/bitbar-itunes/raw/master/bbitunes.png"),
//            dependencies: "iTunes Lite applescript",
//            aboutURL: URL(string: "https://github.com/prenagha/bitbar-itunes"),
//            source: "./Music/bbitunes.10s.sh", version: "v1.2.5"
//        )).previewLayout(.fixed(width: 400, height: 600))
//    }
// }
