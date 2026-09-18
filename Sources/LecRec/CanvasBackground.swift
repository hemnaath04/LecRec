import AppKit

/// A tint drawn over the window's vibrancy layer.
///
/// The window itself is translucent so the desktop shows through, which is what
/// gives the panel its colour. This view only supplies the wash: a dark tint so
/// text stays legible over any wallpaper, one warm bloom behind the hero, and
/// grain to dither the gradient, which otherwise bands on an 8-bit display.
final class CanvasBackgroundView: NSView {
    override var isOpaque: Bool { false }
    private lazy var grain: NSImage = CanvasBackgroundView.makeGrain()

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Translucent tint rather than a solid fill, so the desktop reads through
        // while text keeps its contrast.
        let top = NSColor(srgbRed: 0.055, green: 0.055, blue: 0.065, alpha: 0.80)
        let bottom = NSColor(srgbRed: 0.078, green: 0.078, blue: 0.094, alpha: 0.88)
        if let gradient = NSGradient(starting: top, ending: bottom) {
            gradient.draw(in: bounds, angle: -90)
        }

        // A single warm bloom behind the hero, anchored top left of the content.
        context.saveGState()
        let origin = CGPoint(x: bounds.minX + bounds.width * 0.22, y: bounds.maxY - 90)
        let radius = max(bounds.width, bounds.height) * 0.55
        let colors = [
            Theme.Palette.record.withAlphaComponent(0.085).cgColor,
            Theme.Palette.record.withAlphaComponent(0.028).cgColor,
            Theme.Palette.record.withAlphaComponent(0.0).cgColor,
        ] as CFArray
        if let space = CGColorSpace(name: CGColorSpace.sRGB),
           let bloom = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.45, 1]) {
            context.drawRadialGradient(bloom, startCenter: origin, startRadius: 0,
                                       endCenter: origin, endRadius: radius,
                                       options: [.drawsAfterEndLocation])
        }
        context.restoreGState()

        // A second, cooler bloom bottom right keeps the field from feeling lopsided.
        context.saveGState()
        let cool = NSColor(srgbRed: 0.369, green: 0.620, blue: 1.0, alpha: 1)
        let coolOrigin = CGPoint(x: bounds.maxX - bounds.width * 0.08, y: bounds.minY + 40)
        let coolColors = [
            cool.withAlphaComponent(0.05).cgColor,
            cool.withAlphaComponent(0.0).cgColor,
        ] as CFArray
        if let space = CGColorSpace(name: CGColorSpace.sRGB),
           let bloom = CGGradient(colorsSpace: space, colors: coolColors, locations: [0, 1]) {
            context.drawRadialGradient(bloom, startCenter: coolOrigin, startRadius: 0,
                                       endCenter: coolOrigin, endRadius: bounds.width * 0.42,
                                       options: [.drawsAfterEndLocation])
        }
        context.restoreGState()

        // Grain, tiled, to dither the gradient.
        NSColor(patternImage: grain).setFill()
        bounds.fill(using: .plusLighter)
    }

    /// A small tile of very low alpha noise, repeated across the window.
    private static func makeGrain(side: Int = 128) -> NSImage {
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * side)
        var generator = SystemRandomNumberGenerator()
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let value = UInt8.random(in: 0...255, using: &generator)
            pixels[index] = value
            pixels[index + 1] = value
            pixels[index + 2] = value
            pixels[index + 3] = 5          // about 2 percent, enough to dither
        }
        let space = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: side, height: side, bitsPerComponent: 8,
                                  bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                                  space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent)
        else { return NSImage(size: NSSize(width: side, height: side)) }
        return NSImage(cgImage: image, size: NSSize(width: side, height: side))
    }
}

/// The sidebar sits slightly above the canvas rather than being a flat panel.
/// The sidebar is part of the same translucent panel, marked only by a slightly
/// deeper tint and a hairline, rather than being an opaque slab beside it.
final class SidebarBackgroundView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.16).setFill()
        bounds.fill()
        NSColor.white.withAlphaComponent(0.07).setFill()
        NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
    }
}
