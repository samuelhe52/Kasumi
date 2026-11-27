#if os(macOS)
import AppKit
import KasumiMarkdown

@MainActor final class ReaderCanvas: NSView, NSUserInterfaceValidations {
    weak var owner: MarkdownReaderView?
    var preview: ReaderViewportBitmap?
    private(set) var selection: NSRange?
    private var selectionAnchor: Int?
    private var stringCache: NSString?
    private var lineStarts: [Int]?
    private var accessibilityLinks: [ReaderAccessibilityLink]?
    private var pointerTracking: NSTrackingArea?
    private var drag: Drag?
    private var autoscrollTask: Task<Void, Never>?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    deinit { autoscrollTask?.cancel() }

    private enum Granularity { case character, word, paragraph }
    private struct Drag {
        let origin: CGPoint
        let base: NSRange
        let granularity: Granularity
        let link: URL?
        let tableID: Int?
        var location: CGPoint
        var moved = false
    }

    var draggedTableID: Int? { drag?.tableID }

    func replaceDocument() {
        endDrag()
        selection = nil
        selectionAnchor = nil
        stringCache = nil
        lineStarts = nil
        accessibilityLinks = nil
        preview = nil
        needsDisplay = true
    }

    var semanticString: NSString {
        if let stringCache { return stringCache }
        guard let rendered = owner?.rendered else { return "" }
        let string = rendered.readerSemanticText as NSString
        stringCache = string
        return string
    }

    func setSelection(_ range: NSRange?, anchoredAt anchor: Int? = nil) {
        selectionAnchor = anchor ?? range?.location
        guard selection != range else { return }
        selection = range
        owner?.find.finder.cancelFindIndicator()
        owner?.setHighlightsNeedDisplay()
        NSAccessibility.post(element: self, notification: .selectedTextChanged)
    }

