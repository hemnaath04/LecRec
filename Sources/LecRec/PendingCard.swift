import AppKit
import UniformTypeIdentifiers

/// The handoff between the two phases, shown at the top of the dashboard.
///
/// This is where a transcribed lecture waits for its slide deck. It is the whole
/// reason the pipeline pauses: the deck is what turns a transcript-only note
/// into a cross-checked one, and it is rarely to hand the second class ends.
final class PendingCard: NSView {
    private let title = Theme.label("", font: Theme.Font.of(15, .semibold), color: Theme.Palette.ink)
    private let detail = Theme.label("", font: Theme.Font.rowMeta, color: Theme.Palette.muted, lines: 2)
    private let deckLabel = Theme.label("", font: Theme.Font.rowMeta, color: Theme.Palette.faint, lines: 1)
    private let qualityLabel = Theme.label("", font: Theme.Font.of(11.5, .medium),
                                           color: Theme.Palette.warn, lines: 3)
    private let overrideBox = NSButton(checkboxWithTitle:
        "Write it up anyway, I understand the note will be thin", target: nil, action: nil)
    private let attachButton = NSButton()
    private let playButton = NSButton()
    private let codeButton = NSButton()
    private let codeLabel = Theme.label("", font: Theme.Font.rowMeta, color: Theme.Palette.faint, lines: 2)
    private let startButton = RecordButton(frame: .zero)
    private let skipButton = NSButton()

    private var pending: PendingLecture?
    var onStart: ((PendingLecture) -> Void)?
    var onChanged: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = 14
        layer?.backgroundColor = Theme.Palette.leaf.withAlphaComponent(0.10).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = Theme.Palette.leaf.withAlphaComponent(0.30).cgColor

        attachButton.title = "Choose deck (PDF or PPTX)"
        attachButton.bezelStyle = .push
        attachButton.target = self
        attachButton.action = #selector(chooseDeck)

        // Nothing here could play the recording, so the only way to judge a
        // questionable lecture before approving it was to go find the file.
        // The notebook worked through in class is the only exact record of what
        // the code actually was, so it is worth a button of its own.
        codeButton.title = "Attach class code"
        codeButton.bezelStyle = .accessoryBarAction
        codeButton.controlSize = .small
        codeButton.target = self
        codeButton.action = #selector(chooseCode)

        playButton.title = "Play recording"
        playButton.bezelStyle = .accessoryBarAction
        playButton.controlSize = .small
        playButton.target = self
        playButton.action = #selector(playRecording)

        skipButton.title = "No deck for this one"
        skipButton.bezelStyle = .accessoryBarAction
        skipButton.controlSize = .small
        skipButton.target = self
        skipButton.action = #selector(clearDeck)

        startButton.idleTitle = "Write the note"
        startButton.target = self
        startButton.action = #selector(start)
        startButton.translatesAutoresizingMaskIntoConstraints = false

