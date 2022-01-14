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
    var body: some View {
        VStack {
            WebView(request: request)
        }
    }
}
