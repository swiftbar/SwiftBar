import Cocoa

extension NSImage {
    static func createImage(from base64: String?, isTemplate: Bool) -> NSImage? {
        guard let base64 = base64, let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return nil }
        let image = NSImage(data: data)
        image?.isTemplate = isTemplate
        return image
    }

    func resizedCopy(w: CGFloat, h: CGFloat) -> NSImage {
        let destSize = NSMakeSize(w, h)
        let newImage = NSImage(size: destSize)

        newImage.lockFocus()

        draw(in: NSRect(origin: .zero, size: destSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy,
             fraction: CGFloat(1))

        newImage.unlockFocus()

        guard let data = newImage.tiffRepresentation,
              let result = NSImage(data: data)
        else { return NSImage() }

        return result
    }

    func tintedImage(color: NSColor?) -> NSImage {
        guard let color = color else { return self }
        let newImage = NSImage(size: size)
        newImage.lockFocus()

        let imageRect = NSRect(origin: .zero, size: size)
        draw(in: imageRect, from: imageRect, operation: .sourceOver, fraction: color.alphaComponent)

        color.withAlphaComponent(1).set()
        imageRect.fill(using: .sourceAtop)

        newImage.unlockFocus()
        return newImage
    }
}
