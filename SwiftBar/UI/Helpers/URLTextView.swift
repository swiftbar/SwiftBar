import SwiftUI

struct URLTextView: View {
    var text: String
    var url: URL
    var body: some View {
        Text(text)
            .font(.headline)
            .underline()
            .onTapGesture {
                NSWorkspace.shared.open(url)
            }
    }
}
