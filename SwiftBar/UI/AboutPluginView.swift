import Combine
import SwiftUI

struct AboutPluginView: View {
    let md: PluginMetadata
    var body: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 8) {
                if !md.name.isEmpty {
                    VStack {
                        Text(md.name)
                            .font(.largeTitle)
                            .fixedSize()
                        if !md.version.isEmpty {
                            Text(md.version)
                                .font(.footnote)
                        }
                    }.padding(.bottom)
                }

                if !md.desc.isEmpty {
                    LabelView(label: "Description:", value: md.desc)
                }

                Divider()

                if let previewImageURL = md.previewImageURL {
                    ImageView(withURL: previewImageURL, width: 350, height: 200)
                        .padding(.bottom, 8)
                }

                if !md.author.isEmpty {
                    LabelView(label: "Author:", value: md.author)
                }

                if !md.github.isEmpty {
                    LabelView(label: "GitHub:", value: md.github, url: URL(string: "https://github.com/\(md.github.replacingOccurrences(of: "@", with: ""))"))
                }

                if !md.dependencies.isEmpty {
                    let dependencies = md.dependencies.filter { !$0.isEmpty }.joined(separator: ", ")
                    if !dependencies.isEmpty {
                        LabelView(label: "Dependencies:", value: dependencies)
                    }
                }

                if let about = md.aboutURL {
                    LabelView(label: "About:", value: about.absoluteString, url: about)
                }

                // Display plugin variables if they exist
                if !md.environment.isEmpty {
                    Divider().padding(.vertical, 4)
                    Text("Variables:").font(.headline).padding(.top, 4)

                    ForEach(Array(md.environment.keys.sorted()), id: \.self) { key in
                        if let value = md.environment[key] {
                            LabelView(label: key + ":", value: value)
                        }
                    }
                }

                // Display additional plugin settings
                if md.type != .Executable || md.runInBash == false || md.refreshOnOpen || md.persistentWebView {
                    Divider().padding(.vertical, 4)
                    Text("Settings:").font(.headline).padding(.top, 4)

                    if md.type != .Executable {
                        LabelView(label: "Type:", value: md.type.rawValue)
                    }

                    if !md.schedule.isEmpty {
                        LabelView(label: "Schedule:", value: md.schedule)
                    }

                    if md.runInBash == false {
                        LabelView(label: "Run in Bash:", value: "false")
                    }

                    if md.refreshOnOpen {
                        LabelView(label: "Refresh on Open:", value: "true")
                    }

                    if md.persistentWebView {
                        LabelView(label: "Persistent WebView:", value: "true")
                    }
                }

                if !md.dropTypes.isEmpty {
                    let dropTypes = md.dropTypes.filter { !$0.isEmpty }.joined(separator: ", ")
                    if !dropTypes.isEmpty {
                        Divider().padding(.vertical, 4)
                        LabelView(label: "Drop Types:", value: dropTypes)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct LabelView: View {
    let label: String
    let value: String
    var url: URL?
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            if let url {
                Text(value)
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .onTapGesture {
                        NSWorkspace.shared.open(url)
                    }
            } else {
                Text(value)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}

struct AboutPluginView_Previews: PreviewProvider {
    static var previews: some View {
        AboutPluginView(md:
            PluginMetadata(name: "Super Plugin",
                           version: "1.0",
                           author: "SwiftBar",
                           github: "@melonamin",
                           desc: "This plugin is so cool you can't imagine your life before it!",
                           previewImageURL: URL(string: "https://upload.wikimedia.org/wikipedia/commons/6/6e/Golde33443.jpg"),
                           dependencies: ["ruby", "aws"],
                           aboutURL: URL(string: "https://github.com/swiftbar")))
    }
}
