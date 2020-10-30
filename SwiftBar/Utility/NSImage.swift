import Cocoa

extension NSImage {
    static func createImage(from base64: String?, isTemplate: Bool) -> NSImage? {
        guard let base64 = base64, let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {return nil}
        let image = NSImage(data: data)
        image?.isTemplate = isTemplate
        return image
    }

    func resizedCopy( w: CGFloat, h: CGFloat) -> NSImage {
        let destSize = NSMakeSize(w, h)
        let newImage = NSImage(size: destSize)

        newImage.lockFocus()

        self.draw(in: NSRect(origin: .zero, size: destSize),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .copy,
                  fraction: CGFloat(1)
        )

        newImage.unlockFocus()

        guard let data = newImage.tiffRepresentation,
              let result = NSImage(data: data)
        else { return NSImage() }

        return result
    }
}
