import Combine
import SwiftUI

struct AboutPluginView: View {
    let md: PluginMetadata
    var body: some View {
        ScrollView(showsIndicators: true) {
            VStack {
                if let name = md.name {
                    VStack {
                        Text(name)
                            .font(.largeTitle)
                            .fixedSize()
                        if let version = md.version {
                            Text(version)
                                .font(.footnote)
                        }
                    }.padding(.bottom)
                }

                if let desc = md.desc {
                    LabelView(label: "", value: desc)
                }
                Divider()
                if let imageURL = md.previewImageURL {
                    ImageView(withURL: imageURL, width: 350, height: 200)
                }

                if let author = md.author {
                    LabelView(label: "Author:", value: author)
                }

                if let github = md.github {
                    LabelView(label: "GitHub:", value: github, url: URL(string: "https://github.com/\(github.replacingOccurrences(of: "@", with: ""))"))
                }

                if let dependencies = md.dependencies.joined(separator: ",") {
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
