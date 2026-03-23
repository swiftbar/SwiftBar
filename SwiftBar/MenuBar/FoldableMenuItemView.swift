import Cocoa

/// A custom NSView for foldable menu items that prevents menu dismissal on click.
/// When an NSMenuItem has a `view` set, clicking it does NOT close the menu,
/// which enables accordion/fold behavior in the dropdown.
class FoldableMenuItemView: NSView {
    // MARK: - Layout Constants

    private enum Layout {
        static let itemHeight: CGFloat = 22
        static let maxIconSize = NSSize(width: 18, height: 16)
        static let chevronSize = NSSize(width: 10, height: 12)
        static let leadingPadding: CGFloat = 18
        static let iconTrailingSpacing: CGFloat = 4
        static let titleBadgeSpacing: CGFloat = 6
        static let badgeChevronSpacing: CGFloat = 8
        static let chevronLeadingSpacing: CGFloat = 8
        static let trailingPadding: CGFloat = 16
        static let highlightInsetX: CGFloat = 4
        static let highlightInsetY: CGFloat = 1
        static let highlightCornerRadius: CGFloat = 4
        static let chevronPointSize: CGFloat = 10
        static let chevronAnimationDuration: CFTimeInterval = 0.14
    }

    private static let chevronSymbolConfig = NSImage.SymbolConfiguration(pointSize: Layout.chevronPointSize, weight: .semibold)

    // MARK: - Views

    private let titleField = NSTextField(labelWithString: "")
    private let chevronView = NSImageView()
    private let iconView = NSImageView()
    private let badgeView = FoldableMenuItemBadgeView()
    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?
    private var titleLeadingConstraint: NSLayoutConstraint?
    private var normalAttributedTitle = NSAttributedString()
    private var highlightedAttributedTitle = NSAttributedString()
    private var currentImage: NSImage?
    var isFolded: Bool {
        didSet {
            updateChevron()
        }
    }
    var onToggle: (() -> Void)?

    private var isHighlighted = false

    var displayedBadgeText: String? {
        badgeView.badgeText
    }

    var displayedIconSize: NSSize {
        NSSize(width: iconWidthConstraint?.constant ?? 0, height: iconHeightConstraint?.constant ?? 0)
    }

    var isShowingHighlightedAppearance: Bool {
        isHighlighted
    }

