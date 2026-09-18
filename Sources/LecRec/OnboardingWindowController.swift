import AppKit

/// First run. Turns "clone this and read the README" into something a friend can
/// actually finish: it checks each dependency, installs what it safely can, and
/// provisions the user's own Notion database.
final class OnboardingWindowController: NSWindowController {
    private enum Step: Int, CaseIterable {
        case welcome, dependencies, courses, finish
    }

    private var settings: Settings
    private var step: Step = .welcome
    private var dependencies: [Dependency] = []
    private var rows: [String: DependencyRow] = [:]

    var onFinish: ((Settings) -> Void)?

    private let container = NSView()
    private let titleLabel = Theme.label("", font: .systemFont(ofSize: 17, weight: .semibold))
    private let bodyLabel = Theme.label("", font: Theme.Font.body, color: .secondaryLabelColor, lines: 0)
    private let content = NSStackView()
    private let primaryButton = NSButton()
    private let secondaryButton = NSButton()
    private let progressLabel = Theme.label("", font: Theme.Font.caption, color: .tertiaryLabelColor)
    private let coursesField = NSTextField(string: "")
    private let helpButton = NSButton()
    private let logLabel = Theme.label("", font: .monospacedSystemFont(ofSize: 10, weight: .regular),
                                       color: .tertiaryLabelColor, lines: 3)

    init(settings: Settings) {
        self.settings = settings
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 470),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Welcome to LecRec"
        window.center()
        super.init(window: window)
        buildChrome()
        show(.welcome)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Chrome

