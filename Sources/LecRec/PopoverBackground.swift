import AppKit

/// The menu bar popover uses the same surface language as the window rather than
/// the stock popover material, so the two never look like different apps.
final class PopoverBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let top = NSColor(srgbRed: 0.086, green: 0.086, blue: 0.098, alpha: 1)
        let bottom = NSColor(srgbRed: 0.055, green: 0.055, blue: 0.067, alpha: 1)
        if let gradient = NSGradient(starting: top, ending: bottom) {
            gradient.draw(in: bounds, angle: -90)
        }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let origin = CGPoint(x: bounds.midX, y: bounds.maxY)
        let colors = [
            Theme.Palette.record.withAlphaComponent(0.10).cgColor,
            Theme.Palette.record.withAlphaComponent(0.0).cgColor,
        ] as CFArray
        if let space = CGColorSpace(name: CGColorSpace.sRGB),
           let bloom = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            context.drawRadialGradient(bloom, startCenter: origin, startRadius: 0,
                                       endCenter: origin, endRadius: bounds.width * 0.9,
                                       options: [.drawsAfterEndLocation])
        }
    }
}
