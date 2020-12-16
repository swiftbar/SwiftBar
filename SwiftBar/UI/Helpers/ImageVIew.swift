import SwiftUI

struct ImageView: View {
    @ObservedObject var imageLoader: ImageLoader
    @State var image = NSImage(named: "AppIcon")!

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
            .onReceive(imageLoader.didChange) { data in
                self.image = NSImage(data: data) ?? NSImage()
            }
    }
}
