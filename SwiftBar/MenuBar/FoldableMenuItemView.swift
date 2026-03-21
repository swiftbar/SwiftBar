import Cocoa

/// A custom NSView for foldable menu items that prevents menu dismissal on click.
/// When an NSMenuItem has a `view` set, clicking it does NOT close the menu,
/// which enables accordion/fold behavior in the dropdown.
class FoldableMenuItemView: NSView {
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
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: 22))
        autoresizingMask = [.width]

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

        let iconWidth: CGFloat = hasImage ? 18 : 0
        let iconTrailingPad: CGFloat = hasImage ? 4 : 0

        let iconWidthConstraint = iconView.widthAnchor.constraint(equalToConstant: iconWidth)
        iconWidthConstraint.priority = .defaultHigh
        let iconHeightConstraint = iconView.heightAnchor.constraint(equalToConstant: 16)
        iconHeightConstraint.priority = .defaultHigh
        let chevronWidthConstraint = chevronView.widthAnchor.constraint(equalToConstant: 10)
        chevronWidthConstraint.priority = .defaultHigh
        let chevronHeightConstraint = chevronView.heightAnchor.constraint(equalToConstant: 12)
        chevronHeightConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidthConstraint,
            iconHeightConstraint,

            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: iconTrailingPad),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -8),

            chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronWidthConstraint,
            chevronHeightConstraint,
        ])
    }

    private func updateChevron() {
        // Use the same chevron SF Symbol as standard submenu indicators
        let symbolName = isFolded ? "chevron.right" : "chevron.down"
        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            chevronView.image = symbol.withSymbolConfiguration(config)
            chevronView.contentTintColor = isHighlighted ? .white : .tertiaryLabelColor
        }
    }

    // MARK: - Layout

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 22)
    }

    // MARK: - Tracking & Highlighting

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
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
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 4, yRadius: 4)
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

    // MARK: - Update

    /// Update the view's title and image without replacing the view.
    func update(attributedTitle: NSAttributedString, image: NSImage?) {
        titleField.attributedStringValue = attributedTitle
        iconView.image = image
        iconView.isHidden = image == nil
    }
}
