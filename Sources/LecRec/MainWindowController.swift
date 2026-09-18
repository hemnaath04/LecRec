import AppKit

/// The real app window: a sidebar of courses and a dashboard that says what you
/// have actually captured this term.
final class MainWindowController: NSWindowController {
    private var settings: Settings
    private var items: [LibraryItem] = []
    private var filter: String?          // course slug, nil means everything

    private let sidebar = NSStackView()
    private let contentStack = NSStackView()
    private let scroll = NSScrollView()

    private let greeting = Theme.label("", font: .systemFont(ofSize: 24, weight: .bold))
    private let highlight = Theme.label("", font: .systemFont(ofSize: 13), color: .secondaryLabelColor, lines: 2)
    private let recordButton = RecordButton(frame: .zero)
    private let recordCaption = Theme.label("", font: Theme.Font.caption, color: .tertiaryLabelColor)
    private let coursePopup = NSPopUpButton(frame: .zero, pullsDown: false)

    private let tiles: [String: StatTile] = [
        "lectures": StatTile(symbol: "books.vertical.fill", tint: .systemBlue),
        "hours": StatTile(symbol: "clock.fill", tint: .systemOrange),
        "words": StatTile(symbol: "text.alignleft", tint: .systemPurple),
        "coverage": StatTile(symbol: "waveform.badge.checkmark", tint: .systemGreen),
    ]
    private let tileOrder = ["lectures", "hours", "words", "coverage"]
    private var rowsContainer = NSStackView()
    private var sidebarButtons: [NSButton] = []

    var onRecordPressed: ((Course) -> Void)?
    var onOpenSettings: (() -> Void)?

    init(settings: Settings) {
        self.settings = settings
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "LecRec"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 820, height: 520)
        window.center()
        super.init(window: window)
        buildLayout()
        reload()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func apply(settings newSettings: Settings) {
        settings = newSettings
        reload()
    }

    // MARK: - Layout

