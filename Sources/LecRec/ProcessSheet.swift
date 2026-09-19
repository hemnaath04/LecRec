import AppKit
import UniformTypeIdentifiers

/// Shown when the user processes a recording by hand. Its whole job is to let
/// them attach the lecture's slide deck, which is the source that turns a
/// transcript-only note into a cross-checked one.
final class ProcessSheet: NSViewController {
    private let item: LibraryItem
    private var deckPath: String?

    private let deckLabel = Theme.label("No deck attached", font: Theme.Font.rowMeta,
                                        color: Theme.Palette.faint, lines: 2)
    private let startButton = NSButton()

    var onStart: ((String?) -> Void)?

    init(item: LibraryItem) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 268))
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.Palette.canvas.cgColor

        let title = Theme.label("Process this lecture", font: Theme.Font.of(16, .semibold),
                                color: Theme.Palette.ink)
        let subtitle = Theme.label(
            "\(item.courseName), \(Self.dateText(item.date))"
                + (item.duration > 0 ? ", \(Library.clock(item.duration))" : ""),
            font: Theme.Font.rowMeta, color: Theme.Palette.faint)

        let explain = Theme.label(
            "Attach the slide deck if you have it. The transcript alone garbles numbers, "
                + "formulas and proper nouns, and the deck is what corrects them.",
            font: Theme.Font.rowMeta, color: Theme.Palette.muted, lines: 3)

        let attachButton = NSButton(title: "Choose deck (PDF or PPTX)", target: self,
                                    action: #selector(chooseDeck))
        attachButton.bezelStyle = .push
        attachButton.controlSize = .regular

        let clearButton = NSButton(title: "Remove", target: self, action: #selector(clearDeck))
        clearButton.bezelStyle = .accessoryBarAction
        clearButton.controlSize = .small

        let attachRow = NSStackView(views: [attachButton, clearButton])
        attachRow.orientation = .horizontal
        attachRow.spacing = 8

        startButton.title = "Start processing"
        startButton.bezelStyle = .push
        startButton.controlSize = .large
        startButton.keyEquivalent = "\r"
        startButton.target = self
        startButton.action = #selector(start)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(dismissSheet))
        cancel.bezelStyle = .push
        cancel.keyEquivalent = "\u{1b}"

        let buttons = NSStackView(views: [NSView(), cancel, startButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let stack = NSStackView(views: [title, subtitle, explain, attachRow, deckLabel, NSView(), buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 11
        stack.setCustomSpacing(3, after: title)
        stack.setCustomSpacing(18, after: subtitle)
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            explain.widthAnchor.constraint(equalToConstant: 412),
            deckLabel.widthAnchor.constraint(equalToConstant: 412),
            buttons.widthAnchor.constraint(equalToConstant: 412),
        ])
        view = root
    }

    @objc private func chooseDeck() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose the slide deck for this lecture"
        var types: [UTType] = [.pdf]
        if let pptx = UTType(filenameExtension: "pptx") { types.append(pptx) }
        if let ppt = UTType(filenameExtension: "ppt") { types.append(ppt) }
        panel.allowedContentTypes = types

        panel.beginSheetModal(for: view.window ?? NSApp.keyWindow ?? NSWindow()) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.deckPath = url.path
            self?.deckLabel.stringValue = url.lastPathComponent
            self?.deckLabel.textColor = Theme.Palette.ink
        }
    }

    @objc private func clearDeck() {
        deckPath = nil
        deckLabel.stringValue = "No deck attached"
        deckLabel.textColor = Theme.Palette.faint
    }

    @objc private func start() {
        onStart?(deckPath)
        dismissSheet()
    }

    @objc private func dismissSheet() {
        view.window?.sheetParent?.endSheet(view.window!)
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: date)
    }
}

/// A thin determinate bar with the current stage beside it.
final class ProgressStrip: NSView {
    private let track = NSView()
    private let fill = NSView()
    private let stageLabel = Theme.label("", font: Theme.Font.rowMeta, color: Theme.Palette.ink)
    private let percentLabel = Theme.label("", font: Theme.Font.rowMeta, color: Theme.Palette.faint)
    private var fillWidth: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = 10
        layer?.backgroundColor = Theme.Palette.surface.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = Theme.Palette.stroke.cgColor

        track.wantsLayer = true
        track.layer?.cornerRadius = 2
        track.layer?.backgroundColor = Theme.Palette.stroke.cgColor
        track.translatesAutoresizingMaskIntoConstraints = false

        fill.wantsLayer = true
        fill.layer?.cornerRadius = 2
        fill.layer?.backgroundColor = Theme.Palette.record.cgColor
        fill.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(fill)

        percentLabel.alignment = .right

        let header = NSStackView(views: [stageLabel, NSView(), percentLabel])
        header.orientation = .horizontal
        header.alignment = .centerY

        let stack = NSStackView(views: [header, track])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        fillWidth = fill.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            track.widthAnchor.constraint(equalTo: stack.widthAnchor),
            track.heightAnchor.constraint(equalToConstant: 4),
            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            fillWidth,
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func update(stage: String, detail: String, fraction: Double) {
        stageLabel.stringValue = detail.isEmpty ? stage : "\(stage): \(detail)"
        percentLabel.stringValue = "\(Int((fraction * 100).rounded()))%"
        layoutSubtreeIfNeeded()
        let target = max(0, min(1, fraction)) * track.bounds.width
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            fillWidth.animator().constant = target
        }
    }
}
