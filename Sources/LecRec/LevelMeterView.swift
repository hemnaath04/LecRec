import AppKit

/// Seven bars driven by input RMS. The point is that a dead or hopelessly quiet
/// mic is obvious during class, not after the lecture is over.
final class LevelMeterView: NSView {
    private var level: Float = 0
    private var peakHold: Float = 0
    private var lastPeakBump = Date.distantPast

    override var intrinsicContentSize: NSSize { NSSize(width: 74, height: 16) }

    func update(level newLevel: Float) {
        level = newLevel
        if newLevel >= peakHold || Date().timeIntervalSince(lastPeakBump) > 1.2 {
            peakHold = newLevel
            lastPeakBump = Date()
        }
        needsDisplay = true
    }

    func reset() {
        level = 0
        peakHold = 0
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let barCount = 7
        let gap: CGFloat = 3
        let width = (bounds.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount)
        let lit = Int((level * Float(barCount)).rounded())
        let peakBar = Int((peakHold * Float(barCount)).rounded())

        for index in 0..<barCount {
            let fraction = CGFloat(index + 1) / CGFloat(barCount)
            let height = max(3, bounds.height * (0.35 + 0.65 * fraction))
            let rect = NSRect(x: CGFloat(index) * (width + gap),
                              y: (bounds.height - height) / 2,
                              width: width, height: height)
            let path = NSBezierPath(roundedRect: rect, xRadius: width / 2, yRadius: width / 2)

            if index < lit {
                (index >= barCount - 1 ? NSColor.systemOrange : NSColor.controlAccentColor).setFill()
            } else if index == peakBar - 1 {
                NSColor.controlAccentColor.withAlphaComponent(0.45).setFill()
            } else {
                NSColor.quaternaryLabelColor.setFill()
            }
            path.fill()
        }
    }
}

/// Warns when the input has been near silent for a while, which on a back-row
/// laptop recording usually means the wrong device is selected.
final class SilenceWatchdog {
    private var quietSince: Date?
    private(set) var isWarning = false
    var onChange: ((Bool) -> Void)?

    func observe(level: Float) {
        let quiet = level < 0.04
        if quiet {
            if quietSince == nil { quietSince = Date() }
            let elapsed = Date().timeIntervalSince(quietSince ?? Date())
            setWarning(elapsed > 20)
        } else {
            quietSince = nil
            setWarning(false)
        }
    }

    func reset() {
        quietSince = nil
        setWarning(false)
    }

    private func setWarning(_ value: Bool) {
        guard value != isWarning else { return }
        isWarning = value
        onChange?(value)
    }
}
