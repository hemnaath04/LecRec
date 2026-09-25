import AppKit

/// The main window, implemented from the Paper file "LecRec" / artboard Dashboard.
///
/// The design's central idea is scale contrast: one number large enough to read
/// from across the room, everything else deliberately quiet. Four equal stat
/// tiles were dropped in review for being grid-like sameness.
final class MainWindowController: NSWindowController {
    private var settings: Settings
    private var items: [LibraryItem] = []
    private var filter: String?

    private let sidebar = NSStackView()
    private let content = NSStackView()
    private let scroll = NSScrollView()

    private let eyebrowLabel = Theme.label("", font: Theme.Font.rowMeta, color: Theme.Palette.faint)
    private let heroNumber = Theme.label("", font: Theme.Font.hero, color: Theme.Palette.ink, tracking: -2.2)
    private let heroUnit = Theme.label("", font: Theme.Font.heroUnit, color: Theme.Palette.muted)
    private let summaryLabel = Theme.label("", font: Theme.Font.rowMeta, color: Theme.Palette.faint, lines: 2)
    private let recordButton = RecordButton(frame: .zero)
    private let recordCaption = Theme.label("", font: Theme.Font.caption, color: Theme.Palette.dim)
    private let courseChip = CourseChip(frame: .zero)
    private let listRange = Theme.label("", font: Theme.Font.rowMeta, color: Theme.Palette.faint)
    private var rows = NSStackView()
    private let pendingCard = PendingCard(frame: .zero)
    private let progress = ProgressStrip(frame: .zero)

