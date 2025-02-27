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

            WebView(request: request)
        }
    }
}
