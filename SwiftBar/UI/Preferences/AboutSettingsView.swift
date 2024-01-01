import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        VStack {
            HStack {
                Image(nsImage: NSImage(named: "AppIcon")!)
                    .resizable()
                    .renderingMode(.original)
                    .frame(width: 90, height: 90, alignment: .leading)

                VStack(alignment: .leading) {
                    if #available(macOS 11.0, *) {
                        Text("SwiftBar")
                            .font(.title3)
                            .bold()
                    }
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))")
                        .font(.subheadline)
                    Text("Copyright ©2020-2024 Ameba Labs. All rights reserved.")
                        .font(.footnote)
                        .padding(.top, 10)
                }
            }
            Spacer()
            Divider()
            HStack {
                Spacer()
                Button("Visit our Website", action: {
                    NSWorkspace.shared.open(URL(string: "https://swiftbar.app")!)
                })
                Button("Contact Us", action: {
                    NSWorkspace.shared.open(URL(string: "mailto:info@swiftbar.app")!)
                })
            }.padding(.top, 10)
                .padding(.bottom, 10)
        }.padding(.trailing, 20)
            .padding(.bottom, 10)
            .frame(width: 410, height: 160)
    }
}

struct AboutSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AboutSettingsView()
    }
}
