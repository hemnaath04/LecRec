import AppKit

/// NSTextView has no placeholder, so an empty multi-line field reads as a dead
/// black box with no hint of what belongs in it.
final class PlaceholderTextView: NSTextView {
    var placeholder: String = "" {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let inset = textContainerInset
        let origin = NSPoint(x: inset.width + (textContainer?.lineFragmentPadding ?? 0),
                             y: inset.height)
        placeholder.draw(at: origin, withAttributes: attributes)
    }
}

/// Draws a red focus ring around a control that just failed validation, so the
/// message and the thing it refers to are visibly connected.
enum Validation {
    static func flag(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerCurve = .continuous
        view.layer?.cornerRadius = 6
        view.layer?.borderWidth = 2
        view.layer?.borderColor = NSColor.systemRed.cgColor

        let pulse = CABasicAnimation(keyPath: "borderColor")
        pulse.fromValue = NSColor.systemRed.cgColor
        pulse.toValue = NSColor.systemRed.withAlphaComponent(0.25).cgColor
        pulse.duration = 0.35
        pulse.autoreverses = true
        pulse.repeatCount = 2
        view.layer?.add(pulse, forKey: "flag")
    }

    static func clear(_ view: NSView) {
        view.layer?.borderWidth = 0
        view.layer?.removeAnimation(forKey: "flag")
    }
}
