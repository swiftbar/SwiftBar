import SwiftUI

struct ImageView: View {
    @ObservedObject var imageLoader: ImageLoader
    var image: NSImage? {
        guard let data = imageLoader.imageData else { return nil }
        return NSImage(data: data)
    }

    let width: CGFloat?
    let height: CGFloat?
    let fallbackView: AnyView

    /// Create an view that shows an image loaded from the URL. The fallbackView will be shown instead when the URL is nil, can't load, or is still loading.
    init(withURL url: URL?, width: CGFloat? = nil, height: CGFloat? = nil, fallbackView: AnyView = AnyView(EmptyView())) {
        self.width = width
        self.height = height
        self.fallbackView = fallbackView
        imageLoader = ImageLoader(url: url)
    }

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: width, height: height)
        } else {
            fallbackView
        }
    }
}
