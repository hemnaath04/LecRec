import AppKit

/// Design tokens taken from the Paper file "LecRec" (artboard Dashboard, 1280x860).
/// Values live here rather than at call sites so the app and the design file can be
/// reconciled by reading one screen of code.
enum Theme {
    static let popoverWidth: CGFloat = 316
    static let gutter: CGFloat = 16
    static let rowGap: CGFloat = 10
    static let tightGap: CGFloat = 5
    static let corner: CGFloat = 10

    enum Palette {
        static let canvas = NSColor(srgbRed: 0.055, green: 0.055, blue: 0.063, alpha: 1)   // #0E0E10
        static let sidebar = NSColor(srgbRed: 0.075, green: 0.075, blue: 0.086, alpha: 1)  // #131316
        static let hairline = NSColor(srgbRed: 0.122, green: 0.122, blue: 0.137, alpha: 1) // #1F1F23
        static let surface = NSColor(srgbRed: 0.110, green: 0.110, blue: 0.129, alpha: 1)  // #1C1C21
        static let stroke = NSColor(srgbRed: 0.165, green: 0.165, blue: 0.192, alpha: 1)   // #2A2A31
        static let ink = NSColor(srgbRed: 0.957, green: 0.957, blue: 0.961, alpha: 1)      // #F4F4F5
        static let inkSoft = NSColor(srgbRed: 0.706, green: 0.706, blue: 0.745, alpha: 1)  // #B4B4BE
        static let muted = NSColor(srgbRed: 0.541, green: 0.541, blue: 0.580, alpha: 1)    // #8A8A94
        static let faint = NSColor(srgbRed: 0.431, green: 0.431, blue: 0.471, alpha: 1)    // #6E6E78
        static let dim = NSColor(srgbRed: 0.353, green: 0.353, blue: 0.388, alpha: 1)      // #5A5A63
        static let record = NSColor(srgbRed: 1.0, green: 0.271, blue: 0.227, alpha: 1)     // #FF453A
        static let warn = NSColor(srgbRed: 0.878, green: 0.627, blue: 0.188, alpha: 1)     // #E0A030

        /// Stable per-course accents, in the order courses were added.
        static let courseAccents = [
            NSColor(srgbRed: 0.369, green: 0.620, blue: 1.0, alpha: 1),                    // #5E9EFF
            NSColor(srgbRed: 0.753, green: 0.549, blue: 1.0, alpha: 1),                    // #C08CFF
            NSColor(srgbRed: 0.353, green: 0.831, blue: 0.702, alpha: 1),
            NSColor(srgbRed: 1.0, green: 0.667, blue: 0.408, alpha: 1),
            NSColor(srgbRed: 0.980, green: 0.514, blue: 0.702, alpha: 1),
        ]
    }

    enum Font {
        static let title = NSFont.systemFont(ofSize: 13, weight: .semibold)
        static let body = NSFont.systemFont(ofSize: 12, weight: .regular)
        static let caption = NSFont.systemFont(ofSize: 11, weight: .regular)
        static let captionStrong = NSFont.systemFont(ofSize: 11, weight: .medium)
        static let clock = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        static let stage = NSFont.systemFont(ofSize: 11.5, weight: .regular)

        // Dashboard scale. The gap between hero and everything else is the point.
        static let hero = NSFont.systemFont(ofSize: 56, weight: .semibold)
        static let heroUnit = NSFont.systemFont(ofSize: 17, weight: .regular)
        static let sectionTitle = NSFont.systemFont(ofSize: 14, weight: .semibold)
        static let rowTitle = NSFont.systemFont(ofSize: 14, weight: .medium)
        static let rowMeta = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        static let eyebrow = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        static let sidebarItem = NSFont.systemFont(ofSize: 12.5, weight: .regular)
    }

    enum Motion {
        static let stateChange: TimeInterval = 0.18
        static let pulse: TimeInterval = 1.4
    }

    static func label(_ text: String,
                      font: NSFont = Font.body,
                      color: NSColor = Palette.ink,
                      lines: Int = 1,
                      tracking: CGFloat? = nil) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        field.maximumNumberOfLines = lines
        field.cell?.wraps = lines != 1
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if let tracking {
            field.attributedStringValue = NSAttributedString(string: text, attributes: [
                .font: font, .foregroundColor: color, .kern: tracking,
            ])
        }
        return field
    }

    /// Small uppercase section label, as used for LIBRARY and COURSES.
    static func eyebrow(_ text: String) -> NSTextField {
        label(text.uppercased(), font: Font.eyebrow, color: Palette.dim, tracking: 1.1)
    }

    static func iconButton(symbol: String, tooltip: String,
                           target: AnyObject?, action: Selector) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.image?.isTemplate = true
        button.bezelStyle = .accessoryBar
        button.isBordered = false
        button.contentTintColor = Palette.muted
        button.toolTip = tooltip
        button.target = target
        button.action = action
        button.setAccessibilityLabel(tooltip)
        return button
    }

    static func card() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerCurve = .continuous
        view.layer?.cornerRadius = corner
        view.layer?.backgroundColor = Palette.surface.cgColor
        return view
    }

    /// The real app icon, for use inside the app. A flat coloured square stood in
    /// for this and looked like a placeholder, because it was one.
    static func appIcon(size: CGFloat) -> NSImageView {
        let view = NSImageView()
        view.image = NSApp.applicationIconImage
            ?? Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
                .flatMap { NSImage(contentsOf: $0) }
        view.imageScaling = .scaleProportionallyUpOrDown
        view.wantsLayer = true
        // The icns already carries the rounded tile, so no extra masking.
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: size).isActive = true
        view.heightAnchor.constraint(equalToConstant: size).isActive = true
        view.setAccessibilityLabel("LecRec")
        return view
    }

    /// A small coloured dot, the only decoration the design uses.
    static func dot(_ color: NSColor, size: CGFloat = 6) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = size / 2
        view.layer?.backgroundColor = color.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: size).isActive = true
        view.heightAnchor.constraint(equalToConstant: size).isActive = true
        return view
    }
}
