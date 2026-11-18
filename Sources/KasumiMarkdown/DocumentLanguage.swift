import Foundation

/// Immutable, bounded analysis captured when a document is parsed, never at reflow.
struct DocumentLanguageAnalysis: Equatable, Sendable {
    enum Origin: Equatable, Sendable { case frontMatter, stopwords, fallback }
    let hyphenationLanguage: String
    let origin: Origin
    let sampledScalars: Int

    static let sampleLimit = 32_768
    static let wordLimit = 4_096
    private static let languages = [
        "en-us", "de-1996", "fr", "es", "it", "pt", "nl", "sv", "da", "nb", "fi", "pl", "cs", "ru"
    ]
    // Authored function-word sets, not a model or imported linguistic corpus.
    // Shared words receive less weight, and repeated words have capped influence.
    private static let stopwords = [
        "the and of to in is that for with as this it be are was from not have on or by an a which their",
        "der die das und ist nicht ein eine einer den dem des mit für von auf sich auch als zu im wird werden",
        "le la les des du et est une un dans pour avec que qui sur pas sont au aux ce cette nous vous",
        "el la los las del y es una un en para con que por no se como más pero sus está son",
        "il lo la gli le di del della e è una un per con che non nel nella sono come questo anche",
        "o a os as do da dos das e é uma um em para com que por não se são como mas este",
        "de het een en is niet van voor met dat die op als zijn wordt deze ook aan door er",
        "och att det som är en ett för med inte den till av på har från om men också blir",
        "og at det som er en et for med ikke den til af på har fra om men også bliver",
        "og at det som er en et for med ikke den til av på har fra om men også blir være",
        "ja on ei että se tämä ovat kanssa mutta myös kuin kun joka sekä oli voi olla tai hän",
        "i w na z do nie jest się że to dla jak ale przez oraz są tego tej który jako lub",
        "a v na z do se je že to pro jak ale jsou který která nebo také jako při není byl",
        "и в на с не что это для как но из по от к у за он она они который также есть"
    ]
    /// A normalized stopword's UTF-8 bytes fit in two machine words. Zero bytes
    /// never occur in the authored lexicon or sampled letter tokens, so padding
    /// is unambiguous. Keep matching allocation-free without constructing a trie
    /// at the first parse in each process.
    private struct WordKey: Hashable {
        var low: UInt64 = 0
        var high: UInt64 = 0
        @inline(__always) mutating func append(_ byte: UInt8, at index: Int) {
            if index < 8 { low |= UInt64(byte) << (index * 8) } else { high |= UInt64(byte) << ((index - 8) * 8) }
        }
    }
    private struct Vote {
        var mask: UInt16
        let word: Int
    }
    private static let votes: [WordKey: Vote] = {
        var result: [WordKey: Vote] = [:]
        result.reserveCapacity(stopwords.count * 32)
        @inline(__always) func record(_ key: WordKey, language: Int) {
            let nextWord = result.count
            result[key, default: Vote(mask: 0, word: nextWord)].mask |= 1 << language
        }
        @inline(__always) func scan<Bytes: Sequence>(_ bytes: Bytes, language: Int) where Bytes.Element == UInt8 {
            var key = WordKey()
            var length = 0
            for byte in bytes {
                if byte == 32 {
                    if length > 0 { record(key, language: language) }
                    key = WordKey()
                    length = 0
                } else {
                    precondition(length < 16, "Widen WordKey before adding a longer stopword")
                    key.append(byte, at: length)
                    length += 1
                }
            }
            if length > 0 { record(key, language: language) }
        }
        for (index, words) in stopwords.enumerated() {
            let scanned =
                words.utf8.withContiguousStorageIfAvailable { bytes in
                    scan(bytes, language: index)
                    return true
                } ?? false
            if !scanned { scan(words.utf8, language: index) }
        }
        return result
    }()

    static func dictionary(for tag: String) -> String? {
        let tag = tag.lowercased().replacingOccurrences(of: "_", with: "-")
        if tag == "en-gb" || tag.hasPrefix("en-gb-") { return "en-gb" }
        let primary = tag.split(separator: "-").first.map(String.init) ?? ""
        switch primary {
        case "en": return "en-us"
        case "de": return "de-1996"
        case "fr", "es", "it", "pt", "nl", "sv", "da", "nb", "fi", "pl", "cs", "ru": return primary
        default: return nil
        }
    }

