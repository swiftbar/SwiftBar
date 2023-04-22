import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    let request: URLRequest
    func makeNSView(context _: Context) -> WKWebView {
        WKWebView()
    }

    func updateNSView(_ uiView: WKWebView, context _: Context) {
        uiView.load(request)
    }
}

struct WebPanelView: View {
    let request: URLRequest
    let name: String
    var body: some View {
        VStack {
            ZStack {
                if #available(macOS 12.0, *) {
                    Rectangle().fill(.bar)
                } else if #available(macOS 12.0, *) {
                    Rectangle().fill(.background)
                } else {
                    Rectangle().fill(.gray)
                }
                Text("SwiftBar: \(name)")
                    .font(.headline)
            }.frame(height: 20)
            WebView(request: request)
        }
    }
}
