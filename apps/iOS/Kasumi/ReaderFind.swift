import KasumiMarkdown
import UIKit

/// The system owns the field, keyboard presentation, count, navigation controls,
/// and shortcuts. The session supplies results in Kasumi's immutable layout.
final class ReaderFindSession: UIFindSession {
    private var rendered: RenderedDocument?
    private var query = ""
    private var options: UITextSearchOptions?
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
        currentIndex = matches.isEmpty || resetIndex ? NSNotFound :
            (currentIndex == NSNotFound ? 0 : min(currentIndex, matches.count - 1))
        update(matches, currentIndex == NSNotFound ? nil : currentIndex, scroll && !resetIndex)
    }

    private func matchingRanges(in rendered: RenderedDocument) -> [TextRange] {
        guard !query.isEmpty else { return [] }
        let text = rendered.text(in: rendered.documentRange) as NSString
        let method = options?.wordMatchMethod ?? .contains
        var wordStarts: Set<Int> = []
        var wordEnds: Set<Int> = []
        if method != .contains {
            text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byWords, .substringNotRequired]) {
                _, range, _, _ in
                wordStarts.insert(range.location)
                wordEnds.insert(NSMaxRange(range))
            }
        }
        let flags = options?.stringCompareOptions ?? [.caseInsensitive, .diacriticInsensitive]
        var cursor = 0
        var result: [TextRange] = []
        while cursor < text.length {
            let range = text.range(
                of: query, options: flags, range: NSRange(location: cursor, length: text.length - cursor),
                locale: Locale(identifier: "en_US_POSIX"))
            guard range.location != NSNotFound, range.length > 0 else { break }
            cursor = NSMaxRange(range)
            if method != .contains && !wordStarts.contains(range.location) { continue }
            if method == .fullWord && !wordEnds.contains(cursor) { continue }
            guard let start = rendered.position(from: rendered.documentRange.lowerBound, offset: range.location),
                let end = rendered.position(from: start, offset: range.length) else { continue }
            result.append(TextRange(start, end))
        }
        return result
    }
}
