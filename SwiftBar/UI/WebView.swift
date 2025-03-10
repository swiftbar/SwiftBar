import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    let request: URLRequest
    let zoomFactor: CGFloat

    init(request: URLRequest, zoomFactor: CGFloat = 1.0) {
        self.request = request
        self.zoomFactor = zoomFactor
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context _: Context) {
        webView.load(request)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView

        init(_ parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            if parent.zoomFactor != 1.0 {
                applyZoom(to: webView, scale: parent.zoomFactor)
            }
        }

        private func applyZoom(to webView: WKWebView, scale: CGFloat) {
            let zoomScript = """
            (function() {
                document.body.style.transformOrigin = 'top left';
                document.body.style.transform = 'scale(\(scale))';
                document.body.style.width = '\(100 / scale)%';
                document.documentElement.style.overflow = 'auto';
            })();
            """
            webView.evaluateJavaScript(zoomScript, completionHandler: nil)
        }
    }
}

struct WebPanelView: View {
    let request: URLRequest
    let name: String
    let zoomFactor: CGFloat

    init(request: URLRequest, name: String, zoomFactor: CGFloat = 1.0) {
        self.request = request
        self.name = name
        self.zoomFactor = zoomFactor
    }

    // This property lets us detect if we're in a detached window
    @State private var isDetachedWindow: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if !isDetachedWindow {
                ZStack {
                    if #available(macOS 12.0, *) {
                        Rectangle().fill(.bar)
                    } else {
                        Rectangle().fill(.background)
                    }
                    HStack {
                        Spacer()
                        Text("SwiftBar: \(name)")
                            .font(.headline)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                }
                .frame(height: 28)
                .padding(.top, 4)
            }

            WebView(request: request, zoomFactor: zoomFactor)
        }
    }
}
