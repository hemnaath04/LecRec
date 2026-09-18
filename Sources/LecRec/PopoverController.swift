import AppKit
import AVFoundation

/// The whole in-class surface. Sections appear only in the phase they belong to,
/// so what is on screen is always what the user can act on right now.
final class PopoverController: NSViewController {
    private enum Phase {
        case ready, recording, processing, finished, failed
    }

    private var settings: Settings
    private let recorder = Recorder()
    private let watchdog = SilenceWatchdog()

    // Controls
    private let coursePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let topicField = NSTextField(string: "")
    private let recordButton = RecordButton(frame: .zero)
    private let meter = LevelMeterView()
    private let clockLabel = Theme.label("00:00", font: Theme.Font.clock, color: .labelColor)
    private let hintLabel = Theme.label("", font: Theme.Font.caption, color: .secondaryLabelColor, lines: 2)
    private let stages = StageListView(frame: .zero)
    private let inputLabel = Theme.label("", font: Theme.Font.caption, color: .tertiaryLabelColor)
    private let destinationLabel = Theme.label("", font: Theme.Font.caption, color: .tertiaryLabelColor)
    private let openNoteButton = NSButton()

    // Grouped rows we show and hide by phase
    private var meterRow: NSStackView!
    private var permissionCard: NSView?
    private let permissionLabel = Theme.label(
        "Microphone access is off, so LecRec cannot record.",
        font: Theme.Font.caption, color: .labelColor, lines: 2)

    private var phase: Phase = .ready
    private var lastNoteURL: URL?
    private var currentStage: PipelineStage = .idle

    var onStatusChange: ((Bool) -> Void)?
    var onOpenSettings: (() -> Void)?

    init(settings: Settings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Called before the first show, when the view hierarchy does not exist yet,
    /// so every view touch is gated on isViewLoaded.
    func reload(settings newSettings: Settings) {
        settings = newSettings
        guard isViewLoaded else { return }
        rebuildCourseMenu()
        refreshMeta()
        refreshPermissionState()
    }

    // MARK: - Layout

    override func loadView() {
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active

        let header = buildHeader()
        buildControls()
        let permissionCardView = buildPermissionCard()
        permissionCard = permissionCardView

        meterRow = NSStackView(views: [meter, NSView(), clockLabel])
        meterRow.orientation = .horizontal
        meterRow.alignment = .centerY
        meterRow.distribution = .fill

        let footer = NSStackView(views: [inputLabel, destinationLabel])
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 2

        let stack = NSStackView(views: [
            header,
            coursePopup,
            topicField,
            recordButton,
            meterRow,
            permissionCardView,
            stages,
            hintLabel,
            openNoteButton,
            footer,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Theme.rowGap
        stack.edgeInsets = NSEdgeInsets(top: Theme.gutter, left: Theme.gutter,
                                        bottom: Theme.gutter, right: Theme.gutter)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(Theme.tightGap, after: coursePopup)
        stack.setCustomSpacing(14, after: topicField)
        background.addSubview(stack)

        let fullWidth: [NSView] = [header, coursePopup, topicField, recordButton,
                                   meterRow, permissionCardView, stages, hintLabel, footer]
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            background.widthAnchor.constraint(equalToConstant: Theme.popoverWidth),
        ] + fullWidth.map {
            $0.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -Theme.gutter * 2)
        })

        view = background
        wireRecorder()
        rebuildCourseMenu()
        refreshMeta()
        apply(phase: .ready)
        refreshPermissionState()
    }

