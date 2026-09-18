import AppKit

/// A text field with real padding.
///
/// Turning off `isBordered` to get a custom surface also throws away the inset
/// AppKit normally applies, so text and placeholder sit flush against the edge.
/// There is no padding property on NSTextField, so the cell has to do it, and it
/// must inset the editing and selection rects too or the caret jumps on focus.
final class PaddedTextFieldCell: NSTextFieldCell {
    var padding = NSSize(width: 11, height: 0)

    private func inset(_ rect: NSRect) -> NSRect {
        var result = rect.insetBy(dx: padding.width, dy: padding.height)
        // Vertically centre a single line rather than top-aligning it.
        let height = (font?.boundingRectForFont.height ?? rect.height).rounded(.up)
        if height < result.height {
            result.origin.y += (result.height - height) / 2
            result.size.height = height
        }
        return result
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        super.drawingRect(forBounds: inset(rect))
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView,
                       editor: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: inset(rect), in: controlView,
                   editor: editor, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView,
                         editor: NSText, delegate: Any?, start: Int, length: Int) {
        super.select(withFrame: inset(rect), in: controlView,
                     editor: editor, delegate: delegate, start: start, length: length)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: inset(cellFrame), in: controlView)
    }
}

final class PaddedTextField: NSTextField {
    override class var cellClass: AnyClass? {
        get { PaddedTextFieldCell.self }
        set { super.cellClass = newValue }
    }

    /// Styles the field as the surface chip used everywhere else in the app.
    func applyChipStyle(placeholder: String) {
        placeholderString = placeholder
        font = Theme.Font.body
        isBordered = false
        drawsBackground = false          // the layer paints it, so the cell cannot clip it
        textColor = Theme.Palette.ink
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = Theme.Palette.surface.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = Theme.Palette.stroke.cgColor
        (cell as? PaddedTextFieldCell)?.padding = NSSize(width: 11, height: 0)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { layer?.borderColor = Theme.Palette.record.withAlphaComponent(0.7).cgColor }
        return ok
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        layer?.borderColor = Theme.Palette.stroke.cgColor
    }
}
