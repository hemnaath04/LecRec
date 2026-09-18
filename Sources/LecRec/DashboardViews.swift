import AppKit

/// A lecture as one typographic row, matching the Paper design: a fixed course
/// lane, a title, a meta line, a right-aligned coverage column that never wraps,
/// and a quiet Open affordance.
final class LectureRow: NSView {
    private let courseTag = Theme.label("", font: Theme.Font.eyebrow, tracking: 0.8)
    private let titleLabel = Theme.label("", font: Theme.Font.rowTitle, color: Theme.Palette.ink)
    private let metaLabel = Theme.label("", font: Theme.Font.rowMeta, color: Theme.Palette.faint)
    private let statusLabel = Theme.label("", font: Theme.Font.rowMeta, color: Theme.Palette.faint)
    private let openButton = NSButton()
    private let hairline = NSView()
    private var item: LibraryItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = Theme.Palette.surface.cgColor
        hairline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hairline)

        courseTag.alignment = .left
        statusLabel.alignment = .right
        // The lane that wrapped in review. A fixed width keeps every row aligned.
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusLabel.lineBreakMode = .byTruncatingTail

        openButton.title = "Open"
        openButton.font = Theme.Font.caption
        openButton.bezelStyle = .accessoryBarAction
        openButton.isBordered = false
        openButton.contentTintColor = Theme.Palette.muted
        openButton.wantsLayer = true
        openButton.layer?.cornerRadius = 6
        openButton.layer?.cornerCurve = .continuous
        openButton.layer?.borderWidth = 1
        openButton.layer?.borderColor = Theme.Palette.stroke.cgColor
        openButton.target = self
        openButton.action = #selector(open)

        let text = NSStackView(views: [titleLabel, metaLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3

        let row = NSStackView(views: [courseTag, text, NSView(), statusLabel, openButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 18
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            hairline.topAnchor.constraint(equalTo: topAnchor),
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 15),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -15),
            courseTag.widthAnchor.constraint(equalToConstant: 34),
            statusLabel.widthAnchor.constraint(equalToConstant: 112),
            openButton.widthAnchor.constraint(equalToConstant: 56),
            openButton.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(_ newItem: LibraryItem, accent: NSColor, showHairline: Bool) {
        item = newItem
        hairline.isHidden = !showHairline

        courseTag.attributedStringValue = NSAttributedString(
            string: newItem.course.uppercased(),
            attributes: [.font: Theme.Font.eyebrow, .foregroundColor: accent, .kern: 0.8])
        titleLabel.stringValue = newItem.title

        var parts = [Self.dateText(newItem.date)]
        if newItem.duration > 0 { parts.append(Library.clock(newItem.duration)) }
        parts.append(newItem.hasNote
            ? "\(Library.formatted(newItem.wordCount)) words"
            : "no note yet")
        metaLabel.stringValue = parts.joined(separator: "  ·  ")

        // Only two things are worth an alarming colour: an unprocessed recording,
        // and a transcript that did not cover the lecture.
        let lowCoverage = (newItem.coverage ?? 1) < 0.95
        metaLabel.textColor = (!newItem.hasNote || lowCoverage) ? Theme.Palette.warn : Theme.Palette.faint

        if let coverage = newItem.coverage {
            let pct = Int((coverage * 100).rounded())
            statusLabel.stringValue = lowCoverage ? "only \(pct)% covered" : "\(pct)% covered"
            statusLabel.textColor = lowCoverage ? Theme.Palette.warn : Theme.Palette.faint
        } else if !newItem.hasNote {
            statusLabel.stringValue = "not processed"
            statusLabel.textColor = Theme.Palette.warn
        } else {
            statusLabel.stringValue = ""
        }

        openButton.isHidden = newItem.noteURL == nil && newItem.notionURL == nil
    }

    @objc private func open() {
        if let link = item?.notionURL, let url = URL(string: link) {
            NSWorkspace.shared.open(url)
            return
        }
        if let url = item?.noteURL { NSWorkspace.shared.open(url) }
    }

    private static func dateText(_ date: Date) -> String {
        guard date > .distantPast else { return "undated" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }
}

/// A sidebar entry in the reference language: a title with a quiet subtitle,
/// and when selected it inverts to a white pill with dark text and reveals its
/// action. The inversion is what makes the current selection unmissable without
/// adding another colour to the palette.
final class SidebarItem: NSView {
    private let titleLabel: NSTextField
    private let subtitleLabel: NSTextField
    private let actionLabel: NSTextField
    private let dotView: NSView?
    private let pill = NSView()
    private var selected: Bool
    private var trackingArea: NSTrackingArea?

    var onSelect: (() -> Void)?
    var onAction: (() -> Void)?

    init(title: String, subtitle: String, accent: NSColor?, selected isSelected: Bool,
         actionTitle: String? = nil) {
        selected = isSelected
        titleLabel = Theme.label(title, font: .systemFont(ofSize: 13.5, weight: .semibold))
        subtitleLabel = Theme.label(subtitle, font: Theme.Font.rowMeta)
        actionLabel = Theme.label(actionTitle ?? "", font: .systemFont(ofSize: 10, weight: .semibold),
                                  tracking: 0.9)
        dotView = accent.map { Theme.dot($0, size: 7) }
        super.init(frame: .zero)

        pill.wantsLayer = true
        pill.layer?.cornerCurve = .continuous
        pill.layer?.cornerRadius = 11
        pill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pill)

        let text = NSStackView(views: subtitle.isEmpty ? [titleLabel] : [titleLabel, subtitleLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1

        var views: [NSView] = []
        if let dotView { views.append(dotView) }
        views += [text, NSView(), actionLabel]

        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = dotView == nil ? 0 : 10
        row.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(row)

        NSLayoutConstraint.activate([
            pill.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            pill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            pill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: pill.topAnchor, constant: 9),
            row.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -9),
            row.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 13),
            row.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -13),
        ])
        applyAppearance(hovering: false)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func applyAppearance(hovering: Bool) {
        if selected {
            pill.layer?.backgroundColor = NSColor.white.cgColor
            titleLabel.textColor = NSColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 1)
            subtitleLabel.textColor = NSColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 0.55)
            actionLabel.textColor = NSColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 0.5)
            actionLabel.isHidden = actionLabel.stringValue.isEmpty
        } else {
            pill.layer?.backgroundColor = hovering
                ? NSColor.white.withAlphaComponent(0.07).cgColor
                : NSColor.clear.cgColor
            titleLabel.textColor = Theme.Palette.ink
            subtitleLabel.textColor = Theme.Palette.faint
            actionLabel.isHidden = true
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                  owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { applyAppearance(hovering: true) }
    override func mouseExited(with event: NSEvent) { applyAppearance(hovering: false) }

    override func mouseDown(with event: NSEvent) {
        // The revealed action sits on the right of a selected pill.
        if selected, !actionLabel.isHidden {
            let point = convert(event.locationInWindow, from: nil)
            if actionLabel.frame.insetBy(dx: -8, dy: -8).contains(convert(point, to: pill)) {
                onAction?()
                return
            }
        }
        onSelect?()
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { titleLabel.stringValue }
}