    private func buildLayout() {
        let sidebarHost = NSVisualEffectView()
        sidebarHost.material = .sidebar
        sidebarHost.blendingMode = .behindWindow
        sidebarHost.state = .followsWindowActiveState
        sidebarHost.translatesAutoresizingMaskIntoConstraints = false

        sidebar.orientation = .vertical
        sidebar.alignment = .leading
        sidebar.spacing = 2
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebarHost.addSubview(sidebar)

        let settingsButton = NSButton(title: "  Settings", target: self, action: #selector(openSettings))
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settingsButton.imagePosition = .imageLeading
        settingsButton.bezelStyle = .accessoryBarAction
        settingsButton.isBordered = false
        settingsButton.alignment = .left
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        sidebarHost.addSubview(settingsButton)

        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: sidebarHost.topAnchor, constant: 52),
            sidebar.leadingAnchor.constraint(equalTo: sidebarHost.leadingAnchor, constant: 12),
            sidebar.trailingAnchor.constraint(equalTo: sidebarHost.trailingAnchor, constant: -12),
            settingsButton.leadingAnchor.constraint(equalTo: sidebarHost.leadingAnchor, constant: 16),
            settingsButton.bottomAnchor.constraint(equalTo: sidebarHost.bottomAnchor, constant: -16),
            sidebarHost.widthAnchor.constraint(equalToConstant: 208),
        ])

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 20
        contentStack.edgeInsets = NSEdgeInsets(top: 44, left: 30, bottom: 30, right: 30)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        buildHero()
        buildTiles()
        buildRecentList()

        let flipped = FlippedView()
        flipped.translatesAutoresizingMaskIntoConstraints = false
        flipped.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: flipped.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: flipped.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: flipped.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: flipped.bottomAnchor),
        ])
        scroll.documentView = flipped
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(sidebarHost)
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            sidebarHost.topAnchor.constraint(equalTo: container.topAnchor),
            sidebarHost.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            sidebarHost.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: sidebarHost.trailingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            flipped.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])
        window?.contentView = container
    }

    private func buildHero() {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerCurve = .continuous
        card.layer?.cornerRadius = 14
        card.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.10).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        recordButton.target = self
        recordButton.action = #selector(startRecording)
        recordButton.translatesAutoresizingMaskIntoConstraints = false

        coursePopup.target = self
        coursePopup.action = #selector(courseChanged)

        recordCaption.stringValue = "Recording keeps going if you close this window."

        let left = NSStackView(views: [greeting, highlight])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 5

        let right = NSStackView(views: [coursePopup, recordButton, recordCaption])
        right.orientation = .vertical
        right.alignment = .leading
        right.spacing = 7

        let row = NSStackView(views: [left, NSView(), right])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 24
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
            recordButton.widthAnchor.constraint(equalToConstant: 210),
            coursePopup.widthAnchor.constraint(equalToConstant: 210),
        ])
        contentStack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -60).isActive = true
    }

    private func buildTiles() {
        let row = NSStackView(views: tileOrder.compactMap { tiles[$0] })
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = 13
        contentStack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -60).isActive = true
    }

    private func buildRecentList() {
        let heading = Theme.label("Recent lectures", font: .systemFont(ofSize: 15, weight: .semibold))
        contentStack.addArrangedSubview(heading)

        rowsContainer.orientation = .vertical
        rowsContainer.alignment = .leading
        rowsContainer.spacing = 6
        contentStack.addArrangedSubview(rowsContainer)
        rowsContainer.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -60).isActive = true
    }

    // MARK: - Data

    func reload() {
        items = Library.scan(settings: settings)
        rebuildSidebar()
        rebuildCoursePopup()

        let visible = filter.map { slug in items.filter { $0.course == slug } } ?? items
        let stats = Library.stats(for: visible)

        greeting.stringValue = Self.greetingText()
        highlight.stringValue = Library.highlight(items: visible, stats: stats)
            ?? "No lectures captured yet. Press record when your next class starts."

        tiles["lectures"]?.set(value: "\(stats.lectureCount)",
                               caption: stats.lectureCount == 1 ? "lecture" : "lectures")
        if stats.totalDuration >= 3600 {
            tiles["hours"]?.set(value: String(format: "%.1f", stats.totalHours),
                                caption: "hours recorded")
        } else if stats.totalDuration > 0 {
            let minutes = max(1, Int((stats.totalDuration / 60).rounded()))
            tiles["hours"]?.set(value: "\(minutes)",
                                caption: minutes == 1 ? "minute recorded" : "minutes recorded")
        } else {
            tiles["hours"]?.set(value: "0", caption: "nothing recorded yet")
        }
        tiles["words"]?.set(value: Library.formatted(stats.totalWords), caption: "words in notes")
        if let coverage = stats.averageCoverage {
            tiles["coverage"]?.set(value: "\(Int((coverage * 100).rounded()))%", caption: "average coverage")
        } else {
            tiles["coverage"]?.set(value: "n/a", caption: "average coverage")
        }

        rowsContainer.arrangedSubviews.forEach {
            rowsContainer.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        if visible.isEmpty {
            let empty = Theme.label("Nothing here yet.", font: Theme.Font.body, color: .tertiaryLabelColor)
            rowsContainer.addArrangedSubview(empty)
        }
        for item in visible.prefix(12) {
            let row = LectureRow(frame: .zero)
            row.configure(item)
            rowsContainer.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rowsContainer.widthAnchor).isActive = true
        }
    }

    private func rebuildSidebar() {
        sidebar.arrangedSubviews.forEach {
            sidebar.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        sidebarButtons = []

        let counts = Dictionary(grouping: items, by: \.course).mapValues(\.count)
        addSidebarItem(title: "All lectures", symbol: "square.grid.2x2",
                       count: items.count, slug: nil)

        if !settings.courses.isEmpty {
            let header = Theme.label("COURSES", font: .systemFont(ofSize: 10, weight: .semibold),
                                     color: .tertiaryLabelColor)
            let spacer = NSView()
            spacer.heightAnchor.constraint(equalToConstant: 10).isActive = true
            sidebar.addArrangedSubview(spacer)
            sidebar.addArrangedSubview(header)
        }
        for course in settings.courses {
            addSidebarItem(title: course.name, symbol: "book.closed",
                           count: counts[course.slug] ?? 0, slug: course.slug)
        }
    }

    private func addSidebarItem(title: String, symbol: String, count: Int, slug: String?) {
        let button = NSButton(title: "  \(title)", target: self, action: #selector(sidebarTapped(_:)))
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.alignment = .left
        button.font = .systemFont(ofSize: 12.5, weight: filter == slug ? .semibold : .regular)
        button.contentTintColor = filter == slug ? .controlAccentColor : .labelColor
        button.identifier = NSUserInterfaceItemIdentifier(slug ?? "")
        button.toolTip = count == 1 ? "1 lecture" : "\(count) lectures"
        sidebar.addArrangedSubview(button)
        button.widthAnchor.constraint(equalTo: sidebar.widthAnchor).isActive = true
        sidebarButtons.append(button)
    }

    private func rebuildCoursePopup() {
        coursePopup.removeAllItems()
        coursePopup.addItems(withTitles: settings.courses.map(\.name))
        if let index = settings.courses.firstIndex(where: { $0.slug == settings.selectedCourseSlug }) {
            coursePopup.selectItem(at: index)
        }
        coursePopup.isEnabled = !settings.courses.isEmpty
    }

    // MARK: - Actions

    @objc private func sidebarTapped(_ sender: NSButton) {
        let slug = sender.identifier?.rawValue ?? ""
        filter = slug.isEmpty ? nil : slug
        reload()
    }

    @objc private func courseChanged() {
        let index = coursePopup.indexOfSelectedItem
        guard index >= 0, index < settings.courses.count else { return }
        settings.selectedCourseSlug = settings.courses[index].slug
        settings.save()
    }

    @objc private func openSettings() { onOpenSettings?() }

    @objc private func startRecording() {
        guard let course = settings.selectedCourse else { return }
        onRecordPressed?(course)
    }

    /// Reflects whatever the menu bar popover is doing, so the two never disagree.
    func setRecording(_ recording: Bool) {
        recordButton.apply(recording ? .recording : .idle)
        recordCaption.stringValue = recording
            ? "Recording. Use the menu bar icon to stop."
            : "Recording keeps going if you close this window."
    }

    private static func greetingText() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Late one"
        }
    }
}

/// Top-down coordinates so a scrolled stack starts at the top rather than the bottom.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
