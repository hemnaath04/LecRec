import AppKit

/// The course selector from the Paper design: a quiet chip, not a system popup.
///
/// A stock NSPopUpButton brings its own grey bezel and blue chevron badge, which
/// is the one piece of default macOS chrome that refused to sit inside a custom
/// dark surface.
final class CourseChip: NSControl {
    private let dot = NSView()
    private let titleLabel = Theme.label("", font: .systemFont(ofSize: 12.5, weight: .regular),
                                         color: Theme.Palette.inkSoft)
    private let chevron = NSImageView()
    private var courses: [Course] = []
    private var selectedSlug: String?
    private var accentProvider: ((String) -> NSColor)?

    /// Fires with the slug the user picked.
    var onSelect: ((String) -> Void)?

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 34) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = 8
        layer?.backgroundColor = Theme.Palette.surface.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = Theme.Palette.stroke.cgColor

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.translatesAutoresizingMaskIntoConstraints = false

        let symbol = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        chevron.image = NSImage(systemSymbolName: "chevron.up.chevron.down",
                                accessibilityDescription: "Change course")?
            .withSymbolConfiguration(symbol)
        chevron.contentTintColor = Theme.Palette.faint
        chevron.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.lineBreakMode = .byTruncatingTail

        let row = NSStackView(views: [dot, titleLabel, NSView(), chevron])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 9
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            chevron.widthAnchor.constraint(equalToConstant: 11),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(courses newCourses: [Course], selected slug: String?,
                   accent: @escaping (String) -> NSColor) {
        courses = newCourses
        selectedSlug = slug
        accentProvider = accent
        isEnabled = !newCourses.isEmpty

        let course = newCourses.first { $0.slug == slug } ?? newCourses.first
        titleLabel.stringValue = course?.name ?? "No courses yet"
        dot.isHidden = course == nil
        if let course { dot.layer?.backgroundColor = accent(course.slug).cgColor }
        alphaValue = isEnabled ? 1 : 0.5
    }

    // MARK: - Menu

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, !courses.isEmpty else { return }
        highlight(true)

        let menu = NSMenu()
        menu.font = .systemFont(ofSize: 12.5)
        for course in courses {
            let item = NSMenuItem(title: course.name, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = course.slug
            item.state = course.slug == selectedSlug ? .on : .off
            if let accent = accentProvider?(course.slug) {
                item.image = Self.swatch(accent)
            }
            menu.addItem(item)
        }
        // Open aligned to the chip rather than at the pointer.
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: bounds.height + 5),
                   in: self)
        highlight(false)
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let slug = sender.representedObject as? String else { return }
        selectedSlug = slug
        configure(courses: courses, selected: slug, accent: accentProvider ?? { _ in Theme.Palette.faint })
        onSelect?(slug)
    }

    private func highlight(_ on: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.Motion.stateChange
            layer?.backgroundColor = (on ? Theme.Palette.stroke : Theme.Palette.surface).cgColor
        }
    }

    private static func swatch(_ color: NSColor) -> NSImage {
        let size = NSSize(width: 8, height: 8)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .popUpButton }
    override func accessibilityLabel() -> String? { "Course: \(titleLabel.stringValue)" }
}