    private func buildChrome() {
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10

        primaryButton.bezelStyle = .push
        primaryButton.controlSize = .large
        primaryButton.keyEquivalent = "\r"
        primaryButton.target = self
        primaryButton.action = #selector(primaryTapped)

        secondaryButton.bezelStyle = .accessoryBarAction
        secondaryButton.controlSize = .small
        secondaryButton.target = self
        secondaryButton.action = #selector(secondaryTapped)

        helpButton.bezelStyle = .helpButton
        helpButton.title = ""
        helpButton.target = self
        helpButton.action = #selector(showHelp)
        helpButton.toolTip = "Show step by step instructions"

        let buttons = NSStackView(views: [helpButton, progressLabel, NSView(), secondaryButton, primaryButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 10

        let stack = NSStackView(views: [titleLabel, bodyLabel, content, NSView(), logLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 26, bottom: 20, right: 26)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bodyLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -52),
            content.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -52),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -52),
            logLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -52),
        ])
        window?.contentView = container
    }

    private func clearContent() {
        content.arrangedSubviews.forEach {
            content.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
    }

    // MARK: - Steps

    /// Rebuilding the view tree from inside a button action re-sends that action
    /// to the new button under the still-tracking cursor, which walked the user
    /// through three steps on one click. Always hop a runloop turn first.
    private func advance(to newStep: Step) {
        DispatchQueue.main.async { [weak self] in self?.show(newStep) }
    }

    private func show(_ newStep: Step) {
        step = newStep
        clearContent()
        clearError()
        progressLabel.stringValue = "Step \(newStep.rawValue + 1) of \(Step.allCases.count)"
        secondaryButton.isHidden = newStep == .welcome

        switch newStep {
        case .welcome:
            titleLabel.stringValue = "LecRec records a lecture and writes the note"
            bodyLabel.stringValue = """
            Press record when class starts. When you stop, LecRec cleans the audio, \
            transcribes it on this Mac, then has Claude Code write a structured note and \
            publish it to your Notion.

            Two things are worth knowing before you set this up. Transcription runs \
            entirely on your Mac and is free, but the first run downloads about 2.3 GB. \
            Writing the note uses Claude Code, which needs a paid Claude plan starting at \
            20 dollars a month. LecRec never sees your audio or your notes; everything \
            runs under your own accounts.
            """
            primaryButton.title = "Get started"

        case .dependencies:
            titleLabel.stringValue = "What LecRec needs"
            bodyLabel.stringValue = "Install anything marked missing. LecRec runs the install for you where it safely can."
            dependencies = Dependency.all(for: settings.destination)
            rows = [:]
            for dependency in dependencies {
                let row = DependencyRow(dependency: dependency) { [weak self] dep in
                    self?.install(dep)
                }
                rows[dependency.title] = row
                content.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
            }
            refreshDependencyRows()
            primaryButton.title = "Continue"
            secondaryButton.title = "Re-check"

        case .courses:
            titleLabel.stringValue = "Your courses"
            bodyLabel.stringValue = """
            Type your courses separated by commas. They appear in Notion exactly as you \
            type them.

            Then choose where the notes go. Press "Find my databases" to pick an existing \
            one, or leave the box unticked and LecRec creates a Course Notes database for \
            you.
            """

            // NSTokenField rather than a text view in a scroll view: it is the native
            // control for a list of short strings, and it handles typing, paste and
            // editing without any of the manual text-container setup a bare
            // NSTextView needs to accept input reliably.
            courseField.placeholderString = "NLP CS 6120, IR CS 6200"
            courseField.tokenizingCharacterSet = CharacterSet(charactersIn: ",")
            courseField.objectValue = settings.courses.map(\.name)
            courseField.delegate = self
            courseField.font = Theme.Font.body
            content.addArrangedSubview(courseField)
            courseField.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

            if settings.destination == .notion {
                reuseCheckbox.title = "I already have a Notion database for these notes"
                reuseCheckbox.target = self
                reuseCheckbox.action = #selector(reuseToggled)
                reuseCheckbox.state = settings.notionDatabaseURL.isEmpty ? .off : .on
                reuseCheckbox.toolTip = "Leave this off and LecRec creates a database for you."
                existingField.placeholderString = "or paste the database URL or its id"
                existingField.stringValue = settings.notionDatabaseURL

                databasePopup.removeAllItems()
                databasePopup.addItem(withTitle: "Choose a database\u{2026}")
                databasePopup.target = self
                databasePopup.action = #selector(databasePicked)

                findButton.title = "Find my databases"
                findButton.bezelStyle = .push
                findButton.controlSize = .regular
                findButton.target = self
                findButton.action = #selector(findDatabases)

                let pickerRow = NSStackView(views: [databasePopup, findButton])
                pickerRow.orientation = .horizontal
                pickerRow.spacing = 8
                pickerRow.alignment = .centerY

                content.addArrangedSubview(reuseCheckbox)
                content.addArrangedSubview(pickerRow)
                content.addArrangedSubview(existingField)
                pickerRow.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
                existingField.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
                databasePopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
                reuseToggled()
            }
            primaryButton.title = primaryTitleForCourses()
            secondaryButton.title = "Back"
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self.courseField)
            }

        case .finish:
            titleLabel.stringValue = "You are set up"
            bodyLabel.stringValue = """
            LecRec lives in your menu bar. Pick a course, press record, and stop when \
            class ends. Your notes database is ready in Notion.
            """
            if !settings.notionDatabaseURL.isEmpty {
                let link = NSButton(title: "Open my Notion database", target: self,
                                    action: #selector(openDatabase))
                link.bezelStyle = .accessoryBarAction
                link.controlSize = .small
                content.addArrangedSubview(link)
            }
            primaryButton.title = "Start using LecRec"
            secondaryButton.isHidden = true
        }
    }

    private let courseField = NSTokenField()
    private let reuseCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let existingField = NSTextField(string: "")
    private let databasePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let findButton = NSButton()
    private var candidates: [NotionSetup.Candidate] = []
    private var lookupToken = UUID()

    private var isReusingDatabase: Bool {
        settings.destination == .notion && reuseCheckbox.state == .on
    }

    private func primaryTitleForCourses() -> String {
        guard settings.destination == .notion else { return "Continue" }
        return isReusingDatabase ? "Use this database" : "Create my Notion database"
    }

    @objc private func reuseToggled() {
        let on = isReusingDatabase
        existingField.isEnabled = on
        existingField.isHidden = !on
        databasePopup.isEnabled = on && !candidates.isEmpty
        databasePopup.superview?.isHidden = !on
        findButton.isEnabled = on
        primaryButton.title = primaryTitleForCourses()
    }

    /// Asks Notion which databases exist rather than making the user dig an id out
    /// of a URL. This is the difference between a setup step and a scavenger hunt.
    @objc private func findDatabases() {
        findButton.isEnabled = false
        findButton.title = "Looking\u{2026}"
        logLabel.stringValue = "Asking Notion which databases you have, this takes a few seconds."
        lookupToken = UUID()
        let token = lookupToken
        // Claude plus a Notion round trip is usually under 30s, but the button must
        // never be left disabled if it is not.
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
            guard let self, self.lookupToken == token, !self.findButton.isEnabled else { return }
            self.findButton.isEnabled = true
            self.findButton.title = "Find my databases"
            self.showError("Notion did not answer in time. Paste the database link instead.")
        }
        Task { @MainActor in
            do {
                self.candidates = try await NotionSetup.findDatabases { line in
                    DispatchQueue.main.async { self.logLabel.stringValue = line }
                }
                self.databasePopup.removeAllItems()
                if self.candidates.isEmpty {
                    self.databasePopup.addItem(withTitle: "No databases found")
                    self.logLabel.stringValue = "Nothing came back. Paste a URL, or untick the box to create one."
                } else {
                    self.databasePopup.addItem(withTitle: "Choose a database\u{2026}")
                    self.candidates.forEach { self.databasePopup.addItem(withTitle: $0.title) }
                    self.logLabel.stringValue = "Found \(self.candidates.count). Pick the one your notes go in."
                }
                self.databasePopup.isEnabled = !self.candidates.isEmpty
            } catch {
                self.logLabel.stringValue = error.localizedDescription
            }
            self.findButton.isEnabled = true
            self.findButton.title = "Find my databases"
        }
    }

    @objc private func databasePicked() {
        let index = databasePopup.indexOfSelectedItem - 1   // item 0 is the placeholder
        guard index >= 0, index < candidates.count else { return }
        let picked = candidates[index]
        existingField.stringValue = picked.url ?? picked.dataSourceId
        logLabel.stringValue = "Using \(picked.title)."
    }

    private func refreshDependencyRows() {
        dependencies = Dependency.all(for: settings.destination)
        for dependency in dependencies { rows[dependency.title]?.refresh(dependency) }
        let missing = dependencies.filter { $0.isRequired && !$0.isSatisfied }
        primaryButton.isEnabled = missing.isEmpty
        primaryButton.title = missing.isEmpty ? "Continue" : "Install what is missing first"
    }

    /// Includes whatever is still being typed, so a user who never presses return
    /// does not lose the course they just entered.
    private func currentCourseNames() -> [String] {
        var names = (courseField.objectValue as? [String]) ?? []
        let pending = courseField.stringValue
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for candidate in pending where !names.contains(candidate) { names.append(candidate) }
        return names
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func showError(_ message: String) {
        logLabel.stringValue = message
        logLabel.font = Theme.Font.captionStrong
        logLabel.textColor = .systemRed
    }

    private func clearError() {
        logLabel.stringValue = ""
        logLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        logLabel.textColor = .tertiaryLabelColor
        Validation.clear(courseField)
        Validation.clear(existingField)
    }

    // MARK: - Help

    /// Answers the question the current step actually raises, in place, rather
    /// than sending the user to a document they will not read.
    @objc private func showHelp() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        switch step {
        case .welcome:
            alert.messageText = "What LecRec does"
            alert.informativeText = """
            1. You press record when class starts, and stop when it ends.
            2. LecRec cleans the recording, then transcribes it on this Mac. No audio \
            is uploaded anywhere.
            3. Claude Code reads the transcript, cross-checks it against your slide \
            deck if you attached one, and writes a structured note.
            4. The note is saved to your Documents folder, then published to Notion.

            The audio file and a local copy of the note are always written before \
            anything is published, so a failed publish never costs you the lecture.
            """
        case .dependencies:
            alert.messageText = "About these requirements"
            alert.informativeText = """
            ffmpeg and parakeet-mlx are free and run on your Mac. Press Install and \
            LecRec runs the command for you. The first transcription downloads about \
            2.3 GB of model, once.

            Claude Code needs a paid Claude plan, from 20 dollars a month, because it \
            is what writes the note. LecRec cannot install or pay for it. Get it at \
            claude.com/claude-code, sign in, then come back and press Re-check.

            The Notion connection is added through Claude Code, not through LecRec, so \
            your Notion login is never handled by this app. Press Install to add it, \
            then run `claude` once in Terminal and approve the Notion sign in.
            """
        case .courses:
            alert.messageText = "Finding your Notion database"
            alert.informativeText = """
            Easiest way: press "Find my databases" and pick yours from the list.

            To do it by hand:
            1. Open the database in Notion as a full page, not inside another page.
            2. Click the ... menu at the top right, then Copy link.
            3. Paste it into the box. The whole URL is fine.

            The id is the long string of letters and numbers between the last slash \
            and the ?v= in that URL. The ?v= part is a saved view, not the database, \
            so do not trim the URL yourself; LecRec works it out.

            If you would rather start fresh, untick the box and LecRec creates a \
            Course Notes database for you.
            """
        case .finish:
            alert.messageText = "Using LecRec"
            alert.informativeText = """
            LecRec lives in your menu bar, the waveform icon. Click it, pick the \
            course, optionally type the topic, and press record.

            While recording, the level meter tells you sound is actually arriving. If \
            it sits flat for 20 seconds LecRec warns you, because a wrong input device \
            is the one mistake you cannot fix afterwards.

            Recordings, transcripts and notes all land in \
            ~/Documents/course-notes/<course>/
            """
        }
        alert.addButton(withTitle: "Got it")
        if step == .courses {
            alert.addButton(withTitle: "Open Notion")
        }
        if let window, alert.runModal() == .alertSecondButtonReturn, step == .courses {
            _ = window
            NSWorkspace.shared.open(URL(string: "https://www.notion.so")!)
        }
    }

    // MARK: - Actions

    @objc private func openDatabase() {
        guard let url = URL(string: settings.notionDatabaseURL) else { return }
        NSWorkspace.shared.open(url)
    }

    private func install(_ dependency: Dependency) {
        rows[dependency.title]?.setWorking(true)
        Task { @MainActor in
            do {
                try await DependencyInstaller.install(dependency) { [weak self] line in
                    DispatchQueue.main.async { self?.logLabel.stringValue = line }
                }
            } catch {
                self.logLabel.stringValue = error.localizedDescription
            }
            self.rows[dependency.title]?.setWorking(false)
            self.refreshDependencyRows()
        }
    }

    @objc private func secondaryTapped() {
        switch step {
        case .dependencies: refreshDependencyRows()
        case .courses: advance(to: .dependencies)
        default: break
        }
    }

    @objc private func primaryTapped() {
        switch step {
        case .welcome:
            advance(to: .dependencies)

        case .dependencies:
            do {
                try SkillInstaller.install()
            } catch {
                logLabel.stringValue = error.localizedDescription
            }
            advance(to: .courses)

        case .courses:
            let names = currentCourseNames()
            guard !names.isEmpty else {
                showError("Type at least one course above, for example NLP CS 6120.")
                Validation.flag(courseField)
                window?.makeFirstResponder(courseField)
                return
            }
            settings.courses = names.map { Course(name: $0) }
            settings.selectedCourseSlug = settings.courses[0].slug

            guard settings.destination == .notion else {
                settings.hasCompletedOnboarding = true
                settings.save()
                advance(to: .finish)
                return
            }

            primaryButton.isEnabled = false
            primaryButton.title = isReusingDatabase ? "Checking that database" : "Setting up Notion"
            let existing = isReusingDatabase
                ? existingField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
            if isReusingDatabase, existing?.isEmpty != false {
                showError("Pick a database above, or untick the box to create a new one.")
                Validation.flag(existingField)
                primaryButton.isEnabled = true
                primaryButton.title = primaryTitleForCourses()
                return
            }
            Task { @MainActor in
                do {
                    let result = try await NotionSetup.provision(
                        courses: self.settings.courses, existing: existing) { line in
                        DispatchQueue.main.async { self.logLabel.stringValue = line }
                    }
                    self.settings.notionDataSourceID = result.normalizedDataSourceId
                    self.settings.notionParentPageID = result.parentPageId ?? ""
                    self.settings.notionDatabaseURL = result.pageUrl
                    self.settings.hasCompletedOnboarding = true
                    self.settings.save()
                    self.show(.finish)
                } catch {
                    self.logLabel.stringValue = error.localizedDescription
                    self.primaryButton.isEnabled = true
                    self.primaryButton.title = "Try again"
                }
            }

        case .finish:
            settings.hasCompletedOnboarding = true
            settings.save()
            onFinish?(settings)
            window?.close()
        }
    }
}