    private struct Sampler {
        var scores = [Int](repeating: 0, count: languages.count)
        var distinct = [Int](repeating: 0, count: languages.count)
        let lexicon = votes
        var occurrences = [UInt8](repeating: 0, count: votes.count)
        var scalars = 0
        var words = 0
        var token = WordKey()
        var tokenBytes = 0
        var tokenScalars = 0
        @inline(__always) mutating func append(_ byte: UInt8) {
            if tokenBytes < 16 { token.append(byte, at: tokenBytes) }
            tokenBytes += 1
        }
        @inline(__always) mutating func letter(_ value: UInt32) {
            tokenScalars += 1
            guard tokenScalars <= 48, tokenBytes <= 16 else { return }
            if value < 128 {
                append(UInt8(value <= 90 ? value + 32 : value))
            } else {
                for byte in String(UnicodeScalar(value)!).lowercased().utf8 { append(byte) }
            }
        }
        @inline(__always) mutating func flush() {
            guard tokenScalars > 0 else { return }
            words += 1
            let key = token
            let length = tokenBytes
            token = WordKey()
            tokenBytes = 0
            tokenScalars = 0
            guard length <= 16, let vote = lexicon[key] else { return }
            let mask = vote.mask
            let word = vote.word
            let prior = occurrences[word]
            guard prior < 4 else { return }
            occurrences[word] = prior + 1
            let weight = max(1, 8 / mask.nonzeroBitCount)
            for index in languages.indices where mask & (1 << index) != 0 {
                scores[index] += weight
                if prior == 0 { distinct[index] += 1 }
            }
        }
        mutating func sample(_ runs: [InlineRun]) {
            for run in runs {
                guard scalars < sampleLimit, words < wordLimit else { return }
                guard run.traits.isDisjoint(with: [.code, .math, .image, .footnote, .link]) else {
                    flush()
                    continue
                }
                var truncated = false
                let sampledASCII =
                    run.text.utf8.withContiguousStorageIfAvailable { bytes in
                        let prefix = bytes.prefix(sampleLimit - scalars)
                        guard prefix.allSatisfy({ $0 < 128 }) else { return false }
                        var consumed = 0
                        for value in prefix {
                            guard words < wordLimit else { break }
                            consumed += 1
                            scalars += 1
                            if (65...90).contains(value) || (97...122).contains(value) {
                                letter(UInt32(value))
                            } else {
                                flush()
                            }
                        }
                        truncated = consumed < bytes.count
                        return true
                    } ?? false
                if sampledASCII {
                    if truncated { return }
                    continue
                }
                for scalar in run.text.unicodeScalars {
                    guard scalars < sampleLimit, words < wordLimit else { return }
                    scalars += 1
                    let value = scalar.value
                    let asciiLetter = (65...90).contains(value) || (97...122).contains(value)
                    let extendedLetter =
                        (0x00C0...0x024F).contains(value) || (0x1E00...0x1EFF).contains(value)
                        || (0x0400...0x04FF).contains(value)
                    if asciiLetter || (extendedLetter && scalar.properties.isAlphabetic) {
                        letter(value)
                    } else {
                        flush()
                    }
                }
            }
            flush()
        }
    }

    static func analyze(_ blocks: [DocumentBlock], declaredLanguage: String? = nil) -> Self {
        if let declaredLanguage, let tag = dictionary(for: declaredLanguage) {
            return Self(hyphenationLanguage: tag, origin: .frontMatter, sampledScalars: 0)
        }
        var sampler = Sampler()
        for block in blocks {
            guard sampler.scalars < sampleLimit, sampler.words < wordLimit else { break }
            switch block.kind {
            case .paragraph, .heading, .quote: sampler.sample(block.runs)
            case .table:
                for row in block.rows {
                    guard sampler.scalars < sampleLimit, sampler.words < wordLimit else { break }
                    for cell in row {
                        guard sampler.scalars < sampleLimit, sampler.words < wordLimit else { break }
                        sampler.sample(cell)
                    }
                }
            default: break
            }
        }
        let scores = sampler.scores
        let distinct = sampler.distinct
        let scalars = sampler.scalars
        // A truncated final token must not vote as a different, shorter word.
        // Complete tokens are flushed at run/block boundaries above.
        let ranked = scores.indices.sorted { scores[$0] > scores[$1] }
        let winner = ranked[0]
        let runnerUp = scores[ranked[1]]
        guard distinct[winner] >= 3, scores[winner] >= 24,
            scores[winner] - runnerUp >= 8, scores[winner] * 4 >= runnerUp * 5
        else { return Self(hyphenationLanguage: "en-us", origin: .fallback, sampledScalars: scalars) }
        return Self(hyphenationLanguage: languages[winner], origin: .stopwords, sampledScalars: scalars)
    }
}

/// A deliberately bounded front-matter envelope reader, not a general YAML parser.
struct DocumentFrontMatter {
    let markdown: String
    let language: String?

    init(_ source: String) {
        markdown = source
        language = nil
    }

    private init(markdown: String, language: String?) {
        self.markdown = markdown
        self.language = language
    }

    static func extract(_ source: String) -> Self {
        guard source.hasPrefix("---") || source.hasPrefix("\u{FEFF}---") else { return Self(source) }
        let bytes = Array(source.utf8.prefix(65_536))
        var start = source.hasPrefix("\u{FEFF}") ? 3 : 0
        var lineCount = 0
        var language: String?
        for index in 0...bytes.count where index == bytes.count || bytes[index] == 10 {
            guard index >= start else { continue }
            guard index < bytes.count || bytes.count == source.utf8.count else { return Self(source) }
            let line = String(decoding: bytes[start..<index], as: UTF8.self).trimmingCharacters(
                in: .whitespacesAndNewlines)
            if lineCount == 0 {
                guard line == "---" else { return Self(source) }
            } else if line == "---" || line == "..." {
                let end = index < bytes.count ? index + 1 : index
                let boundary = source.utf8.index(source.utf8.startIndex, offsetBy: end)
                return Self(
                    markdown: String(repeating: "\n", count: lineCount + 1)
                        + String(decoding: source.utf8[boundary...], as: UTF8.self),
                    language: language)
            } else if let colon = line.firstIndex(of: ":"),
                line[..<colon].trimmingCharacters(in: .whitespaces) == "lang"
            {
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if value.first == "\"" || value.first == "'", let quote = value.first,
                    let close = value.dropFirst().firstIndex(of: quote)
                {
                    language = String(value[value.index(after: value.startIndex)..<close])
                } else {
                    language = value.split(separator: "#", maxSplits: 1).first.map {
                        $0.trimmingCharacters(in: .whitespaces)
                    }
                }
            }
            lineCount += 1
            guard lineCount < 128 else { return Self(source) }
            start = index + 1
        }
        return Self(source)
    }
}
