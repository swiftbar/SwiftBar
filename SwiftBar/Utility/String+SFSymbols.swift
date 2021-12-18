import Cocoa

extension String {
    func symbolize(font: NSFont, colors: [NSColor], sfsize: CGFloat?) -> NSMutableAttributedString {
        guard #available(OSX 11.0, *), contains(":") else {
            return NSMutableAttributedString(string: self)
        }
        var colors: [NSColor] = colors
        let out = NSMutableAttributedString()
        //TODO: This could mess up the string(refer to #237), ideally replace with regexp match + substring replace or something like that
        components(separatedBy: .whitespaces).forEach { word in
            if out.length != 0 {
                out.append(NSAttributedString(string: " "))
            }
            guard word.hasPrefix(":"), word.hasSuffix(":") else {
                out.append(NSAttributedString(string: word))
                return
            }
            let imageConfig = NSImage.SymbolConfiguration(pointSize: sfsize ?? font.pointSize, weight: .regular)
            if let image = NSImage(systemSymbolName: String(word.dropFirst().dropLast()), accessibilityDescription: nil)?.withSymbolConfiguration(imageConfig) {
                let tintColor = colors.first
                if colors.count > 1 {
                    colors = Array(colors.dropFirst())
                }
                out.append(NSAttributedString(attachment: NSTextAttachment.centeredImage(with: image.tintedImage(color: tintColor), and: font)))
                return
            }
            out.append(NSAttributedString(string: word))
        }
        return out
    }
}

extension NSTextAttachment {
    static func centeredImage(with image: NSImage, and font: NSFont) -> NSTextAttachment {
        let imageAttachment = NSTextAttachment()
        imageAttachment.bounds = CGRect(x: 0, y: (font.capHeight - image.size.height).rounded() / 2, width: image.size.width, height: image.size.height)
        imageAttachment.attachmentCell = ImageAttachmentCell(imageCell: image)
        return imageAttachment
    }
}

class ImageAttachmentCell: NSTextAttachmentCell {
    override func cellBaselineOffset() -> NSPoint {
        var baseline = super.cellBaselineOffset()
        baseline.y = baseline.y - 3 - (image!.size.height - 16) / 2
        return baseline
    }
}