    private func buildHeader() -> NSStackView {
        let title = Theme.label("LecRec", font: Theme.Font.title)
        let settingsButton = Theme.iconButton(symbol: "gearshape", tooltip: "Settings",
                                              target: self, action: #selector(openSettings))
        let quitButton = Theme.iconButton(symbol: "power", tooltip: "Quit LecRec",
                                          target: NSApp, action: #selector(NSApplication.terminate(_:)))
        let header = NSStackView(views: [title, NSView(), settingsButton, quitButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 2
        header.distribution = .fill
        return header
    }

    private func buildControls() {
        coursePopup.target = self
        coursePopup.action = #selector(courseChanged)
        coursePopup.setAccessibilityLabel("Course")

        topicField.placeholderString = "Topic (optional, Claude names it otherwise)"
        topicField.font = Theme.Font.body
        topicField.bezelStyle = .roundedBezel
        topicField.setAccessibilityLabel("Lecture topic")

        recordButton.target = self
        recordButton.action = #selector(toggleRecording)

        clockLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        openNoteButton.title = "Open last note"
        openNoteButton.bezelStyle = .accessoryBarAction
        openNoteButton.controlSize = .small
        openNoteButton.target = self
        openNoteButton.action = #selector(openLastNote)
        openNoteButton.isHidden = true
    }

    /// Rather than telling the user where to click, take them there.
    private func buildPermissionCard() -> NSView {
        let card = Theme.card()
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "mic.slash.fill", accessibilityDescription: "microphone off")
        icon.contentTintColor = .systemOrange
        icon.translatesAutoresizingMaskIntoConstraints = false

        let button = NSButton(title: "Open System Settings", target: self,
                              action: #selector(openMicrophoneSettings))
        button.bezelStyle = .accessoryBarAction
        button.controlSize = .small

        let text = NSStackView(views: [permissionLabel, button])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 6

        let row = NSStackView(views: [icon, text])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            icon.widthAnchor.constraint(equalToConstant: 15),
            icon.heightAnchor.constraint(equalToConstant: 15),
        ])
        card.isHidden = true
        return card
    }

    // MARK: - Phase

    private func apply(phase newPhase: Phase) {
        phase = newPhase
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.Motion.stateChange
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            switch newPhase {
            case .ready:
                recordButton.apply(.idle)
                meterRow.isHidden = true
                stages.isHidden = true
                coursePopup.isEnabled = true
                topicField.isEnabled = true
                clockLabel.stringValue = "00:00"
            case .recording:
                recordButton.apply(.recording)
                meterRow.isHidden = false
                stages.isHidden = true
                coursePopup.isEnabled = false
                topicField.isEnabled = true
                hintLabel.stringValue = "Recording. You can close this window."
                hintLabel.textColor = .secondaryLabelColor
            case .processing:
                recordButton.apply(.busy)
                meterRow.isHidden = true
                stages.isHidden = false
                stages.reset()
                coursePopup.isEnabled = false
                topicField.isEnabled = false
            case .finished:
                recordButton.apply(.idle)
                meterRow.isHidden = true
                stages.isHidden = false
                coursePopup.isEnabled = true
                topicField.isEnabled = true
            case .failed:
                recordButton.apply(.idle)
                meterRow.isHidden = true
                coursePopup.isEnabled = true
                topicField.isEnabled = true
            }
        }
    }

    private func refreshPermissionState() {
        guard isViewLoaded, permissionCard != nil else { return }
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        let blocked = status == .denied || status == .restricted
        permissionCard?.isHidden = !blocked
        permissionLabel.stringValue = status == .restricted
            ? "Microphone access is blocked by a policy on this Mac."
            : "Microphone access is off, so LecRec cannot record."
    }

    private func refreshMeta() {
        guard isViewLoaded else { return }
        let device = settings.inputDeviceUID.flatMap { AudioDevices.device(uid: $0) }
            ?? AudioDevices.defaultInput()
        inputLabel.stringValue = "Input: \(device?.name ?? "system default")"
        destinationLabel.stringValue = "Publishes to: \(settings.destination.label)"
    }

    private func rebuildCourseMenu() {
        coursePopup.removeAllItems()
        coursePopup.addItems(withTitles: settings.courses.map(\.name))
        if let index = settings.courses.firstIndex(where: { $0.slug == settings.selectedCourseSlug }) {
            coursePopup.selectItem(at: index)
        }
    }

    private func wireRecorder() {
        recorder.onLevel = { [weak self] level in
            self?.meter.update(level: level)
            self?.watchdog.observe(level: level)
        }
        recorder.onTick = { [weak self] elapsed in
            self?.clockLabel.stringValue = Self.clock(elapsed)
        }
        watchdog.onChange = { [weak self] warning in
            guard let self, self.recorder.isRecording else { return }
            self.hintLabel.stringValue = warning
                ? "Almost no sound for 20 seconds. Check the input device in Settings."
                : "Recording. You can close this window."
            self.hintLabel.textColor = warning ? .systemOrange : .secondaryLabelColor
        }
    }

    // MARK: - Actions

    @objc private func courseChanged() {
        let index = coursePopup.indexOfSelectedItem
        guard index >= 0, index < settings.courses.count else { return }
        settings.selectedCourseSlug = settings.courses[index].slug
        settings.save()
    }

    @objc private func openSettings() { onOpenSettings?() }

    @objc private func openLastNote() {
        guard let url = lastNoteURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Verified on macOS 27: this deep link lands directly on the Microphone pane.
    @objc private func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        if let url, NSWorkspace.shared.open(url) { return }
        // Fall back to the Privacy and Security pane, then the app itself.
        if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security"),
           NSWorkspace.shared.open(fallback) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    @objc private func toggleRecording() {
        recorder.isRecording ? finishRecording() : beginRecording()
    }

    /// Driven from the main window, so both surfaces share one recorder rather
    /// than each owning their own and fighting over the microphone.
    func toggleRecordingExternally() {
        _ = view            // force loadView, the controls must exist first
        toggleRecording()
    }

    var isRecording: Bool { recorder.isRecording }

    /// Fires whenever a run finishes, so the dashboard can pick up the new lecture.
    var onLibraryChanged: (() -> Void)?

    private func beginRecording() {
        Task { @MainActor in
            let granted = await Recorder.requestPermission()
            self.refreshPermissionState()
            guard granted else {
                // The card is already visible with a button that goes straight there.
                self.hintLabel.stringValue = "Grant microphone access, then press Start again."
                self.hintLabel.textColor = .systemOrange
                self.permissionCard?.isHidden = false
                return
            }

            guard let course = self.settings.selectedCourse else {
                self.hintLabel.stringValue = "Add a course in Settings before recording."
                self.hintLabel.textColor = .systemOrange
                self.onOpenSettings?()
                return
            }
            let url = URL(fileURLWithPath: self.settings.notesRoot)
                .appendingPathComponent(course.slug, isDirectory: true)
                .appendingPathComponent("audio/\(Self.stamp())-raw.caf")
            do {
                try self.recorder.start(deviceUID: self.settings.inputDeviceUID, to: url)
                self.openNoteButton.isHidden = true
                self.watchdog.reset()
                self.apply(phase: .recording)
                self.onStatusChange?(true)
                Diagnostics.log("recording started -> \(url.path)")
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }

    private func finishRecording() {
        guard let finished = recorder.stop() else { return }
        meter.reset()
        watchdog.reset()
        onStatusChange?(false)
        Diagnostics.log("recording stopped, \(Int(finished.duration))s at \(finished.url.lastPathComponent)")

        guard settings.autoRunPipelineOnStop else {
            apply(phase: .ready)
            hintLabel.stringValue = "Saved \(finished.url.lastPathComponent). Automatic processing is off in Settings."
            hintLabel.textColor = .secondaryLabelColor
            return
        }

        apply(phase: .processing)
        hintLabel.stringValue = "This runs on your Mac and takes a few minutes. You can close this window."
        hintLabel.textColor = .secondaryLabelColor

        guard let course = settings.selectedCourse else { return }
        let lecture = Lecture(
            course: course,
            date: Date(),
            slug: Self.slugify(topicField.stringValue),
            audioURL: finished.url,
            audioDuration: finished.duration,
            deckPath: nil)

        let pipeline = Pipeline(settings: settings)
        pipeline.onStage = { [weak self] stage, detail in
            guard let self else { return }
            self.currentStage = stage
            self.stages.advance(to: stage, detail: detail)
        }
        pipeline.onLog = { message in Diagnostics.log(message) }

        Task { @MainActor in
            do {
                let note = try await pipeline.run(lecture: lecture)
                self.lastNoteURL = note
                self.openNoteButton.isHidden = false
                self.stages.finish(publishedTo: self.settings.destination.label)
                self.apply(phase: .finished)
                self.topicField.stringValue = ""
                self.hintLabel.stringValue = "\(note.lastPathComponent) is ready."
                self.hintLabel.textColor = .secondaryLabelColor
                self.onLibraryChanged?()
                Notifier.post(title: "Lecture note ready",
                              body: "\(course.name), \(Self.clock(finished.duration)) recorded.")
            } catch {
                self.stages.markFailure(at: self.currentStage, message: error.localizedDescription)
                self.apply(phase: .failed)
                self.fail(error.localizedDescription)
                // The audio survives regardless, which is the whole point of disk first.
                self.lastNoteURL = finished.url
                self.openNoteButton.title = "Open recording folder"
                self.openNoteButton.isHidden = false
                self.onLibraryChanged?()
                Notifier.post(title: "Lecture processing failed",
                              body: "Your audio is safe at \(finished.url.lastPathComponent).")
            }
        }
    }

    private func fail(_ message: String) {
        hintLabel.stringValue = message
        hintLabel.textColor = .systemRed
        Diagnostics.log("FAILED: \(message)")
    }

    // MARK: - Helpers

    static func slugify(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -"))
        let cleaned = String(trimmed.unicodeScalars.filter { allowed.contains($0) })
        return cleaned.split(whereSeparator: { $0 == " " || $0 == "-" }).joined(separator: "-")
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%02d:%02d", total / 60, total % 60)
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: Date())
    }
}
