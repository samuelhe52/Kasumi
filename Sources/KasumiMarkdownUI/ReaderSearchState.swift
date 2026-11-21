import Foundation

/// Reader-owned semantic offsets survive width changes; layout-owned positions
/// are reconstructed by ReaderFindSession for every new snapshot.
struct ReaderSearchState {
    enum WordMatch: Equatable { case contains, startsWith, fullWord }
    struct Options: Equatable {
        var comparison: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var wordMatch: WordMatch = .contains
    }

    private var hasText = false
    private var searchText: NSString = ""
    private var wordBoundaries: (starts: Set<Int>, ends: Set<Int>)?
    private var query: NSString?
    private var options: Options?
    private var matches: [NSRange] = []
    private(set) var searchBuilds = 0
    private(set) var wordBoundaryBuilds = 0

    mutating func ranges(in text: String, matching query: String, options: Options = Options()) -> [NSRange] {
        // String == permits canonical equivalents with different UTF-16 offsets.
        // NSString equality compares the literal text without a Swift index walk.
        if !hasText || !searchText.isEqual(to: text) {
            hasText = true
            searchText = text as NSString
            wordBoundaries = nil
            self.query = nil
            matches = []
        }
        if self.query?.isEqual(to: query) == true, self.options == options { return matches }
        self.query = query as NSString
        self.options = options
        matches = []
        guard !query.isEmpty else { return matches }

        if options.wordMatch != .contains, wordBoundaries == nil {
            var starts: Set<Int> = []
            var ends: Set<Int> = []
            searchText.enumerateSubstrings(
                in: NSRange(location: 0, length: searchText.length), options: [.byWords, .substringNotRequired]
            ) { _, range, _, _ in
                starts.insert(range.location)
                ends.insert(NSMaxRange(range))
            }
            wordBoundaries = (starts, ends)
            wordBoundaryBuilds += 1
        }
        searchBuilds += 1
        var cursor = 0
        while cursor < searchText.length {
            let range = searchText.range(
                of: query, options: options.comparison,
                range: NSRange(location: cursor, length: searchText.length - cursor),
                locale: Locale(identifier: "en_US_POSIX"))
            guard range.location != NSNotFound, range.length > 0 else { break }
            cursor = NSMaxRange(range)
            if options.wordMatch != .contains, wordBoundaries?.starts.contains(range.location) != true { continue }
            if options.wordMatch == .fullWord, wordBoundaries?.ends.contains(cursor) != true { continue }
            matches.append(range)
        }
        return matches
    }
}