    var onRecordPressed: ((Course) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenLive: (() -> Void)?

    init(settings: Settings) {
        self.settings = settings
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "LecRec"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isOpaque = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 900, height: 560)
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
        // The window is translucent: vibrancy takes the desktop behind it, and the
        // canvas view paints only the tint and bloom on top.
        let vibrancy = NSVisualEffectView()
        vibrancy.material = .underWindowBackground
        vibrancy.blendingMode = .behindWindow
        vibrancy.state = .followsWindowActiveState
        vibrancy.translatesAutoresizingMaskIntoConstraints = false

        let container = CanvasBackgroundView()
        container.translatesAutoresizingMaskIntoConstraints = false
        vibrancy.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: vibrancy.topAnchor),
            container.bottomAnchor.constraint(equalTo: vibrancy.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: vibrancy.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: vibrancy.trailingAnchor),
        ])

        let sidebarHost = SidebarBackgroundView()
        sidebarHost.translatesAutoresizingMaskIntoConstraints = false

        sidebar.orientation = .vertical
        sidebar.alignment = .leading
        sidebar.spacing = 1
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebarHost.addSubview(sidebar)

        let settingsButton = NSButton(title: "Settings", target: self, action: #selector(openSettings))
        settingsButton.font = Theme.Font.sidebarItem
        settingsButton.contentTintColor = Theme.Palette.faint
        settingsButton.bezelStyle = .accessoryBarAction
        settingsButton.isBordered = false
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        sidebarHost.addSubview(settingsButton)

        NSLayoutConstraint.activate([
            sidebarHost.widthAnchor.constraint(equalToConstant: 236),
            sidebar.topAnchor.constraint(equalTo: sidebarHost.topAnchor, constant: 30),
            sidebar.leadingAnchor.constraint(equalTo: sidebarHost.leadingAnchor),
            sidebar.trailingAnchor.constraint(equalTo: sidebarHost.trailingAnchor),
            settingsButton.leadingAnchor.constraint(equalTo: sidebarHost.leadingAnchor, constant: 20),
            settingsButton.bottomAnchor.constraint(equalTo: sidebarHost.bottomAnchor, constant: -18),
        ])

        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 0
        content.edgeInsets = NSEdgeInsets(top: 52, left: 56, bottom: 40, right: 56)
        content.translatesAutoresizingMaskIntoConstraints = false
        buildHero()
        buildPendingAndProgress()
        buildList()

        let flipped = FlippedView()
        flipped.translatesAutoresizingMaskIntoConstraints = false
        flipped.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: flipped.topAnchor),
            content.leadingAnchor.constraint(equalTo: flipped.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: flipped.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: flipped.bottomAnchor),
        ])
        scroll.documentView = flipped
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

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
        window?.contentView = vibrancy
    }

    private func buildHero() {
        let heroRow = NSStackView(views: [heroNumber, heroUnit])
        heroRow.orientation = .horizontal
        heroRow.alignment = .firstBaseline
        heroRow.spacing = 12

        let left = NSStackView(views: [eyebrowLabel, heroRow, summaryLabel])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 4
        left.setCustomSpacing(8, after: heroRow)

        courseChip.onSelect = { [weak self] slug in
            guard let self else { return }
            self.settings.selectedCourseSlug = slug
            self.settings.save()
        }
        recordButton.target = self
        recordButton.action = #selector(startRecording)
        recordCaption.stringValue = "Keeps running if you close this window"

        let right = NSStackView(views: [courseChip, recordButton, recordCaption])
        right.orientation = .vertical
        right.alignment = .trailing
        right.spacing = 9

        let hero = NSStackView(views: [left, NSView(), right])
        hero.orientation = .horizontal
        hero.alignment = .bottom
        hero.spacing = 28
        content.addArrangedSubview(hero)
        content.setCustomSpacing(46, after: hero)

        NSLayoutConstraint.activate([
            hero.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -112),
            recordButton.widthAnchor.constraint(equalToConstant: 196),
            courseChip.widthAnchor.constraint(equalToConstant: 196),
            summaryLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
        ])
    }

    /// The write-up handoff and the live progress bar, both hidden until they
    /// have something to say, so a quiet dashboard stays quiet.
    private func buildPendingAndProgress() {
        pendingCard.onStart = { [weak self] item in
            guard let self else { return }
            do {
                try ProcessingCenter.shared.startWriteUp(item, settings: self.settings)
            } catch {
                self.progress.update(stage: "Busy", detail: error.localizedDescription, fraction: 0)
            }
        }
        pendingCard.onChanged = { [weak self] in self?.reload() }

        content.addArrangedSubview(pendingCard)
        content.setCustomSpacing(16, after: pendingCard)
        let openLive = NSClickGestureRecognizer(target: self, action: #selector(openLiveTapped))
        progress.addGestureRecognizer(openLive)
        progress.toolTip = "Open the live monitor"
        content.addArrangedSubview(progress)
        content.setCustomSpacing(30, after: progress)

        NSLayoutConstraint.activate([
            pendingCard.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -112),
            progress.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -112),
        ])
        pendingCard.isHidden = true
        progress.isHidden = true

        // One observer for the whole window: the bar follows whatever is running.
        ProcessingCenter.shared.observe("dashboard") { [weak self] update in
            guard let self else { return }
            if let update {
                self.progress.isHidden = false
                self.progress.update(stage: update.stage.rawValue,
                                     detail: update.detail, fraction: update.fraction)
                self.pendingCard.isHidden = true
            } else {
                self.progress.isHidden = true
                self.reload()
            }
        }
        ProcessingCenter.shared.onComplete("dashboard") { [weak self] _, _ in
            self?.reload()
        }
    }

    private func buildList() {
        let heading = Theme.label("Recent lectures", font: Theme.Font.sectionTitle, color: Theme.Palette.ink)
        let header = NSStackView(views: [heading, NSView(), listRange])
        header.orientation = .horizontal
        header.alignment = .lastBaseline
        content.addArrangedSubview(header)
        content.setCustomSpacing(6, after: header)

        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        content.addArrangedSubview(rows)

        NSLayoutConstraint.activate([
            header.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -112),
            rows.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -112),
        ])
    }

    // MARK: - Data

    func reload() {
        items = Library.scan(settings: settings)
        rebuildSidebar()
        rebuildCoursePopup()

        let visible = filter.map { slug in items.filter { $0.course == slug } } ?? items
        let stats = Library.stats(for: visible)

        eyebrowLabel.stringValue = Self.termLabel()
        applyHero(stats: stats, visible: visible)

        if let waiting = PendingStore.first, !ProcessingCenter.shared.isRunning {
            pendingCard.configure(waiting)
            pendingCard.isHidden = false
        } else {
            pendingCard.isHidden = true
        }

        listRange.stringValue = visible.isEmpty ? "" : "\(visible.count) in the library"
        rows.arrangedSubviews.forEach {
            rows.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        if visible.isEmpty {
            let empty = Theme.label("Nothing recorded yet. Press record when your next class starts.",
                                    font: Theme.Font.rowMeta, color: Theme.Palette.dim)
            rows.addArrangedSubview(empty)
            return
        }
        for (index, item) in visible.prefix(14).enumerated() {
            let row = LectureRow(frame: .zero)
            row.configure(item, accent: accent(for: item.course), showHairline: index > 0)
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
    }

    /// The hero states the most meaningful number available, which changes as the
    /// library fills: hours once there are any, otherwise the lecture count.
    private func applyHero(stats: LibraryStats, visible: [LibraryItem]) {
        if stats.totalDuration >= 3600 {
            heroNumber.stringValue = String(format: "%.1f", stats.totalHours)
            heroUnit.stringValue = "hours of lectures kept"
        } else if stats.totalDuration > 0 {
            let minutes = max(1, Int((stats.totalDuration / 60).rounded()))
            heroNumber.stringValue = "\(minutes)"
            heroUnit.stringValue = minutes == 1
                ? "minute of lectures kept" : "minutes of lectures kept"
        } else {
            heroNumber.stringValue = "\(stats.lectureCount)"
            heroUnit.stringValue = stats.lectureCount == 1 ? "lecture in the library" : "lectures in the library"
        }

        var bits: [String] = []
        if stats.lectureCount > 0 {
            bits.append("\(stats.lectureCount) lecture\(stats.lectureCount == 1 ? "" : "s")")
        }
        if stats.totalWords > 0 { bits.append("\(Library.formatted(stats.totalWords)) words written") }
        if let coverage = stats.averageCoverage {
            bits.append("\(Int((coverage * 100).rounded()))% of every recording transcribed")
        }
        let missing = visible.filter { !$0.hasNote }.count
        if missing > 0 { bits.append("\(missing) still to process") }
        summaryLabel.stringValue = bits.isEmpty
            ? "Press record when class starts and LecRec does the rest."
            : bits.joined(separator: ", ") + "."
    }

    private func rebuildSidebar() {
        sidebar.arrangedSubviews.forEach {
            sidebar.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let brand = NSStackView(views: [
            Theme.appIcon(size: 22),
            Theme.label("LecRec", font: Theme.Font.of(13.5, .semibold),
                        color: Theme.Palette.ink),
        ])
        brand.orientation = .horizontal
        brand.spacing = 9
        brand.alignment = .centerY
        addToSidebar(brand, insets: 22, spacingAfter: 28)

        addToSidebar(Theme.eyebrow("Library"), insets: 22, spacingAfter: 8)
        addSidebarRow(title: "All lectures", count: items.count, accent: nil, slug: nil)

        guard !settings.courses.isEmpty else { return }
        addToSidebar(Theme.eyebrow("Courses"), insets: 22, spacingAfter: 8, spacingBefore: 22)
        let counts = Dictionary(grouping: items, by: \.course).mapValues(\.count)
        for course in settings.courses {
            addSidebarRow(title: course.name, count: counts[course.slug] ?? 0,
                          accent: accent(for: course.slug), slug: course.slug)
        }
    }

    private func addToSidebar(_ view: NSView, insets: CGFloat,
                              spacingAfter: CGFloat, spacingBefore: CGFloat = 0) {
        if spacingBefore > 0 {
            let spacer = NSView()
            spacer.translatesAutoresizingMaskIntoConstraints = false
            spacer.heightAnchor.constraint(equalToConstant: spacingBefore).isActive = true
            sidebar.addArrangedSubview(spacer)
        }
        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        view.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: insets),
            view.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor, constant: -insets),
            view.topAnchor.constraint(equalTo: holder.topAnchor),
            view.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
        ])
        sidebar.addArrangedSubview(holder)
        holder.widthAnchor.constraint(equalTo: sidebar.widthAnchor).isActive = true
        sidebar.setCustomSpacing(spacingAfter, after: holder)
    }

    private func addSidebarRow(title: String, count: Int, accent: NSColor?, slug: String?) {
        let isSelected = filter == slug
        let subtitle = count == 1 ? "1 lecture" : "\(count) lectures"
        let item = SidebarItem(title: title, subtitle: subtitle, accent: accent,
                               selected: isSelected,
                               actionTitle: slug == nil ? nil : "RECORD +")
        item.onSelect = { [weak self] in
            self?.filter = slug
            self?.reload()
        }
        item.onAction = { [weak self] in
            guard let self, let slug else { return }
            self.settings.selectedCourseSlug = slug
            self.settings.save()
            self.rebuildCoursePopup()
            self.startRecording()
        }
        sidebar.addArrangedSubview(item)
        item.widthAnchor.constraint(equalTo: sidebar.widthAnchor).isActive = true
    }

    private func accent(for slug: String) -> NSColor {
        let index = settings.courses.firstIndex { $0.slug == slug } ?? abs(slug.hashValue)
        return Theme.Palette.courseAccents[index % Theme.Palette.courseAccents.count]
    }

    private func rebuildCoursePopup() {
        courseChip.configure(courses: settings.courses,
                             selected: settings.selectedCourseSlug) { [weak self] slug in
            self?.accent(for: slug) ?? Theme.Palette.faint
        }
    }

    // MARK: - Actions

    @objc private func openSettings() { onOpenSettings?() }

    @objc private func openLiveTapped() { onOpenLive?() }

    @objc private func startRecording() {
        guard let course = settings.selectedCourse else { return }
        onRecordPressed?(course)
    }

    func setRecording(_ recording: Bool) {
        recordButton.apply(recording ? .recording : .idle)
        recordCaption.stringValue = recording
            ? "Recording. Use the menu bar icon to stop."
            : "Keeps running if you close this window"
    }

    private static func termLabel() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: Date())
    }
}

/// Top-down coordinates so a scrolled stack starts at the top.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
