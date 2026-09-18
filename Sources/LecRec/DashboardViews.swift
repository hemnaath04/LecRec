import AppKit

/// A single number with a label. Big figure, quiet caption, one accent.
final class StatTile: NSView {
    private let value = Theme.label("", font: .systemFont(ofSize: 27, weight: .semibold))
    private let caption = Theme.label("", font: Theme.Font.caption, color: .secondaryLabelColor)
    private let glyph = NSImageView()

    init(symbol: String, tint: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.10).cgColor

        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        glyph.contentTintColor = tint
        glyph.translatesAutoresizingMaskIntoConstraints = false
        value.maximumNumberOfLines = 1

        let stack = NSStackView(views: [glyph, value, caption])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.setCustomSpacing(8, after: glyph)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 15),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -15),
            glyph.widthAnchor.constraint(equalToConstant: 16),
            glyph.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func set(value newValue: String, caption newCaption: String) {
        value.stringValue = newValue
        caption.stringValue = newCaption
    }
}

/// One lecture in the recent list. Shows what is actually known and, more
/// usefully, what is missing.
final class LectureRow: NSView {
    private let titleLabel = Theme.label("", font: .systemFont(ofSize: 13, weight: .medium))
    private let metaLabel = Theme.label("", font: Theme.Font.caption, color: .secondaryLabelColor)
    private let courseChip = Theme.label("", font: .systemFont(ofSize: 10, weight: .semibold))
    private let chipBackground = NSView()
    private let openNote = NSButton()
    private let openNotion = NSButton()
    private var item: LibraryItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = 10

        chipBackground.wantsLayer = true
        chipBackground.layer?.cornerRadius = 5
        chipBackground.layer?.cornerCurve = .continuous
        chipBackground.translatesAutoresizingMaskIntoConstraints = false
        courseChip.translatesAutoresizingMaskIntoConstraints = false
        chipBackground.addSubview(courseChip)

        for button in [openNote, openNotion] {
            button.bezelStyle = .accessoryBarAction
            button.controlSize = .small
            button.target = self
        }
        openNote.title = "Note"
        openNote.action = #selector(revealNote)
        openNotion.title = "Notion"
        openNotion.action = #selector(openInNotion)

        let text = NSStackView(views: [titleLabel, metaLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2

        let row = NSStackView(views: [chipBackground, text, NSView(), openNote, openNotion])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 11
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            courseChip.topAnchor.constraint(equalTo: chipBackground.topAnchor, constant: 3),
            courseChip.bottomAnchor.constraint(equalTo: chipBackground.bottomAnchor, constant: -3),
            courseChip.leadingAnchor.constraint(equalTo: chipBackground.leadingAnchor, constant: 7),
            courseChip.trailingAnchor.constraint(equalTo: chipBackground.trailingAnchor, constant: -7),
            chipBackground.widthAnchor.constraint(greaterThanOrEqualToConstant: 38),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(_ newItem: LibraryItem) {
        item = newItem
        titleLabel.stringValue = newItem.title

        var parts: [String] = [Self.dateText(newItem.date)]
        if newItem.duration > 0 { parts.append(Library.clock(newItem.duration)) }
        if newItem.wordCount > 0 { parts.append("\(Library.formatted(newItem.wordCount)) words") }
        if let coverage = newItem.coverage {
            let pct = Int((coverage * 100).rounded())
            parts.append(pct >= 95 ? "\(pct)% covered" : "only \(pct)% covered")
        }
        if !newItem.hasNote { parts.append("no note yet") }
        metaLabel.stringValue = parts.joined(separator: "  ·  ")
        metaLabel.textColor = (newItem.coverage ?? 1) < 0.95 || !newItem.hasNote
            ? .systemOrange : .secondaryLabelColor

        courseChip.stringValue = newItem.course.uppercased()
        let tint = Self.tint(for: newItem.course)
        courseChip.textColor = tint
        chipBackground.layer?.backgroundColor = tint.withAlphaComponent(0.16).cgColor

        openNote.isHidden = newItem.noteURL == nil
        openNotion.isHidden = newItem.notionURL == nil
    }

    @objc private func revealNote() {
        guard let url = item?.noteURL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openInNotion() {
        guard let link = item?.notionURL, let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }

    static func tint(for course: String) -> NSColor {
        // Stable per course, so a course keeps its colour between launches.
        let palette: [NSColor] = [.systemBlue, .systemPurple, .systemTeal, .systemIndigo,
                                  .systemPink, .systemGreen]
        return palette[abs(course.hashValue) % palette.count]
    }

    private static func dateText(_ date: Date) -> String {
        guard date > .distantPast else { return "undated" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }
}