    init(attributedTitle: NSAttributedString, highlightedTitle: NSAttributedString, image: NSImage?, badge: String?, isFolded: Bool) {
        self.isFolded = isFolded
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: Layout.itemHeight))
        autoresizingMask = [.width]
        wantsLayer = true
        setAccessibilityRole(.button)
        setAccessibilitySubrole(.toggle)
        setAccessibilityLabel(attributedTitle.string)
        setAccessibilityValue(isFolded ? "collapsed" : "expanded")

        setupViews()
        update(attributedTitle: attributedTitle, highlightedTitle: highlightedTitle, image: image, badge: badge)
        updateChevron()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
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
        chevronView.wantsLayer = true
        addSubview(chevronView)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(iconView)

        badgeView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.setContentHuggingPriority(.required, for: .horizontal)
        badgeView.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(badgeView)

        let iconWidthConstraint = iconView.widthAnchor.constraint(equalToConstant: 0)
        let iconHeightConstraint = iconView.heightAnchor.constraint(equalToConstant: 0)
        let titleLeadingConstraint = titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 0)
        let chevronWidthConstraint = chevronView.widthAnchor.constraint(equalToConstant: Layout.chevronSize.width)
        let chevronHeightConstraint = chevronView.heightAnchor.constraint(equalToConstant: Layout.chevronSize.height)
        self.iconWidthConstraint = iconWidthConstraint
        self.iconHeightConstraint = iconHeightConstraint
        self.titleLeadingConstraint = titleLeadingConstraint

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.leadingPadding),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidthConstraint,
            iconHeightConstraint,

            titleLeadingConstraint,
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -Layout.chevronLeadingSpacing),

            badgeView.leadingAnchor.constraint(greaterThanOrEqualTo: titleField.trailingAnchor, constant: Layout.titleBadgeSpacing),
            badgeView.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -Layout.badgeChevronSpacing),
            badgeView.centerYAnchor.constraint(equalTo: centerYAnchor),

            chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.trailingPadding),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronWidthConstraint,
            chevronHeightConstraint,
        ])
    }

    private func updateChevron(animated: Bool = false) {
        let symbolName = isFolded ? "chevron.right" : "chevron.down"
        if animated, chevronView.image != nil, let layer = chevronView.layer {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = Layout.chevronAnimationDuration
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(transition, forKey: "foldChevronTransition")
        }

        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: isFolded ? "collapsed" : "expanded") {
            chevronView.image = symbol.withSymbolConfiguration(Self.chevronSymbolConfig)
        }

        chevronView.contentTintColor = isHighlighted ? .selectedMenuItemTextColor : .tertiaryLabelColor
        setAccessibilityValue(isFolded ? "collapsed" : "expanded")
    }

    // MARK: - Layout

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Layout.itemHeight)
    }

    // MARK: - Highlighting

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.controlAccentColor.setFill()
            let inset = bounds.insetBy(dx: Layout.highlightInsetX, dy: Layout.highlightInsetY)
            let path = NSBezierPath(roundedRect: inset, xRadius: Layout.highlightCornerRadius, yRadius: Layout.highlightCornerRadius)
            path.fill()
        }
    }

    func setHighlighted(_ highlighted: Bool) {
        guard isHighlighted != highlighted else { return }
        isHighlighted = highlighted
        titleField.attributedStringValue = isHighlighted ? highlightedAttributedTitle : normalAttributedTitle
        badgeView.isHighlighted = highlighted
        updateImageAppearance()
        updateChevron()
        needsDisplay = true
    }

    // MARK: - Click Handling

    override func mouseUp(with event: NSEvent) {
        isFolded.toggle()
        updateChevron(animated: true)
        onToggle?()
    }

    override func keyDown(with event: NSEvent) {
        // Space or Enter toggles the fold
        if event.keyCode == 36 || event.keyCode == 49 {
            isFolded.toggle()
            updateChevron(animated: true)
            onToggle?()
        } else {
            super.keyDown(with: event)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Update

    /// Update the view's title and image without replacing the view.
    func update(attributedTitle: NSAttributedString, highlightedTitle: NSAttributedString, image: NSImage?, badge: String?) {
        normalAttributedTitle = attributedTitle
        highlightedAttributedTitle = highlightedTitle
        titleField.attributedStringValue = isHighlighted ? highlightedAttributedTitle : normalAttributedTitle
        setAccessibilityLabel(attributedTitle.string)
        updateImage(image)
        badgeView.badgeText = badge
        badgeView.isHighlighted = isHighlighted
        needsLayout = true
        needsDisplay = true
    }

    private func updateImage(_ image: NSImage?) {
        currentImage = image
        iconView.image = image
        let iconSize = Self.resolvedIconSize(for: image)
        iconView.isHidden = image == nil
        iconWidthConstraint?.constant = iconSize.width
        iconHeightConstraint?.constant = iconSize.height
        titleLeadingConstraint?.constant = image == nil ? 0 : Layout.iconTrailingSpacing
        updateImageAppearance()
    }

    private func updateImageAppearance() {
        guard currentImage?.isTemplate == true else {
            iconView.contentTintColor = nil
            return
        }

        iconView.contentTintColor = isHighlighted ? .selectedMenuItemTextColor : .labelColor
    }

    private static func resolvedIconSize(for image: NSImage?) -> NSSize {
        guard let image else { return .zero }
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return Layout.maxIconSize
        }

        let widthRatio = Layout.maxIconSize.width / sourceSize.width
        let heightRatio = Layout.maxIconSize.height / sourceSize.height
        let scale = min(widthRatio, heightRatio, 1)
        return NSSize(
            width: round(sourceSize.width * scale),
            height: round(sourceSize.height * scale)
        )
    }
}

private final class FoldableMenuItemBadgeView: NSView {
    private enum Layout {
        static let horizontalPadding: CGFloat = 6
        static let verticalPadding: CGFloat = 2
        static let minimumHeight: CGFloat = 16
        static let cornerRadius: CGFloat = 8
        static let fontSize: CGFloat = 11
    }

    private let label = NSTextField(labelWithString: "")

    var badgeText: String? {
        didSet {
            let trimmedBadge = badgeText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = (trimmedBadge?.isEmpty == false) ? trimmedBadge : nil
            label.stringValue = text ?? ""
            isHidden = text == nil
            invalidateIntrinsicContentSize()
            needsLayout = true
            needsDisplay = true
        }
    }

    var isHighlighted = false {
        didSet {
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: Layout.fontSize, weight: .semibold)
        label.alignment = .center
        addSubview(label)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        guard let badgeText, !badgeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .zero
        }

        let labelSize = label.intrinsicContentSize
        return NSSize(
            width: ceil(labelSize.width) + (Layout.horizontalPadding * 2),
            height: max(ceil(labelSize.height) + (Layout.verticalPadding * 2), Layout.minimumHeight)
        )
    }

    override func layout() {
        super.layout()
        let labelSize = label.intrinsicContentSize
        label.frame = NSRect(
            x: round((bounds.width - labelSize.width) / 2),
            y: round((bounds.height - labelSize.height) / 2),
            width: labelSize.width,
            height: labelSize.height
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !isHidden else { return }

        let backgroundColor = isHighlighted
            ? NSColor.selectedMenuItemTextColor.withAlphaComponent(0.2)
            : NSColor.tertiaryLabelColor.withAlphaComponent(0.18)
        backgroundColor.setFill()
        NSBezierPath(
            roundedRect: bounds,
            xRadius: Layout.cornerRadius,
            yRadius: Layout.cornerRadius
        ).fill()
        label.textColor = isHighlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
    }
}
