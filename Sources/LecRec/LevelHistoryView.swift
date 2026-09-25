import AppKit

/// A scrolling record of input level over the last few minutes.
///
/// A single bouncing meter only proves the microphone is alive right now. This
/// shows whether it has been alive, which is the question that actually matters
/// during a lecture: a flat stretch behind the playhead is a stretch of audio
/// that will transcribe to nothing.
final class LevelHistoryView: NSView {
    private var samples: [Float] = []
    private let capacity = 420          // about 7 minutes at one sample per second
    private var peakHold: Float = 0

    /// Below this, speech will almost certainly not survive transcription.
    private let floor: Float = 0.06

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 96) }

    func append(_ level: Float) {
        samples.append(level)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
        peakHold = max(peakHold * 0.995, level)
        needsDisplay = true
    }

    func reset() {
        samples.removeAll()
        peakHold = 0
        needsDisplay = true
    }

    /// Fraction of the visible history that sat below the usable floor.
    var quietFraction: Double {
        guard !samples.isEmpty else { return 0 }
        return Double(samples.filter { $0 < floor }.count) / Double(samples.count)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        Theme.Palette.surface.setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        path.fill()
        path.addClip()

        // The usable floor, drawn so a quiet passage is visibly below a line
        // rather than just "small".
        let floorY = bounds.minY + bounds.height * CGFloat(floor)
        Theme.Palette.warn.withAlphaComponent(0.35).setStroke()
        let guide = NSBezierPath()
        guide.move(to: NSPoint(x: bounds.minX, y: floorY))
        guide.line(to: NSPoint(x: bounds.maxX, y: floorY))
        guide.setLineDash([3, 3], count: 2, phase: 0)
        guide.lineWidth = 1
        guide.stroke()

        guard !samples.isEmpty else {
            let hint = "waiting for audio"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: Theme.Font.rowMeta, .foregroundColor: Theme.Palette.faint,
            ]
            let size = hint.size(withAttributes: attributes)
            hint.draw(at: NSPoint(x: bounds.midX - size.width / 2,
                                  y: bounds.midY - size.height / 2),
                      withAttributes: attributes)
            return
        }

        // Newest on the right, so the eye lands on now.
        let barWidth: CGFloat = 2
        let gap: CGFloat = 1
        let slot = barWidth + gap
        let visible = min(samples.count, Int(bounds.width / slot))
        let window = samples.suffix(visible)

        for (index, level) in window.enumerated() {
            let x = bounds.maxX - CGFloat(visible - index) * slot
            let height = max(1.5, bounds.height * CGFloat(min(1, level)))
            let rect = NSRect(x: x, y: bounds.minY, width: barWidth, height: height)
            (level < floor ? Theme.Palette.warn.withAlphaComponent(0.55)
                           : Theme.Palette.leaf).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
        }
        context.resetClip()
    }
}