    func invalidateImage(in rect: CGRect) {
        if preview?.rect.intersects(rect) == true { preview = nil }
        setNeedsDisplay(rect.insetBy(dx: -1, dy: -1))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(owner?.rendered?.backgroundColor ?? NSColor.textBackgroundColor.cgColor)
        context.fill(dirtyRect)
        guard let owner, let rendered = owner.rendered else { return }
        let highlights = owner.highlights(in: dirtyRect)
        if highlights.isEmpty, let preview, preview.rect.intersects(dirtyRect) {
            context.saveGState()
            context.clip(to: preview.rect)
            context.translateBy(x: preview.rect.minX, y: preview.rect.minY + preview.pixelSize.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(preview.image, in: CGRect(origin: .zero, size: preview.pixelSize))
            context.restoreGState()
            if !preview.rect.contains(dirtyRect) {
                context.saveGState()
                context.addRect(dirtyRect)
                context.addRect(preview.rect.intersection(dirtyRect))
                context.clip(using: .evenOdd)
                rendered.draw(in: context, rect: dirtyRect, excludingScrollableTables: true)
                context.restoreGState()
            }
        } else {
            rendered.draw(in: context, rect: dirtyRect, excludingScrollableTables: true, highlights: highlights)
        }
    }

    private func documentPoint(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    private func offset(at point: CGPoint, clamping: Bool = false) -> Int? {
        guard let owner, let rendered = owner.rendered else { return nil }
        var point = point
        if clamping {
            let view = owner.viewport
            point.x = min(max(view.minX, point.x), view.maxX - 0.01)
            point.y = min(max(view.minY, point.y), view.maxY - 0.01)
            if let table = owner.scrollableTable(near: point) {
                point.x = min(max(table.frame.minX, point.x), table.frame.maxX - 0.01)
            }
        }
        return rendered.offset(
            from: rendered.documentRange.lowerBound, to: rendered.position(closestTo: owner.semanticPoint(point)))
    }

    private func link(at point: CGPoint) -> URL? {
        guard let owner, owner.viewport.contains(point) else { return nil }
        return owner.rendered?.link(at: owner.semanticPoint(point))
    }

    override func quickLook(with event: NSEvent) {
        if !showLookup(at: documentPoint(event)) { super.quickLook(with: event) }
    }

    override func pressureChange(with event: NSEvent) {
        // The global Look Up setting is 1 for Force Click, not three-finger tap or off.
        if event.stage == 2, drag?.moved == false,
            UserDefaults.standard.integer(forKey: "com.apple.trackpad.forceClick") == 1,
            showLookup(at: documentPoint(event))
        { return }
        super.pressureChange(with: event)
    }

    private func showLookup(at point: CGPoint) -> Bool {
        guard let target = lookupTarget(at: point) else { return false }
        // A force click can follow mouseDown. Don't open the link on mouseUp.
        endDrag()
        showDefinition(for: target.text, at: target.baseline)
        return true
    }

    /// The word under `point` in its rendered font, with its visible baseline
    /// origin and selection rect in canvas coordinates.
    func lookupTarget(at point: CGPoint) -> (text: NSAttributedString, baseline: CGPoint, rect: CGRect)? {
        guard let owner, owner.isActive, owner.viewport.contains(point), let rendered = owner.rendered else { return nil }
        let semantic = owner.semanticPoint(point)
        let position = rendered.position(closestTo: semantic)
        func target(at position: KasumiMarkdown.TextPosition)
            -> (text: NSAttributedString, baseline: CGPoint, rect: CGRect)?
        {
            guard let word = rendered.wordRange(at: position),
                let rect = rendered.selectionRects(for: word).lazy.map({ owner.visibleSelectionRect($0) })
                    .first(where: { $0.contains(point) })
            else { return nil }
            let string = rendered.text(in: word)
            guard let style = rendered.textStyle(at: word) else {
                let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
                return (
                    NSAttributedString(string: string, attributes: [.font: font]),
                    CGPoint(x: rect.minX, y: rect.maxY + font.descender), rect)
            }
            // Layout coordinates are shifted by the horizontal table scroll offset.
            let baseline = CGPoint(x: style.baseline.x - (semantic.x - point.x), y: style.baseline.y)
            return (NSAttributedString(string: string, attributes: [.font: style.font as NSFont]), baseline, rect)
        }
        if let hit = target(at: position) { return hit }
        // The closest caret may be just after the last glyph of the word.
        guard let previous = rendered.position(from: position, offset: -1) else { return nil }
        return target(at: previous)
    }

    override func mouseDown(with event: NSEvent) {
        guard let owner, owner.isActive, let rendered = owner.rendered else { return }
        window?.makeFirstResponder(self)
        endDrag()
        owner.userWillScroll()
        owner.find.clearSelection()
        let point = documentPoint(event)
        guard let clicked = offset(at: point) else { return }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let granularity: Granularity = event.clickCount >= 3 ? .paragraph : event.clickCount == 2 ? .word : .character
        let extending = modifiers.contains(.shift)
        let clickedRange = range(at: clicked, granularity: granularity, in: rendered)
        let fixed = extending ? (selectionAnchor ?? selection?.location ?? clicked) : clickedRange.location
        let base = extending ? NSRange(location: fixed, length: 0) : clickedRange
        let selected = extending ? Self.span(from: fixed, to: clicked < fixed ? clickedRange.location : NSMaxRange(clickedRange))
            : clickedRange
        setSelection(selected, anchoredAt: fixed)
        drag = Drag(
            origin: event.locationInWindow, base: base, granularity: granularity,
            link: granularity == .character && !extending ? link(at: point) : nil,
            tableID: owner.table(at: point)?.id,
            location: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        guard var drag else { return }
        drag.location = event.locationInWindow
        if abs(drag.location.x - drag.origin.x) > 3 || abs(drag.location.y - drag.origin.y) > 3 { drag.moved = true }
        self.drag = drag
        guard drag.moved else { return }
        advanceDrag()
        guard autoscrollTask == nil else { return }
        autoscrollTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
                guard let self, self.drag?.moved == true else { return }
                self.advanceDrag(onlyAfterScroll: true)
            }
        }
    }

    private func advanceDrag(onlyAfterScroll: Bool = false) {
        guard let drag, let owner, let rendered = owner.rendered else { return }
        var point = convert(drag.location, from: nil)
        let moved = owner.scrollForDrag(to: point)
        if onlyAfterScroll && !moved { return }
        if moved { point = convert(drag.location, from: nil) }
        guard let offset = offset(at: point, clamping: true) else { return }
        let target = range(at: offset, granularity: drag.granularity, in: rendered)
        let first = min(drag.base.location, target.location)
        let last = max(NSMaxRange(drag.base), NSMaxRange(target))
        let fixed = target.location < drag.base.location ? NSMaxRange(drag.base) : drag.base.location
        setSelection(NSRange(location: first, length: last - first), anchoredAt: fixed)
    }

    override func mouseUp(with event: NSEvent) {
        guard let drag else { return }
        endDrag()
        guard !drag.moved, let url = drag.link, link(at: documentPoint(event)) == url else { return }
        owner?.activateLink(url)
    }

    func endDrag() {
        drag = nil
        autoscrollTask?.cancel()
        autoscrollTask = nil
    }

    private func range(at offset: Int, granularity: Granularity, in rendered: RenderedDocument) -> NSRange {
        switch granularity {
        case .character: return NSRange(location: offset, length: 0)
        case .word:
            if let position = rendered.position(from: rendered.documentRange.lowerBound, offset: offset),
                let word = rendered.wordRange(at: position), let range = rendered.readerSemanticRange(for: word)
            { return range }
            let string = semanticString
            if offset < string.length { return string.rangeOfComposedCharacterSequence(at: offset) }
            return NSRange(location: offset, length: 0)
        case .paragraph:
            let string = semanticString
            return string.paragraphRange(for: NSRange(location: min(offset, string.length), length: 0))
        }
    }

    private static func span(from first: Int, to last: Int) -> NSRange {
        NSRange(location: min(first, last), length: abs(last - first))
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.shift) { interpretKeyEvents([event]) }
        else { super.keyDown(with: event) }
    }

