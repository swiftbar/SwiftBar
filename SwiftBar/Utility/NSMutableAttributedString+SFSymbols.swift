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

    static func centeredMenuImage(with image: NSImage, and font: NSFont) -> NSTextAttachment {
        let imageAttachment = NSTextAttachment()
        imageAttachment.bounds = CGRect(x: 0, y: (font.capHeight - image.size.height).rounded() / 2, width: image.size.width, height: image.size.height)
        imageAttachment.attachmentCell = MenuImageAttachmentCell(imageCell: image)
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

class MenuImageAttachmentCell: ImageAttachmentCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        guard let image else { return }

        let drawImage = {
            let color: NSColor = self.isHighlighted ? .selectedMenuItemTextColor : .labelColor
            image.tintedImage(color: color).draw(in: cellFrame)
        }
        if let appearance = controlView?.effectiveAppearance {
            appearance.performAsCurrentDrawingAppearance(drawImage)
        } else {
            drawImage()
        }
    }
}

/// Keeps an inline image from enlarging only the first line of a multiline title.
final class MultilineMenuImageCell: MenuImageAttachmentCell {
    let textHeight: CGFloat
    private let firstBaseline: CGFloat
    private let lastAscent: CGFloat
    private let lastDescent: CGFloat
    private let padding: CGFloat

    init(image: NSImage, title: NSAttributedString) {
        let storage = NSTextStorage(attributedString: title)
        if title.string.hasPrefix("\n") {
            // The real first paragraph contains the image and its spacing,
            // which use the menu font without the label's baseline offset.
            storage.insert(NSAttributedString(string: "\u{200B}", attributes: [
                .font: title.attribute(.font, at: 0, effectiveRange: nil) ?? NSFont.menuFont(ofSize: 0),
            ]), at: 0)
        }
        if title.string.hasSuffix("\n") {
            // The bottom padding occupies the final empty paragraph. Measure
            // that paragraph as a real line, rather than an extra line fragment.
            storage.append(NSAttributedString(string: "\u{200B}", attributes: title.attributes(at: title.length - 1, effectiveRange: nil)))
        }
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: max(1, ceil(title.size().width)), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        textHeight = layout.usedRect(for: container).height
        // Glyph locations include the character's baseline displacement. The
        // attachment needs the common line baseline, since it has no valign.
        func lineBaseline(forGlyphAt glyph: Int) -> CGFloat {
            let character = layout.characterIndexForGlyph(at: glyph)
            let offset = (storage.attribute(.baselineOffset, at: character, effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0
            return layout.location(forGlyphAt: glyph).y + offset
        }
        firstBaseline = lineBaseline(forGlyphAt: 0)
        let lastGlyph = layout.numberOfGlyphs - 1
        let lastLine = layout.lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil)
        lastAscent = lineBaseline(forGlyphAt: lastGlyph)
        lastDescent = lastLine.height - lastAscent
        // Keep a half-point margin at either edge for the pixel-aligned draw.
        padding = max(0, (image.size.height - textHeight + 1) / 2)
        super.init(imageCell: image)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func cellSize() -> NSSize {
        // Reserve any extra ascent above the first line. A matching descent
        // after the last line keeps all text baselines at their normal spacing.
        NSSize(width: image?.size.width ?? 0, height: firstBaseline + padding)
    }

    override func cellBaselineOffset() -> NSPoint { .zero }

    func bottomPaddingAttachment() -> NSTextAttachment {
        // Even with no extra padding, materialize the final empty paragraph so
        // NSString measurement and drawing use the same line metrics.
        let attachment = NSTextAttachment()
        attachment.attachmentCell = MenuImageBottomPaddingCell(ascent: lastAscent, descent: lastDescent + padding)
        return attachment
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        guard let image else { return }
        let flipped = controlView?.isFlipped ?? NSGraphicsContext.current?.isFlipped ?? false
        let offset = (firstBaseline - textHeight / 2) * (flipped ? -1 : 1)
        let baseline = flipped ? cellFrame.maxY : cellFrame.minY
        let imageRect = NSRect(x: cellFrame.minX, y: (baseline + offset - image.size.height / 2).rounded(), width: image.size.width, height: image.size.height)
        super.draw(withFrame: imageRect, in: controlView)
    }
}

private final class MenuImageBottomPaddingCell: NSTextAttachmentCell {
    private let ascent: CGFloat
    private let descent: CGFloat

    init(ascent: CGFloat, descent: CGFloat) {
        self.ascent = ascent
        self.descent = descent
        super.init(textCell: "")
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func cellSize() -> NSSize { NSSize(width: 0, height: ascent + descent) }
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -descent) }
}
