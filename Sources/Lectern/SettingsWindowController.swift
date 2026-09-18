import AppKit

/// Everything the user picks once and then forgets: course list, input device,
/// destination, model, and a preflight that names any missing dependency.
final class SettingsWindowController: NSWindowController {
    private var settings: Settings
    var onSave: ((Settings) -> Void)?

    private let devicePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let destinationPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let rootField = NSTextField(string: "")
    private let obsidianField = NSTextField(string: "")
    private let denoiseCheck = NSButton(checkboxWithTitle: "Denoise before transcribing", target: nil, action: nil)
    private let autoRunCheck = NSButton(checkboxWithTitle: "Process automatically when I stop", target: nil, action: nil)
    private let linkPreviousCheck = NSButton(checkboxWithTitle: "Link each note to earlier lectures", target: nil, action: nil)
    private let closeGapsCheck = NSButton(checkboxWithTitle: "Tick off gaps this lecture answers on earlier notes", target: nil, action: nil)
    private let lookbackField = NSTextField(string: "4")
    private let preflightLabel = NSTextField(labelWithString: "")

    private var devices: [AudioDevice] = []

    init(settings: Settings) {
        self.settings = settings
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 520),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Lectern Settings"
        window.center()
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func buildUI() {
        devices = AudioDevices.inputs()
        devicePopup.addItems(withTitles: ["System default"] + devices.map(\.name))
        if let uid = settings.inputDeviceUID,
           let index = devices.firstIndex(where: { $0.uid == uid }) {
            devicePopup.selectItem(at: index + 1)
        }

        destinationPopup.addItems(withTitles: Destination.allCases.map(\.label))
        if let index = Destination.allCases.firstIndex(of: settings.destination) {
            destinationPopup.selectItem(at: index)
        }
        destinationPopup.target = self
        destinationPopup.action = #selector(destinationChanged)

        modelPopup.addItems(withTitles: ["opus", "sonnet", "haiku"])
        modelPopup.selectItem(withTitle: settings.claudeModel)

        rootField.stringValue = settings.notesRoot
        obsidianField.stringValue = settings.obsidianVaultPath
        obsidianField.placeholderString = "/path/to/vault"
        denoiseCheck.state = settings.denoise ? .on : .off
        autoRunCheck.state = settings.autoRunPipelineOnStop ? .on : .off
        linkPreviousCheck.state = settings.linkPreviousLectures ? .on : .off
        linkPreviousCheck.target = self
        linkPreviousCheck.action = #selector(continuityChanged)
        closeGapsCheck.state = settings.closeResolvedGaps ? .on : .off
        closeGapsCheck.toolTip = "Edits already-published notes, but only to tick a checkbox and add the answer."
        lookbackField.stringValue = String(settings.continuityLookback)

        preflightLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        preflightLabel.textColor = .secondaryLabelColor
        preflightLabel.maximumNumberOfLines = 6
        preflightLabel.cell?.wraps = true

        let checkButton = NSButton(title: "Run preflight", target: self, action: #selector(runPreflight))
        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"

        let grid = NSGridView(views: [
            [label("Audio input"), devicePopup],
            [label("Publish to"), destinationPopup],
            [label("Obsidian vault"), obsidianField],
            [label("Notes folder"), rootField],
            [label("Claude model"), modelPopup],
            [NSView(), denoiseCheck],
            [NSView(), autoRunCheck],
            [NSView(), linkPreviousCheck],
            [NSView(), closeGapsCheck],
            [label("Lectures to recall"), lookbackField],
            [label("Dependencies"), preflightLabel],
            [NSView(), checkButton],
            [NSView(), saveButton],
        ])
        grid.columnSpacing = 12
        grid.rowSpacing = 11
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            devicePopup.widthAnchor.constraint(equalToConstant: 280),
            destinationPopup.widthAnchor.constraint(equalToConstant: 280),
            obsidianField.widthAnchor.constraint(equalToConstant: 280),
            rootField.widthAnchor.constraint(equalToConstant: 280),
            preflightLabel.widthAnchor.constraint(equalToConstant: 280),
            lookbackField.widthAnchor.constraint(equalToConstant: 60),
        ])
        window?.contentView = content
        destinationChanged()
        continuityChanged()
        runPreflight()
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        return field
    }

    @objc private func continuityChanged() {
        let on = linkPreviousCheck.state == .on
        closeGapsCheck.isEnabled = on
        lookbackField.isEnabled = on
    }

    @objc private func destinationChanged() {
        let destination = Destination.allCases[max(0, destinationPopup.indexOfSelectedItem)]
        obsidianField.isEnabled = destination.needsPath
    }

    /// Names exactly what is missing and how to install it, rather than failing
    /// mid-lecture with a stack trace.
    @objc private func runPreflight() {
        var lines: [String] = []
        func check(_ name: String, _ hint: String) {
            lines.append(Shell.which(name) != nil ? "ok    \(name)" : "MISSING \(name) -> \(hint)")
        }
        check("ffmpeg", "brew install ffmpeg")
        check("parakeet-mlx", "uv tool install parakeet-mlx -U")
        check("claude", "install Claude Code")

        let destination = Destination.allCases[max(0, destinationPopup.indexOfSelectedItem)]
        for server in destination.requiredMCPServers {
            lines.append(MCPRegistry.isConfigured(server)
                ? "ok    mcp: \(server)"
                : "MISSING mcp: \(server) -> claude mcp add \(server)")
        }
        if AudioDevices.inputs().isEmpty { lines.append("MISSING no audio input devices") }

        preflightLabel.stringValue = lines.joined(separator: "\n")
        preflightLabel.textColor = lines.contains { $0.hasPrefix("MISSING") } ? .systemOrange : .secondaryLabelColor
    }

    @objc private func save() {
        let deviceIndex = devicePopup.indexOfSelectedItem
        settings.inputDeviceUID = deviceIndex <= 0 ? nil : devices[deviceIndex - 1].uid
        settings.destination = Destination.allCases[max(0, destinationPopup.indexOfSelectedItem)]
        settings.claudeModel = modelPopup.titleOfSelectedItem ?? "opus"
        settings.notesRoot = NSString(string: rootField.stringValue).expandingTildeInPath
        settings.obsidianVaultPath = obsidianField.stringValue
        settings.denoise = denoiseCheck.state == .on
        settings.autoRunPipelineOnStop = autoRunCheck.state == .on
        settings.linkPreviousLectures = linkPreviousCheck.state == .on
        settings.closeResolvedGaps = closeGapsCheck.state == .on
        settings.continuityLookback = max(1, min(12, Int(lookbackField.stringValue) ?? 4))
        settings.save()
        onSave?(settings)
        window?.close()
    }
}