    override func moveLeftAndModifySelection(_ sender: Any?) { extendSelection(horizontal: -1) }
    override func moveRightAndModifySelection(_ sender: Any?) { extendSelection(horizontal: 1) }
    override func moveBackwardAndModifySelection(_ sender: Any?) { extendSelection(horizontal: -1) }
    override func moveForwardAndModifySelection(_ sender: Any?) { extendSelection(horizontal: 1) }
    override func moveUpAndModifySelection(_ sender: Any?) { extendSelection(vertical: -1) }
    override func moveDownAndModifySelection(_ sender: Any?) { extendSelection(vertical: 1) }

    private func extendSelection(horizontal: Int = 0, vertical: CGFloat = 0) {
        guard let owner, let rendered = owner.rendered else { return }
        owner.find.clearSelection()
        let current = selection ?? NSRange(location: 0, length: 0)
        let fixed = selectionAnchor ?? current.location
        let moving = fixed == current.location ? NSMaxRange(current) : current.location
        let next: Int
        if horizontal != 0 {
            let string = semanticString
            if horizontal < 0, moving > 0 {
                next = string.rangeOfComposedCharacterSequence(at: moving - 1).location
            } else if horizontal > 0, moving < string.length {
                next = NSMaxRange(string.rangeOfComposedCharacterSequence(at: moving))
            } else { return }
        } else {
            guard let position = rendered.position(from: rendered.documentRange.lowerBound, offset: moving) else { return }
            let caret = rendered.caretRect(for: position)
            let point = CGPoint(x: caret.midX, y: caret.midY + vertical * max(caret.height, 1))
            guard let offset = rendered.offset(from: rendered.documentRange.lowerBound, to: rendered.position(closestTo: point))
            else { return }
            next = offset
        }
        setSelection(Self.span(from: fixed, to: next), anchoredAt: fixed)
        owner.revealText(NSRange(location: next, length: 0))
    }

