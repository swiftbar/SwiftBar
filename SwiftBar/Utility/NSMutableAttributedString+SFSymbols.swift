import Cocoa

extension NSMutableAttributedString {
    func symbolize(font: NSFont, colors: [NSColor], sfsize: CGFloat?) {
        guard #available(OSX 11.0, *) else {
            return
        }
        let regex = ":[a-z,0-9,.]*:"
        var resultRanges = [NSRange]()
        let currentString = string
        do {
            let regex = try NSRegularExpression(pattern: regex)
            let results = regex.matches(in: currentString,
                                        range: NSRange(currentString.startIndex..., in: currentString))
            for result in results {
                resultRanges.append(result.range)
            }

        } catch {
            print("invalid regex: \(error.localizedDescription)")
            return
        }

        var index = resultRanges.count - 1
        for range in resultRanges.reversed() {
            let imageName = (currentString as NSString).substring(with: range)
            let clearedImageName = getImageName(from: imageName)

            let imageConfig = NSImage.SymbolConfiguration(pointSize: sfsize ?? font.pointSize, weight: .regular)
            guard let image = NSImage(systemSymbolName: clearedImageName, accessibilityDescription: nil)?.withSymbolConfiguration(imageConfig) else { continue }
            let tintColor: NSColor? = if index >= colors.count {
                colors.last
            } else {
                colors[index]
            }
            let attachment = NSTextAttachment.centeredImage(with: image.tintedImage(color: tintColor), and: font)

            let attrWithAttachment = NSAttributedString(attachment: attachment)

            replaceCharacters(in: range, with: "")
            insert(attrWithAttachment, at: range.lowerBound)
            index -= 1
        }
    }

    private func getImageName(from s: String) -> String {
        guard s.count > 2 else {
            return s
        }
        return String(s.dropFirst().dropLast())
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
