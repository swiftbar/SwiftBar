import Cocoa

/// A custom NSView for foldable menu items that prevents menu dismissal on click.
/// When an NSMenuItem has a `view` set, clicking it does NOT close the menu,
/// which enables accordion/fold behavior in the dropdown.
class FoldableMenuItemView: NSView {
    // MARK: - Layout Constants

    private enum Layout {
        static let itemHeight: CGFloat = 22
        static let iconSize = NSSize(width: 18, height: 16)
        static let chevronSize = NSSize(width: 10, height: 12)
        static let leadingPadding: CGFloat = 18
        static let iconTrailingSpacing: CGFloat = 4
        static let chevronLeadingSpacing: CGFloat = 8
        static let trailingPadding: CGFloat = 16
        static let highlightInsetX: CGFloat = 4
        static let highlightInsetY: CGFloat = 1
        static let highlightCornerRadius: CGFloat = 4
        static let chevronPointSize: CGFloat = 10
    }

    private static let chevronSymbolConfig = NSImage.SymbolConfiguration(pointSize: Layout.chevronPointSize, weight: .semibold)

    // MARK: - Views

    private let titleField = NSTextField(labelWithString: "")
    private let chevronView = NSImageView()
    private let iconView = NSImageView()
    var isFolded: Bool {
        didSet {
            updateChevron()
        }
    }
    var onToggle: (() -> Void)?

    private var trackingArea: NSTrackingArea?
    private var isHighlighted = false

    init(attributedTitle: NSAttributedString, image: NSImage?, isFolded: Bool) {
        self.isFolded = isFolded
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: Layout.itemHeight))
        autoresizingMask = [.width]
        setAccessibilityRole(.button)
        setAccessibilitySubrole(.toggle)
        setAccessibilityLabel(attributedTitle.string)
        setAccessibilityValue(isFolded ? "collapsed" : "expanded")

        setupViews(attributedTitle: attributedTitle, image: image)
        updateChevron()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews(attributedTitle: NSAttributedString, image: NSImage?) {
        titleField.attributedStringValue = attributedTitle
        titleField.isEditable = false
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.cell?.wraps = false
        titleField.cell?.isScrollable = false
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleField)

        chevronView.imageScaling = .scaleProportionallyDown
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(chevronView)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        let hasImage = image != nil
        iconView.image = image
        iconView.isHidden = !hasImage

        let iconWidth: CGFloat = hasImage ? Layout.iconSize.width : 0
        let iconTrailingPad: CGFloat = hasImage ? Layout.iconTrailingSpacing : 0

        let iconWidthConstraint = iconView.widthAnchor.constraint(equalToConstant: iconWidth)
        iconWidthConstraint.priority = .defaultHigh
        let iconHeightConstraint = iconView.heightAnchor.constraint(equalToConstant: Layout.iconSize.height)
        iconHeightConstraint.priority = .defaultHigh
        let chevronWidthConstraint = chevronView.widthAnchor.constraint(equalToConstant: Layout.chevronSize.width)
        chevronWidthConstraint.priority = .defaultHigh
        let chevronHeightConstraint = chevronView.heightAnchor.constraint(equalToConstant: Layout.chevronSize.height)
        chevronHeightConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.leadingPadding),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidthConstraint,
            iconHeightConstraint,

            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: iconTrailingPad),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -Layout.chevronLeadingSpacing),

            chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.trailingPadding),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronWidthConstraint,
            chevronHeightConstraint,
        ])
    }

    private func updateChevron() {
        let symbolName = isFolded ? "chevron.right" : "chevron.down"
        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: isFolded ? "collapsed" : "expanded") {
            chevronView.image = symbol.withSymbolConfiguration(Self.chevronSymbolConfig)
            chevronView.contentTintColor = isHighlighted ? .white : .tertiaryLabelColor
        }
        setAccessibilityValue(isFolded ? "collapsed" : "expanded")
    }

    // MARK: - Layout

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Layout.itemHeight)
    }

    // MARK: - Tracking & Highlighting

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        updateChevron()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        updateChevron()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            let inset = bounds.insetBy(dx: Layout.highlightInsetX, dy: Layout.highlightInsetY)
            let path = NSBezierPath(roundedRect: inset, xRadius: Layout.highlightCornerRadius, yRadius: Layout.highlightCornerRadius)
            path.fill()
            titleField.textColor = .white
        } else {
            titleField.textColor = .labelColor
        }
    }

    // MARK: - Click Handling

    override func mouseUp(with event: NSEvent) {
        isFolded.toggle()
        onToggle?()

        // Brief highlight flash
        isHighlighted = true
        updateChevron()
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.isHighlighted = false
            self?.updateChevron()
            self?.needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        // Space or Enter toggles the fold
        if event.keyCode == 36 || event.keyCode == 49 {
            isFolded.toggle()
            onToggle?()
        } else {
            super.keyDown(with: event)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Update

    /// Update the view's title and image without replacing the view.
    func update(attributedTitle: NSAttributedString, image: NSImage?) {
        titleField.attributedStringValue = attributedTitle
        setAccessibilityLabel(attributedTitle.string)
        iconView.image = image
        iconView.isHidden = image == nil
    }
}
