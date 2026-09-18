import AppKit

/// One place for spacing, type and colour so the popover reads as a single
/// surface rather than a pile of default controls.
enum Theme {
    static let popoverWidth: CGFloat = 316
    static let gutter: CGFloat = 16
    static let rowGap: CGFloat = 10
    static let tightGap: CGFloat = 5
    static let corner: CGFloat = 10

    enum Font {
        static let title = NSFont.systemFont(ofSize: 13, weight: .semibold)
        static let body = NSFont.systemFont(ofSize: 12, weight: .regular)
        static let caption = NSFont.systemFont(ofSize: 11, weight: .regular)
        static let captionStrong = NSFont.systemFont(ofSize: 11, weight: .medium)
        static let clock = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        static let stage = NSFont.systemFont(ofSize: 11.5, weight: .regular)
    }

    /// Durations kept short. Motion here only marks a state change, it never
    /// decorates, and nothing animates while the user is trying to read.
    enum Motion {
        static let stateChange: TimeInterval = 0.18
        static let pulse: TimeInterval = 1.4
    }

    static func label(_ text: String,
                      font: NSFont = Font.body,
                      color: NSColor = .labelColor,
                      lines: Int = 1) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        field.maximumNumberOfLines = lines
        field.cell?.wraps = lines != 1
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    static func iconButton(symbol: String, tooltip: String,
                           target: AnyObject?, action: Selector) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.image?.isTemplate = true
        button.bezelStyle = .accessoryBar
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tooltip
        button.target = target
        button.action = action
        button.setAccessibilityLabel(tooltip)
        return button
    }

    /// A rounded container used for the transcript-quality and permission rows.
    static func card() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerCurve = .continuous
        view.layer?.cornerRadius = corner
        view.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.09).cgColor
        return view
    }
}
