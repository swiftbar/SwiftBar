import SwiftUI

struct ImageView: View {
    @ObservedObject var imageLoader: ImageLoader
    var image: NSImage {
        if let data = imageLoader.imageData, let image = NSImage(data: data) {
            return image
        }
        return NSImage(named: "AppIcon")!
    }

    var width: CGFloat
    var height: CGFloat

    init(withURL url: URL, width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
        imageLoader = ImageLoader(url: url)
    }

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width, height: height)
    }
}