        let buttons = NSStackView(views: [attachButton, codeButton, skipButton, playButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let left = NSStackView(views: [title, detail, qualityLabel, overrideBox, buttons, deckLabel, codeLabel])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 7
        left.setCustomSpacing(8, after: detail)
        left.setCustomSpacing(12, after: overrideBox)
        overrideBox.target = self
        overrideBox.action = #selector(overrideChanged)

        let row = NSStackView(views: [left, NSView(), startButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 24
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            startButton.widthAnchor.constraint(equalToConstant: 190),
            detail.widthAnchor.constraint(lessThanOrEqualToConstant: 460),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(_ item: PendingLecture) {
        pending = item
        title.stringValue = "\(item.courseName) is transcribed"

        var bits = [Self.dateText(item.date), Library.clock(item.audioDuration), item.coverageText]
        detail.stringValue = bits.joined(separator: "  ·  ")
        detail.textColor = (item.coverage ?? 1) < 0.95 ? Theme.Palette.warn : Theme.Palette.muted

        refreshDeck()
        applyQuality(item)
    }

    /// A poor transcript does not block publishing, it blocks publishing by
    /// accident. The button is disabled until the warning is acknowledged, so a
    /// junk recording cannot become a Notion page on a stray click.
    private func applyQuality(_ item: PendingLecture) {
        guard let note = item.qualityNote else {
            qualityLabel.isHidden = true
            overrideBox.isHidden = true
            startButton.apply(.idle)
            startButton.isEnabled = true
            return
        }
        qualityLabel.isHidden = false
        qualityLabel.stringValue = note
        qualityLabel.textColor = item.qualityBlocking ? Theme.Palette.record : Theme.Palette.warn

        overrideBox.isHidden = !item.qualityBlocking
        if item.qualityBlocking {
            overrideBox.state = .off
            startButton.apply(.busy)
            startButton.isEnabled = false
        } else {
            startButton.apply(.idle)
            startButton.isEnabled = true
        }
    }

    @objc private func overrideChanged() {
        let allowed = overrideBox.state == .on
        startButton.apply(allowed ? .idle : .busy)
        startButton.isEnabled = allowed
    }

    private func refreshDeck() {
        guard let pending else { return }
        if let deck = pending.deckPath, !deck.isEmpty {
            deckLabel.stringValue = "Deck: \((deck as NSString).lastPathComponent)"
            deckLabel.textColor = Theme.Palette.leaf
            attachButton.title = "Change deck"
            skipButton.isHidden = false
        } else {
            deckLabel.stringValue = "No deck attached. The note will be transcript only, and will say so."
            deckLabel.textColor = Theme.Palette.faint
            attachButton.title = "Choose deck (PDF or PPTX)"
            skipButton.isHidden = true
        }
        refreshCode()
    }

    private func refreshCode() {
        let paths = pending?.codePaths ?? []
        guard !paths.isEmpty else {
            codeLabel.stringValue = ""
            codeLabel.isHidden = true
            codeButton.title = "Attach class code"
            return
        }
        codeLabel.isHidden = false
        codeLabel.textColor = Theme.Palette.leaf
        let names = paths.map { ($0 as NSString).lastPathComponent }
        codeLabel.stringValue = names.count == 1
            ? "Code: \(names[0])"
            : "Code: \(names.count) files, \(names.joined(separator: ", "))"
        codeButton.title = "Change class code"
    }

    // MARK: - Actions

    @objc private func playRecording() {
        guard let pending else { return }
        Media.play(pending.audioURL)
    }

    @objc private func chooseCode() {
        guard var item = pending else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Pick the notebook or source files from this class."
        panel.allowedContentTypes = [
            UTType(filenameExtension: "ipynb"), UTType(filenameExtension: "py"),
            UTType(filenameExtension: "java"), UTType(filenameExtension: "sql"),
            UTType(filenameExtension: "r"), UTType(filenameExtension: "txt"),
            UTType(filenameExtension: "md"), .pythonScript, .sourceCode, .plainText,
        ].compactMap { $0 }
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        var paths = item.codePaths ?? []
        for url in panel.urls where !paths.contains(url.path) { paths.append(url.path) }
        item.codePaths = paths
        PendingStore.update(item)
        configure(item)
        onChanged?()
    }

    @objc private func clearCode() {
        guard var item = pending else { return }
        item.codePaths = nil
        PendingStore.update(item)
        configure(item)
        onChanged?()
    }

    @objc private func chooseDeck() {
        guard var item = pending else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose the slide deck for \(item.courseName), \(Self.dateText(item.date))"
        panel.prompt = "Attach"
        var types: [UTType] = [.pdf]
        for ext in ["pptx", "ppt", "key"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        panel.allowedContentTypes = types
        // Decks usually arrive in Downloads, so start there.
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            item.deckPath = url.path
            PendingStore.update(item)
            self.pending = item
            self.refreshDeck()
            Diagnostics.log("deck attached: \(url.lastPathComponent)")
            self.onChanged?()
        }
    }

    @objc private func clearDeck() {
        guard var item = pending else { return }
        item.deckPath = nil
        PendingStore.update(item)
        pending = item
        refreshDeck()
        onChanged?()
    }

    @objc private func start() {
        guard let pending else { return }
        if pending.qualityBlocking, overrideBox.state != .on {
            Diagnostics.log("write-up blocked: quality warning not acknowledged")
            return
        }
        startButton.apply(.busy)
        onStart?(pending)
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: date)
    }
}
