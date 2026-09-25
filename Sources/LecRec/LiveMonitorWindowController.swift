import AppKit

/// A window you can open to watch a recording or a processing run as it happens.
///
/// Built because both halves of this app were previously opaque. A recording
/// gave no sign of which microphone it was on, and a 39 second take on the wrong
/// input looked exactly like a good one. Processing gave no sign of what the
/// transcript actually said until an hour later, when 97 percent of it turned
/// out to be the literal string NON-ENGLISH SPEECH.
final class LiveMonitorWindowController: NSWindowController {
    private let clock = Theme.label("00:00", font: .monospacedDigitSystemFont(ofSize: 44, weight: .semibold),
                                    color: Theme.Palette.ink)
    private let statusDot = NSView()
    private let statusLabel = Theme.label("", font: Theme.Font.of(13, .medium), color: Theme.Palette.ink)
    private let deviceLabel = Theme.label("", font: Theme.Font.rowMeta, color: Theme.Palette.muted)
    private let sizeLabel = Theme.label("", font: Theme.Font.rowMeta, color: Theme.Palette.faint)
    private let warning = Theme.label("", font: Theme.Font.of(11.5, .medium), color: Theme.Palette.warn, lines: 2)

    private let history = LevelHistoryView(frame: .zero)
    private let stages = StageListView(frame: .zero)
    private let feed = NSTextView()
    private let feedScroll = NSScrollView()
    private let feedTitle = Theme.label("Live output", font: Theme.Font.of(9.5, .semibold),
                                        color: Theme.Palette.dim, tracking: 1.1)

    private weak var recorder: Recorder?
    private var ticker: Timer?
    private let feedKey = "live-monitor"

