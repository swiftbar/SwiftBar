import Cocoa

extension NSImage {
    static func createImage(from base64: String?, isTemplate: Bool) -> NSImage? {
        guard let base64 = base64, let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {return nil}
        let image = NSImage(data: data)
        image?.isTemplate = isTemplate
        return image
    }
}
