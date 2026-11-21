#if os(iOS)
import KasumiMarkdown
import UIKit

@MainActor protocol ReaderFindNavigator: AnyObject {
    var isPresented: Bool { get }
    func present()
    func dismiss()
    func install(_ rendered: RenderedDocument)
}

/// Keep all references to the iOS 16 Find APIs out of the iOS 15 viewport.
@available(iOS 16.0, *)
@MainActor final class UIKitReaderFind: NSObject, ReaderFindNavigator, UIFindInteractionDelegate {
    private let snapshot: () -> RenderedDocument?
    private let update: ([TextRange], Int?, Bool) -> Void
    private let begin: () -> Void
    private let end: () -> Void
    private lazy var interaction = UIFindInteraction(sessionDelegate: self)
    private lazy var session = ReaderFindSession { [weak self] matches, current, scroll in
        self?.update(matches, current, scroll)
        self?.interaction.updateResultCount()
    }

    init(
        view: UIView, snapshot: @escaping () -> RenderedDocument?,
        update: @escaping ([TextRange], Int?, Bool) -> Void, begin: @escaping () -> Void, end: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.update = update
        self.begin = begin
        self.end = end
        super.init()
        view.addInteraction(interaction)
    }

    var isPresented: Bool { interaction.isFindNavigatorVisible }
    func present() { interaction.presentFindNavigator(showingReplace: false) }
    func dismiss() {
        if isPresented { interaction.dismissFindNavigator() }
    }
    func install(_ rendered: RenderedDocument) { session.install(rendered, scroll: false) }

    func findInteraction(_ interaction: UIFindInteraction, sessionFor view: UIView) -> UIFindSession? {
        guard let rendered = snapshot() else { return nil }
        session.install(rendered)
        return session
    }

    func findInteraction(_ interaction: UIFindInteraction, didBegin session: UIFindSession) {
        begin()
        self.session.begin()
    }

    func findInteraction(_ interaction: UIFindInteraction, didEnd session: UIFindSession) {
        self.session.end()
        end()
    }
}

/// The system owns the field, keyboard presentation, count, navigation controls,
/// and shortcuts. The session supplies results in Kasumi's immutable layout.
@available(iOS 16.0, *)
@MainActor private final class ReaderFindSession: UIFindSession {
    private var rendered: RenderedDocument?
    private var query = ""
    private var options: UITextSearchOptions?
    private var search = ReaderSearchState()
    private var matches: [TextRange] = []
    private var currentIndex = NSNotFound
    private var active = false
    private let update: ([TextRange], Int?, Bool) -> Void

    init(update: @escaping ([TextRange], Int?, Bool) -> Void) {
        self.update = update
        super.init()
    }

    override var resultCount: Int { matches.count }
    override var highlightedResultIndex: Int { currentIndex }
    override var supportsReplacement: Bool { false }

    func install(_ rendered: RenderedDocument, scroll: Bool = true) {
        guard self.rendered !== rendered else { return }
        self.rendered = rendered
        if active { rebuild(resetIndex: false, scroll: scroll) }
    }

    func begin() {
        active = true
        rebuild(resetIndex: false)
    }

    func end() {
        active = false
        matches = []
        currentIndex = NSNotFound
        update([], nil, false)
    }

    override func performSearch(query: String, options: UITextSearchOptions?) {
        self.query = query
        self.options = options
        rebuild(resetIndex: true)
    }

    override func highlightNextResult(in direction: UITextStorageDirection) {
        guard !matches.isEmpty else { return }
        let delta = direction == .backward ? -1 : 1
        if currentIndex == NSNotFound {
            currentIndex = direction == .backward ? matches.count - 1 : 0
        } else {
            currentIndex = (currentIndex + delta + matches.count) % matches.count
        }
        update(matches, currentIndex, true)
    }

    override func invalidateFoundResults() {
        matches = []
        currentIndex = NSNotFound
        update([], nil, false)
    }

    private func rebuild(resetIndex: Bool, scroll: Bool = true) {
        guard active, let rendered else { return }
        matches = matchingRanges(in: rendered)
        // UIKit requests the initial highlight after performSearch. Leave it
        // unset here so that request selects result 1 rather than skipping it.
        currentIndex =
            matches.isEmpty || resetIndex
            ? NSNotFound : (currentIndex == NSNotFound ? 0 : min(currentIndex, matches.count - 1))
        update(matches, currentIndex == NSNotFound ? nil : currentIndex, scroll && !resetIndex)
    }

    private func matchingRanges(in rendered: RenderedDocument) -> [TextRange] {
        guard !query.isEmpty else { return [] }
        let text = rendered.readerSemanticText
        let method = options?.wordMatchMethod ?? .contains
        let wordMatch: ReaderSearchState.WordMatch =
            method == .contains ? .contains : method == .fullWord ? .fullWord : .startsWith
        let ranges = search.ranges(
            in: text, matching: query,
            options: .init(
                comparison: options?.stringCompareOptions ?? [.caseInsensitive, .diacriticInsensitive],
                wordMatch: wordMatch))
        let beginning = rendered.documentRange.lowerBound
        return ranges.compactMap { range in
            guard let start = rendered.position(from: beginning, offset: range.location),
                let end = rendered.position(from: start, offset: range.length)
            else { return nil }
            return TextRange(start, end)
        }
    }
}
#endif
