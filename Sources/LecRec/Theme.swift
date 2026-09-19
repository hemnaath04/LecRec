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
        // Taken from the install window. The reference uses bright green as the
        // field behind a dark olive panel, so the app is the panel: green reads
        // through the surfaces and the accent, not as a page of lime.
        static let canvas = NSColor(srgbRed: 0.106, green: 0.145, blue: 0.055, alpha: 1)   // #1B250E -> deep olive
        static let sidebar = NSColor(srgbRed: 0.082, green: 0.114, blue: 0.043, alpha: 1)
        static let hairline = NSColor(srgbRed: 0.180, green: 0.235, blue: 0.098, alpha: 1)
        static let surface = NSColor(srgbRed: 0.161, green: 0.212, blue: 0.086, alpha: 1)
        static let stroke = NSColor(srgbRed: 0.243, green: 0.310, blue: 0.133, alpha: 1)

        static let ink = NSColor(srgbRed: 0.965, green: 0.984, blue: 0.929, alpha: 1)      // warm white
        static let inkSoft = NSColor(srgbRed: 0.839, green: 0.894, blue: 0.769, alpha: 1)
        static let muted = NSColor(srgbRed: 0.667, green: 0.737, blue: 0.573, alpha: 1)
        static let faint = NSColor(srgbRed: 0.545, green: 0.616, blue: 0.451, alpha: 1)
        static let dim = NSColor(srgbRed: 0.427, green: 0.490, blue: 0.345, alpha: 1)

        /// The bright leaf green from the install window, used for the primary action.
        static let leaf = NSColor(srgbRed: 0.612, green: 0.831, blue: 0.188, alpha: 1)     // #9CD430
        static let leafDeep = NSColor(srgbRed: 0.345, green: 0.541, blue: 0.055, alpha: 1)
        /// Red stays reserved for one thing only: a recording that is actually live.
        static let record = NSColor(srgbRed: 1.0, green: 0.271, blue: 0.227, alpha: 1)
        static let warn = NSColor(srgbRed: 0.988, green: 0.792, blue: 0.290, alpha: 1)

        static let courseAccents = [
            NSColor(srgbRed: 0.612, green: 0.831, blue: 0.188, alpha: 1),
            NSColor(srgbRed: 0.427, green: 0.827, blue: 0.671, alpha: 1),
            NSColor(srgbRed: 0.949, green: 0.729, blue: 0.290, alpha: 1),
            NSColor(srgbRed: 0.690, green: 0.686, blue: 0.984, alpha: 1),
            NSColor(srgbRed: 0.965, green: 0.549, blue: 0.494, alpha: 1),
        ]
    }

    /// Inter, bundled with the app. Registered once at launch; if registration
    /// ever fails the system font is used rather than crashing on a nil font.
    enum Typeface {
        static func register() {
            guard let directory = Bundle.main.resourceURL?
                .appendingPathComponent("fonts", isDirectory: true),
                  let files = try? FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: nil)
            else { return }
            for url in files where url.pathExtension.lowercased() == "ttf" {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }

        static func inter(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
            let name: String
            switch weight {
            case .bold, .heavy, .black: name = "Inter-Bold"
            case .semibold:             name = "Inter-SemiBold"
            case .medium:               name = "Inter-Medium"
            default:                    name = "Inter-Regular"
            }
            return NSFont(name: name, size: size)
                ?? .systemFont(ofSize: size, weight: weight)
        }
    }

    enum Font {
        static func of(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
            Typeface.inter(size, weight)
        }

        static var title: NSFont { of(13, .semibold) }
        static var body: NSFont { of(12) }
        static var caption: NSFont { of(11) }
        static var captionStrong: NSFont { of(11, .medium) }
        static var clock: NSFont { .monospacedDigitSystemFont(ofSize: 15, weight: .medium) }
        static var stage: NSFont { of(11.5) }

        static var hero: NSFont { of(56, .semibold) }
        static var heroUnit: NSFont { of(17) }
        static var sectionTitle: NSFont { of(14, .semibold) }
        static var rowTitle: NSFont { of(14, .medium) }
        static var rowMeta: NSFont { of(11.5) }
        static var eyebrow: NSFont { of(9.5, .semibold) }
        static var sidebarItem: NSFont { of(12.5) }
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
