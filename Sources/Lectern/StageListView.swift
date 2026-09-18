import AppKit

/// The five pipeline steps as a checklist. Processing a 75 minute lecture takes
/// minutes, so the user needs to see which step is running and that earlier
/// steps really finished.
final class StageListView: NSView {
    private enum RowState {
        case pending, active, done, failed
    }

    private final class Row: NSView {
        let glyph = NSImageView()
        let spinner = NSProgressIndicator()
        let title: NSTextField
        let detail: NSTextField

        init(title titleText: String) {
            title = Theme.label(titleText, font: Theme.Font.stage, color: .tertiaryLabelColor)
            detail = Theme.label("", font: Theme.Font.caption, color: .tertiaryLabelColor, lines: 2)
            super.init(frame: .zero)

            glyph.imageScaling = .scaleProportionallyUpOrDown
            glyph.translatesAutoresizingMaskIntoConstraints = false
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.isDisplayedWhenStopped = false
            spinner.translatesAutoresizingMaskIntoConstraints = false

            let text = NSStackView(views: [title, detail])
            text.orientation = .vertical
            text.alignment = .leading
            text.spacing = 1

            let row = NSStackView(views: [glyph, spinner, text])
            row.orientation = .horizontal
            row.alignment = .firstBaseline
            row.spacing = 7
            row.translatesAutoresizingMaskIntoConstraints = false
            addSubview(row)

            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: topAnchor),
                row.leadingAnchor.constraint(equalTo: leadingAnchor),
                row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
                row.bottomAnchor.constraint(equalTo: bottomAnchor),
                glyph.widthAnchor.constraint(equalToConstant: 13),
                glyph.heightAnchor.constraint(equalToConstant: 13),
                spinner.widthAnchor.constraint(equalToConstant: 13),
            ])
            detail.isHidden = true
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        func apply(_ state: RowState) {
            switch state {
            case .pending:
                spinner.stopAnimation(nil); spinner.isHidden = true; glyph.isHidden = false
                glyph.image = NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "pending")
                glyph.contentTintColor = .quaternaryLabelColor
                title.textColor = .tertiaryLabelColor
            case .active:
                glyph.isHidden = true; spinner.isHidden = false; spinner.startAnimation(nil)
                title.textColor = .labelColor
            case .done:
                spinner.stopAnimation(nil); spinner.isHidden = true; glyph.isHidden = false
                glyph.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "done")
                glyph.contentTintColor = .systemGreen
                title.textColor = .secondaryLabelColor
            case .failed:
                spinner.stopAnimation(nil); spinner.isHidden = true; glyph.isHidden = false
                glyph.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: "failed")
                glyph.contentTintColor = .systemRed
                title.textColor = .labelColor
            }
        }

        func show(detailText: String?) {
            guard let detailText, !detailText.isEmpty else {
                detail.isHidden = true
                return
            }
            detail.stringValue = detailText
            detail.isHidden = false
        }
    }

    private let order: [PipelineStage] = [.cleaning, .transcribing, .checking,
                                          .recalling, .reasoning, .publishing]
    private var rows: [PipelineStage: Row] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        var views: [NSView] = []
        for stage in order {
            let row = Row(title: stage.rawValue)
            row.apply(.pending)
            rows[stage] = row
            views.append(row)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func reset() {
        for stage in order {
            rows[stage]?.apply(.pending)
            rows[stage]?.show(detailText: nil)
        }
    }

    /// Marks everything before `stage` done, `stage` active, and shows its detail.
    func advance(to stage: PipelineStage, detail: String?) {
        guard let index = order.firstIndex(of: stage) else {
            if stage == .done { order.forEach { rows[$0]?.apply(.done) } }
            return
        }
        for (position, key) in order.enumerated() {
            if position < index {
                rows[key]?.apply(.done)
            } else if position == index {
                rows[key]?.apply(.active)
                rows[key]?.show(detailText: detail)
            } else {
                rows[key]?.apply(.pending)
            }
        }
    }

    func markFailure(at stage: PipelineStage, message: String) {
        guard let index = order.firstIndex(of: stage) else { return }
        for (position, key) in order.enumerated() where position <= index {
            rows[key]?.apply(position == index ? .failed : .done)
        }
        rows[stage]?.show(detailText: message)
    }

    func finish(publishedTo destination: String) {
        order.forEach { rows[$0]?.apply(.done) }
        rows[.publishing]?.show(detailText: destination)
    }
}