    @objc func copy(_ sender: Any?) {
        guard let range = owner?.find.selection ?? selection, range.length > 0,
            let rendered = owner?.rendered, let text = rendered.readerTextRange(for: range)
        else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rendered.text(in: text), forType: .string)
    }

    override func selectAll(_ sender: Any?) {
        guard let rendered = owner?.rendered, let range = rendered.readerSemanticRange(for: rendered.documentRange) else { return }
        owner?.find.clearSelection()
        setSelection(range)
    }

    override func cancelOperation(_ sender: Any?) {
        if owner?.isFindPresented == true { owner?.dismissFind() }
        else if selection != nil { setSelection(nil) }
        else { super.cancelOperation(sender) }
    }

    override func performTextFinderAction(_ sender: Any?) {
        guard let action = readerFindAction(from: sender) else { return }
        owner?.performFindAction(action)
    }

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)): return ((owner?.find.selection ?? selection)?.length ?? 0) > 0
        case #selector(selectAll(_:)): return owner?.rendered?.documentRange.isEmpty == false
        case #selector(performTextFinderAction(_:)):
            return NSTextFinder.Action(rawValue: item.tag).map { owner?.validateFindAction($0) == true } ?? false
        default: return true
        }
    }

    func invalidateLinkCursors() {
        accessibilityLinks = nil
        if let window { updatePointer(at: convert(window.mouseLocationOutsideOfEventStream, from: nil)) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard pointerTracking == nil else { return }
        let tracking = NSTrackingArea(
            rect: .zero, options: [.inVisibleRect, .activeInKeyWindow, .mouseMoved, .cursorUpdate],
            owner: self, userInfo: nil)
        addTrackingArea(tracking)
        pointerTracking = tracking
    }

    override func mouseMoved(with event: NSEvent) { updatePointer(at: documentPoint(event)) }
    override func cursorUpdate(with event: NSEvent) { updatePointer(at: documentPoint(event)) }

    private func updatePointer(at point: CGPoint) {
        guard window?.isKeyWindow == true, visibleRect.contains(point) else { return }
        (link(at: point) == nil ? NSCursor.iBeam : NSCursor.pointingHand).set()
    }

    // MARK: VoiceOver

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .textArea }
    override func accessibilityLabel() -> String? { String(localized: "Document", bundle: .module) }
    override func accessibilityValue() -> Any? { semanticString }
    override func accessibilityNumberOfCharacters() -> Int { semanticString.length }
    override func accessibilitySelectedTextRange() -> NSRange { owner?.find.selection ?? selection ?? NSRange(location: 0, length: 0) }

    override func setAccessibilitySelectedTextRange(_ range: NSRange) {
        guard owner?.rendered?.readerTextRange(for: range) != nil else { return }
        owner?.find.clearSelection()
        setSelection(range)
        owner?.revealText(range)
    }

    override func accessibilitySelectedText() -> String? { accessibilityString(for: accessibilitySelectedTextRange()) }

    override func accessibilityVisibleCharacterRange() -> NSRange {
        guard let owner, let rendered = owner.rendered,
            let text = rendered.textRange(intersectingVerticalRange: owner.viewport.minY..<owner.viewport.maxY),
            let range = rendered.readerSemanticRange(for: text)
        else { return NSRange(location: 0, length: 0) }
        return range
    }

    override func accessibilityString(for range: NSRange) -> String? {
        guard let rendered = owner?.rendered, let text = rendered.readerTextRange(for: range) else { return nil }
        return rendered.text(in: text)
    }

    override func accessibilityAttributedString(for range: NSRange) -> NSAttributedString? {
        accessibilityString(for: range).map { NSAttributedString(string: $0) }
    }

    override func accessibilityFrame(for range: NSRange) -> NSRect {
        let frame = rects(for: range).reduce(CGRect.null) { $0.union($1) }
        return frame.isNull ? .zero : NSAccessibility.screenRect(fromView: self, rect: frame)
    }

    override func accessibilityRange(for point: NSPoint) -> NSRange {
        guard let window, let index = offset(at: convert(window.convertPoint(fromScreen: point), from: nil))
        else { return NSRange(location: NSNotFound, length: 0) }
        return accessibilityRange(for: index)
    }

    override func accessibilityRange(for index: Int) -> NSRange {
        let string = semanticString
        guard index >= 0, index < string.length else { return NSRange(location: NSNotFound, length: 0) }
        return string.rangeOfComposedCharacterSequence(at: index)
    }

    private func semanticLineStarts() -> [Int] {
        if let lineStarts { return lineStarts }
        let string = semanticString
        var starts = [0]
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byLines, .substringNotRequired]) {
            _, _, enclosing, _ in
            let next = NSMaxRange(enclosing)
            if next < string.length { starts.append(next) }
        }
        lineStarts = starts
        return starts
    }

    override func accessibilityLine(for index: Int) -> Int {
        guard index >= 0, index <= semanticString.length else { return NSNotFound }
        let starts = semanticLineStarts()
        var lower = 0
        var upper = starts.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if starts[middle] <= index { lower = middle + 1 } else { upper = middle }
        }
        return lower - 1
    }

    override func accessibilityRange(forLine line: Int) -> NSRange {
        let starts = semanticLineStarts()
        guard starts.indices.contains(line) else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: starts[line], length: (line + 1 < starts.count ? starts[line + 1] : semanticString.length) - starts[line])
    }

    override func accessibilityChildren() -> [Any]? {
        let controls = super.accessibilityChildren() ?? []
        if let accessibilityLinks { return controls + accessibilityLinks }
        guard let owner, let rendered = owner.rendered else { return controls }
        let links = rendered.readerLinks(in: owner.viewport, tableOffsets: owner.tableOffsets).map { link in
            let width = min(0.25, link.rect.width * 0.25)
            let start = rendered.position(closestTo: owner.semanticPoint(CGPoint(x: link.rect.minX + width, y: link.rect.midY)))
            let end = rendered.position(closestTo: owner.semanticPoint(CGPoint(x: link.rect.maxX - width, y: link.rect.midY)))
            let label = rendered.text(in: KasumiMarkdown.TextRange(start, end)).trimmingCharacters(in: .whitespacesAndNewlines)
            return ReaderAccessibilityLink(
                parent: self, snapshot: rendered, url: link.url, label: label, rect: link.rect)
        }
        accessibilityLinks = links
        return controls + links
    }

    func rects(for range: NSRange) -> [CGRect] {
        guard let owner, let rendered = owner.rendered, let text = rendered.readerTextRange(for: range) else { return [] }
        let rects = text.isEmpty ? [rendered.caretRect(for: text.lowerBound)] : rendered.selectionRects(for: text)
        return rects.compactMap { rect in
            let visible = owner.visibleSelectionRect(rect)
            return visible.isEmpty ? nil : visible
        }
    }
}

