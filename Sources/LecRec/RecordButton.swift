import AppKit

/// The one control that matters in class: a full-width pill, unmistakable in
/// both states, with a pulsing dot while capturing so a glance confirms it is live.
final class RecordButton: NSControl {
    enum State {
        case idle
        case recording
        case busy
    }

    private var buttonState: State = .idle
    private var isPressed = false
    private let titleLabel = Theme.label("Start recording", font: Theme.Font.of(13, .semibold))
    private let dot = NSView()
    private let spinner = NSProgressIndicator()

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 38) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = 9

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = NSColor.white.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [dot, spinner, titleLabel])
        row.orientation = .horizontal
        row.spacing = 7
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: centerXAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
        ])
        apply(.idle)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func apply(_ newState: State) {
        buttonState = newState
        switch newState {
        case .idle:
            titleLabel.stringValue = "Start recording"
            titleLabel.textColor = NSColor(srgbRed: 0.09, green: 0.13, blue: 0.04, alpha: 1)
            dot.isHidden = true
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            setBackground(Theme.Palette.leaf)
            stopPulse()
            isEnabled = true
        case .recording:
            titleLabel.stringValue = "Stop and process"
            titleLabel.textColor = .white
            dot.isHidden = false
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            setBackground(Theme.Palette.record)
            startPulse()
            isEnabled = true
        case .busy:
            titleLabel.stringValue = "Processing"
            titleLabel.textColor = .secondaryLabelColor
            dot.isHidden = true
            spinner.isHidden = false
            spinner.startAnimation(nil)
            setBackground(Theme.Palette.surface)
            stopPulse()
            isEnabled = false
        }
    }

    private func setBackground(_ color: NSColor) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.Motion.stateChange
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer?.backgroundColor = color.cgColor
        }
    }

    private func startPulse() {
        guard dot.layer?.animation(forKey: "pulse") == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.25
        pulse.duration = Theme.Motion.pulse / 2
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.layer?.add(pulse, forKey: "pulse")
    }

    private func stopPulse() { dot.layer?.removeAnimation(forKey: "pulse") }

    // MARK: - Hit handling

    /// Labels and image views inside a custom control swallow clicks: AppKit hit
    /// tests the deepest subview, an NSTextField returns itself, and mouseDown
    /// never reaches the control. This routes every point inside the bounds back
    /// to the control itself. Calling mouseDown directly in a test hides this,
    /// which is exactly how it shipped.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        alphaValue = 0.82
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, isPressed else { return }
        isPressed = false
        alphaValue = 1
        let local = convert(event.locationInWindow, from: nil)
        guard bounds.contains(local) else { return }
        Diagnostics.log("record button pressed, state=\(buttonState)")
        sendAction(action, to: target)
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        sendAction(action, to: target)
        return true
    }
    override func accessibilityLabel() -> String? { titleLabel.stringValue }
}
