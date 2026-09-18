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

        let buttons = NSStackView(views: [progressLabel, NSView(), secondaryButton, primaryButton])
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
        logLabel.stringValue = ""
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
            One per line, however you want them to appear in Notion. \
            For example: NLP CS 6120
            """
            coursesField.placeholderString = "NLP CS 6120"
            let field = NSTextField(wrappingLabelWithString: "")
            field.isHidden = true
            let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 440, height: 110))
            textView.font = Theme.Font.body
            textView.string = settings.courses.map(\.name).joined(separator: "\n")
            textView.isRichText = false
            let scroll = NSScrollView()
            scroll.documentView = textView
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            scroll.translatesAutoresizingMaskIntoConstraints = false
            scroll.heightAnchor.constraint(equalToConstant: 110).isActive = true
            content.addArrangedSubview(scroll)
            scroll.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
            courseTextView = textView

            if settings.destination == .notion {
                reuseCheckbox.title = "I already have a Notion database for these notes"
                reuseCheckbox.target = self
                reuseCheckbox.action = #selector(reuseToggled)
                reuseCheckbox.state = settings.notionDatabaseURL.isEmpty ? .off : .on
                existingField.placeholderString = "Paste the Notion database URL or its id"
                existingField.stringValue = settings.notionDatabaseURL
                content.addArrangedSubview(reuseCheckbox)
                content.addArrangedSubview(existingField)
                existingField.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
                reuseToggled()
            }
            primaryButton.title = primaryTitleForCourses()
            secondaryButton.title = "Back"

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

    private var courseTextView: NSTextView?
    private let reuseCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let existingField = NSTextField(string: "")

    private var isReusingDatabase: Bool {
        settings.destination == .notion && reuseCheckbox.state == .on
    }

    private func primaryTitleForCourses() -> String {
        guard settings.destination == .notion else { return "Continue" }
        return isReusingDatabase ? "Use this database" : "Create my Notion database"
    }

    @objc private func reuseToggled() {
        existingField.isEnabled = isReusingDatabase
        existingField.isHidden = !isReusingDatabase
        primaryButton.title = primaryTitleForCourses()
    }

    private func refreshDependencyRows() {
        dependencies = Dependency.all(for: settings.destination)
        for dependency in dependencies { rows[dependency.title]?.refresh(dependency) }
        let missing = dependencies.filter { $0.isRequired && !$0.isSatisfied }
        primaryButton.isEnabled = missing.isEmpty
        primaryButton.title = missing.isEmpty ? "Continue" : "Install what is missing first"
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
            let names = (courseTextView?.string ?? "")
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !names.isEmpty else {
                logLabel.stringValue = "Add at least one course."
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
                logLabel.stringValue = "Paste the database URL first, or untick the box to create a new one."
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
                    self.settings.notionDataSourceID = result.dataSourceId
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
