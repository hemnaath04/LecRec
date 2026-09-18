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

/// A sidebar entry: optional accent dot, label, and a count on the right.
final class SidebarItem: NSView {
    private let button = NSButton()
    private let countLabel = Theme.label("", font: Theme.Font.caption, color: Theme.Palette.faint)
    private let marker = NSView()
    private var accent: NSColor?

    var onSelect: (() -> Void)?

    init(title: String, count: Int, accent: NSColor?, selected: Bool) {
        self.accent = accent
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = selected ? Theme.Palette.surface.cgColor : NSColor.clear.cgColor

        marker.wantsLayer = true
        marker.layer?.backgroundColor = Theme.Palette.record.cgColor
        marker.isHidden = !selected
        marker.translatesAutoresizingMaskIntoConstraints = false
        addSubview(marker)

        button.title = title
        button.font = selected
            ? NSFont.systemFont(ofSize: 12.5, weight: .medium) : Theme.Font.sidebarItem
        button.contentTintColor = selected ? Theme.Palette.ink : Theme.Palette.inkSoft
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.alignment = .left
        button.target = self
        button.action = #selector(tapped)

        countLabel.stringValue = count > 0 ? "\(count)" : ""
        countLabel.alignment = .right

        var views: [NSView] = []
        if let accent { views.append(Theme.dot(accent)) }
        views += [button, NSView(), countLabel]

        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = accent == nil ? 0 : 9
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            marker.leadingAnchor.constraint(equalTo: leadingAnchor),
            marker.topAnchor.constraint(equalTo: topAnchor),
            marker.bottomAnchor.constraint(equalTo: bottomAnchor),
            marker.widthAnchor.constraint(equalToConstant: 2),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func tapped() { onSelect?() }
}