    init(recorder: Recorder?) {
        self.recorder = recorder
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Live"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Theme.Palette.canvas
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 520, height: 520)
        window.center()
        super.init(window: window)
        build()
        subscribe()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        ticker?.invalidate()
        Diagnostics.stopObserving(feedKey)
        ProcessingCenter.shared.stopObserving(feedKey)
    }

    // MARK: - Layout

    private func build() {
        let root = CanvasBackgroundView()

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 5
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.widthAnchor.constraint(equalToConstant: 10).isActive = true
        statusDot.heightAnchor.constraint(equalToConstant: 10).isActive = true

        let statusRow = NSStackView(views: [statusDot, statusLabel])
        statusRow.orientation = .horizontal
        statusRow.spacing = 8
        statusRow.alignment = .centerY

        let head = NSStackView(views: [statusRow, clock, deviceLabel, sizeLabel, warning])
        head.orientation = .vertical
        head.alignment = .leading
        head.spacing = 3
        head.setCustomSpacing(6, after: statusRow)
        head.setCustomSpacing(8, after: clock)

        // Monospaced, because the interesting failure is a repeated marker and
        // the eye catches a repeating column far faster than repeating prose.
        feed.isEditable = false
        feed.drawsBackground = true
        feed.backgroundColor = Theme.Palette.surface
        feed.textColor = Theme.Palette.inkSoft
        feed.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        feed.textContainerInset = NSSize(width: 10, height: 9)
        feedScroll.documentView = feed
        feedScroll.hasVerticalScroller = true
        feedScroll.drawsBackground = false
        feedScroll.wantsLayer = true
        feedScroll.layer?.cornerRadius = 8
        feedScroll.layer?.masksToBounds = true
        feedScroll.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [head, history, stages, feedTitle, feedScroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.setCustomSpacing(10, after: feedTitle)
        stack.edgeInsets = NSEdgeInsets(top: 40, left: 26, bottom: 22, right: 26)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            history.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -52),
            stages.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -52),
            feedScroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -52),
            feedScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 170),
            warning.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
        ])
        window?.contentView = root
        stages.isHidden = true
    }

    // MARK: - Wiring

    private func subscribe() {
        let backlog = Diagnostics.observe(feedKey) { [weak self] line in
            self?.appendFeed(line)
        }
        backlog.suffix(120).forEach { appendFeed($0) }

        ProcessingCenter.shared.observe(feedKey) { [weak self] update in
            guard let self else { return }
            if let update {
                self.stages.isHidden = false
                self.stages.advance(to: update.stage, detail: update.detail)
                self.setStatus(update.stage.rawValue, colour: Theme.Palette.leaf, pulsing: true)
                self.history.isHidden = true
                self.deviceLabel.stringValue = update.lecture.course.name
                self.clock.stringValue = "\(Int((update.fraction * 100).rounded()))%"
                self.sizeLabel.stringValue = update.detail
                self.warning.stringValue = ""
            } else if self.recorder?.isRecording != true {
                self.setStatus("Idle", colour: Theme.Palette.faint, pulsing: false)
            }
        }

        // One second is the right cadence: fast enough to feel live, slow enough
        // that the history spans a whole lecture on screen.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        tick()
    }

    private func tick() {
        guard let recorder, recorder.isRecording else {
            if !ProcessingCenter.shared.isRunning {
                setStatus("Idle", colour: Theme.Palette.faint, pulsing: false)
                deviceLabel.stringValue = "Nothing is being recorded"
                sizeLabel.stringValue = ""
            }
            return
        }

        history.isHidden = false
        stages.isHidden = true
        setStatus("Recording", colour: Theme.Palette.record, pulsing: true)
        clock.stringValue = Self.clock(recorder.duration)
        deviceLabel.stringValue = "Input: \(recorder.activeDeviceName)"

        let bytes = Double(recorder.bytesWritten) / 1e6
        let perMinute = recorder.duration > 5 ? bytes / (recorder.duration / 60) : 0
        sizeLabel.stringValue = perMinute > 0
            ? String(format: "%.0f MB written, about %.1f MB per minute", bytes, perMinute)
            : String(format: "%.0f MB written", bytes)

        let quiet = history.quietFraction
        if quiet > 0.6 {
            warning.stringValue = "Most of this recording is below the level speech needs. "
                + "Check that \(recorder.activeDeviceName) is the microphone you meant, and move it closer."
        } else if quiet > 0.3 {
            warning.stringValue = String(format: "%.0f%% of this recording so far is very quiet.", quiet * 100)
        } else {
            warning.stringValue = ""
        }
    }

    /// Called from the recorder's level callback, once per audio buffer.
    func observe(level: Float) {
        history.append(level)
    }

    private func setStatus(_ text: String, colour: NSColor, pulsing: Bool) {
        statusLabel.stringValue = text
        statusDot.layer?.backgroundColor = colour.cgColor
        if pulsing, statusDot.layer?.animation(forKey: "pulse") == nil {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.3
            pulse.duration = 0.7
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            statusDot.layer?.add(pulse, forKey: "pulse")
        } else if !pulsing {
            statusDot.layer?.removeAnimation(forKey: "pulse")
        }
    }

    private func appendFeed(_ line: String) {
        // Whisper's per-cue lines are the whole point of this pane, but its
        // model-loading spam is not.
        let noise = ["whisper_", "ggml_", "system_info", "main: processing", "load time",
                     "encode time", "decode time", "batchd time", "prompt time", "total time"]
        guard !noise.contains(where: { line.contains($0) }) else { return }

        let trimmed = line.count > 300 ? String(line.prefix(300)) + "..." : line
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
            .foregroundColor: colourFor(trimmed),
        ]
        feed.textStorage?.append(NSAttributedString(string: trimmed + "\n", attributes: attributes))

        // Cap the buffer, an hour of cues is tens of thousands of lines.
        if let storage = feed.textStorage, storage.length > 120_000 {
            storage.deleteCharacters(in: NSRange(location: 0, length: 40_000))
        }
        feed.scrollToEndOfDocument(nil)
    }

    private func colourFor(_ line: String) -> NSColor {
        if line.contains("NON-ENGLISH") || line.contains("BLANK_AUDIO") { return Theme.Palette.warn }
        if line.contains("FAILED") || line.contains("Error") { return Theme.Palette.record }
        if line.hasPrefix("[") { return Theme.Palette.inkSoft }      // a transcript cue
        return Theme.Palette.faint
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%02d:%02d", total / 60, total % 60)
    }
}
