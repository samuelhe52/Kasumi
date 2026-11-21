import Foundation
import KasumiMarkdown

public enum FindDirection: Sendable {
    case next, previous
}

public struct FindResult: Equatable, Sendable {
    public let count: Int
    /// Zero-based index, or nil when no match is current.
    public let currentIndex: Int?
}

/// Holds semantic matches independently of the platform's native Find panel.
@MainActor struct ProgrammaticFind {
    private var search = ReaderSearchState()
    private var query = ""
    private var options = SearchOptions()
    private var origin: KasumiMarkdown.TextPosition?
    private(set) var ranges: [KasumiMarkdown.TextRange] = []
    private(set) var currentIndex: Int?

    var result: FindResult { FindResult(count: ranges.count, currentIndex: currentIndex) }

    mutating func setQuery(_ query: String, options: SearchOptions, in rendered: RenderedDocument?) {
        guard !query.isEmpty else { clear(); return }
        if (self.query as NSString).isEqual(to: query), self.options == options {
            if let rendered { install(rendered) }
            return
        }
        self.query = query
        self.options = options
        currentIndex = nil
        origin = nil
        ranges = []
        if let rendered { install(rendered) }
    }

    mutating func install(_ rendered: RenderedDocument) {
        let beginning = rendered.documentRange.lowerBound
        guard !query.isEmpty, beginning != origin else { return }
        origin = beginning
        var comparison: NSString.CompareOptions = []
        if !options.contains(.caseSensitive) { comparison.insert(.caseInsensitive) }
        if !options.contains(.diacriticSensitive) { comparison.insert(.diacriticInsensitive) }
        let offsets = search.ranges(
            in: rendered.readerSemanticText, matching: query, options: .init(comparison: comparison))
        ranges = offsets.compactMap { range in
            guard let start = rendered.position(from: beginning, offset: range.location),
                let end = rendered.position(from: start, offset: range.length)
            else { return nil }
            return KasumiMarkdown.TextRange(start, end)
        }
        currentIndex = ranges.isEmpty ? nil : min(currentIndex ?? 0, ranges.count - 1)
    }

    mutating func move(_ direction: FindDirection) {
        guard !ranges.isEmpty else { return }
        let end = ranges.count - 1
        switch direction {
        case .next: currentIndex = currentIndex.flatMap { $0 < end ? $0 + 1 : nil } ?? 0
        case .previous: currentIndex = currentIndex.flatMap { $0 > 0 ? $0 - 1 : nil } ?? end
        }
    }

    mutating func clear() { self = ProgrammaticFind() }
}