private final class ReaderAccessibilityLink: NSAccessibilityElement {
    private let press: @MainActor @Sendable () -> Bool

    @MainActor init(parent canvas: ReaderCanvas, snapshot: RenderedDocument, url: URL, label: String, rect: CGRect) {
        press = { [weak canvas, weak snapshot] in
            guard let owner = canvas?.owner, let snapshot, owner.rendered === snapshot else { return false }
            owner.activateLink(url)
            return true
        }
        super.init()
        setAccessibilityElement(true)
        setAccessibilityParent(canvas)
        setAccessibilityRole(.link)
        setAccessibilityLabel(label.isEmpty ? url.absoluteString : label)
        setAccessibilityURL(url)
        setAccessibilityFrameInParentSpace(rect)
    }

    override func accessibilityPerformPress() -> Bool { MainActor.assumeIsolated(press) }
}

extension RenderedDocument {
    func readerTextRange(for range: NSRange) -> KasumiMarkdown.TextRange? {
        guard range.location >= 0, range.length >= 0 else { return nil }
        let (end, overflow) = range.location.addingReportingOverflow(range.length)
        guard !overflow else { return nil }
        let origin = documentRange.lowerBound
        guard let first = position(from: origin, offset: range.location), let last = position(from: origin, offset: end)
        else { return nil }
        return KasumiMarkdown.TextRange(first, last)
    }

    func readerSemanticRange(for range: KasumiMarkdown.TextRange) -> NSRange? {
        let origin = documentRange.lowerBound
        guard let first = offset(from: origin, to: range.lowerBound), let last = offset(from: origin, to: range.upperBound)
        else { return nil }
        return NSRange(location: first, length: last - first)
    }
}
#endif
