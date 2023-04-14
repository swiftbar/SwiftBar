import Combine
import SwiftUI

struct AboutPluginView: View {
    let md: PluginMetadata
    var body: some View {
        ScrollView(showsIndicators: true) {
            VStack {
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

                if md.desc.isEmpty {
                    LabelView(label: "", value: md.desc)
                }
                Divider()
                if let previewImageURL = md.previewImageURL {
                    ImageView(withURL: previewImageURL, width: 350, height: 200)
                }

                if md.author.isEmpty {
                    LabelView(label: "Author:", value: md.author)
                }

                if md.github.isEmpty {
                    LabelView(label: "GitHub:", value: md.github, url: URL(string: "https://github.com/\(md.github.replacingOccurrences(of: "@", with: ""))"))
                }

                if case let dependencies = md.dependencies.joined(separator: ",") {
                    LabelView(label: "Dependencies:", value: dependencies)
                }

                if let about = md.aboutURL {
                    LabelView(label: "About:", value: about.absoluteString, url: about)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if let url = url {
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