extension OnboardingWindowController: NSTokenFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard !currentCourseNames().isEmpty else { return }
        clearError()
    }
}

/// One dependency, its state, and a button that fixes it.
private final class DependencyRow: NSView {
    private let glyph = NSImageView()
    private let spinner = NSProgressIndicator()
    private let title: NSTextField
    private let detail: NSTextField
    private let actionButton = NSButton()
    private var dependency: Dependency
    private let onInstall: (Dependency) -> Void

    init(dependency: Dependency, onInstall: @escaping (Dependency) -> Void) {
        self.dependency = dependency
        self.onInstall = onInstall
        title = Theme.label(dependency.title, font: Theme.Font.captionStrong)
        detail = Theme.label(dependency.detail, font: Theme.Font.caption, color: .tertiaryLabelColor, lines: 2)
        super.init(frame: .zero)

        glyph.translatesAutoresizingMaskIntoConstraints = false
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        actionButton.bezelStyle = .accessoryBarAction
        actionButton.controlSize = .small
        actionButton.target = self
        actionButton.action = #selector(tapped)

        let text = NSStackView(views: [title, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1

        let row = NSStackView(views: [glyph, spinner, text, NSView(), actionButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 9
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            glyph.widthAnchor.constraint(equalToConstant: 14),
            glyph.heightAnchor.constraint(equalToConstant: 14),
            spinner.widthAnchor.constraint(equalToConstant: 14),
        ])
        refresh(dependency)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func refresh(_ updated: Dependency) {
        dependency = updated
        let ok = updated.isSatisfied
        glyph.image = NSImage(
            systemSymbolName: ok ? "checkmark.circle.fill" : "circle.dashed",
            accessibilityDescription: ok ? "installed" : "missing")
        glyph.contentTintColor = ok ? .systemGreen : .secondaryLabelColor
        title.textColor = ok ? .secondaryLabelColor : .labelColor
        actionButton.isHidden = ok
        actionButton.title = updated.installCommand != nil ? "Install" : "How"
        if !ok, updated.installCommand == nil, let hint = updated.manualHint {
            detail.stringValue = hint
        }
    }

    func setWorking(_ working: Bool) {
        spinner.isHidden = !working
        glyph.isHidden = working
        actionButton.isEnabled = !working
        working ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
    }

    @objc private func tapped() {
        guard dependency.installCommand != nil else {
            if let hint = dependency.manualHint,
               let url = URL(string: hint.components(separatedBy: " ").first(where: {
                   $0.hasPrefix("https://")
               }) ?? "") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        onInstall(dependency)
    }
}
