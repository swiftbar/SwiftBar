import Cocoa

extension String {
    func symbolize(font: NSFont) -> NSMutableAttributedString {
        if #available(OSX 11.0, *) {
            let out = NSMutableAttributedString()
            self.components(separatedBy: .whitespaces).forEach { word in
                out.append(NSAttributedString(string: " "))
                guard word.hasPrefix(":"), word.hasSuffix(":") else {
                    out.append(NSAttributedString(string: word))
                    return
                }
                if let image = NSImage(systemSymbolName: String(word.dropFirst().dropLast()), accessibilityDescription: nil) {
                    image.isTemplate = true
                    out.append(NSAttributedString(attachment: NSTextAttachment.centeredImage(with: image, and: font)))
                    return
                }
                out.append(NSAttributedString(string: word))
            }
            return out
        }
        return NSMutableAttributedString(string: self)
    }
}

extension NSTextAttachment {
    static func centeredImage(with image: NSImage, and
                                            font: NSFont) -> NSTextAttachment {
        let imageAttachment = NSTextAttachment()
        imageAttachment.bounds = CGRect(x: 0, y: (font.capHeight - image.size.height).rounded() / 2, width: image.size.width, height: image.size.height)
        imageAttachment.image = image
        return imageAttachment
    }
}
