import SwiftUI

struct URLTextView: View {
    var text: String
    var url: URL
    var sfSymbol: String?
    var body: some View {
        if #available(OSX 11.0, *), let sfSymbol {
            Image(systemName: sfSymbol)
                .colorMultiply(.blue)
                .onTapGesture {
                    NSWorkspace.shared.open(url)
                }
        } else {
            Text(text)
                .font(.headline)
                .underline()
                .onTapGesture {
                    NSWorkspace.shared.open(url)
                }
        }
    }
}
