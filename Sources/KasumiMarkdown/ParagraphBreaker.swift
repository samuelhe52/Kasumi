import CoreText
import Foundation

enum ParagraphAlignment: String, Codable, CaseIterable, Sendable { case justified, leading, centered, trailing }

/// Paragraph-wide box/glue/penalty optimization. Native shaping supplies edge widths.
/// Narrow-measure alignment policy is selected by the caller, independently of breaking.
enum ParagraphBreaker {
    private struct Point {
        let offset: Int
        let forced: Bool
    }
    private struct State {
        var cost = Double.infinity
        var predecessor = -1
        var fitness = 1
    }

    static func ranges(
        in text: String, width: Double, fontSize: Double = 16,
        alignment: ParagraphAlignment = .justified, firstLineIndent: Double = 0,
        measure: (NSRange) -> Double
    ) -> [NSRange] {
        guard !text.isEmpty, width > 0 else { return [] }
        let ns = text as NSString
        let characters = Array(text)
        var offsets = [0]
        var offset = 0
        for character in characters {
            offset += String(character).utf16.count
            offsets.append(offset)
        }
        var points = [Point(offset: 0, forced: false)]
        for index in characters.indices {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            let forced = character == "\n"
            let whitespace = character.isWhitespace
            let cjkBreak =
                next.map { (isCJK(character) || isCJK($0)) && !isOpening(character) && !isClosing($0) } ?? false
            let spaceBreak = whitespace && !(next?.isWhitespace ?? false) && !(next.map(isClosing) ?? false)
            if forced || spaceBreak || cjkBreak || index == characters.count - 1 {
                points.append(Point(offset: offsets[index + 1], forced: forced))
            }
        }
        var states = Array(repeating: Array(repeating: State(), count: 4), count: points.count)
        states[0][1].cost = 0
        var lastForced = 0
        for end in 1..<points.count {
            for start in stride(from: end - 1, through: lastForced, by: -1) {
                let range = trimmedRange(ns, from: points[start].offset, to: points[end].offset)
                let natural = measure(range)
                let edgeWidth = max(1, width - (start == 0 ? firstLineIndent : 0))
                let segment = ns.substring(with: range)
                let spaces = segment.filter { $0 == " " || $0 == "\t" }.count
                let cjkGaps = max(0, segment.filter(isCJK).count - 1)
                let shrink = Double(spaces) * fontSize * 0.22 + Double(cjkGaps) * fontSize * 0.05
                if natural - shrink > edgeWidth + 0.01 { break }
                let last = end == points.count - 1 || points[end].forced
                let delta = edgeWidth - natural
                var badness: Double
                var fitness = 1
                if alignment == .justified && !last {
                    let glue = Double(spaces) * fontSize * 0.5 + Double(cjkGaps) * fontSize * 0.18
                    let capacity = delta >= 0 ? glue : shrink
                    let ratio = capacity > 0 ? delta / capacity : delta / edgeWidth * 3
                    if ratio < -1 { continue }
                    fitness = ratio < -0.5 ? 0 : ratio <= 0.5 ? 1 : ratio <= 1 ? 2 : 3
                    badness = min(10000, 100 * pow(abs(ratio), 3))
                } else {
                    guard natural <= edgeWidth + 0.01 else { continue }
                    badness = last ? 0 : delta * delta
                }
                if last && start > 0 && natural < width * 0.18 { badness += width * 0.2 }
                for priorFitness in 0..<4 where states[start][priorFitness].cost.isFinite {
                    let transition = alignment == .justified && !last && abs(priorFitness - fitness) > 1 ? 3000.0 : 0
                    let cost = states[start][priorFitness].cost + badness + 10 + transition
                    if cost < states[end][fitness].cost {
                        states[end][fitness] = State(cost: cost, predecessor: start, fitness: priorFitness)
                    }
                }
            }
            if points[end].forced { lastForced = end }
        }
        var cursor = points.count - 1
        var fitness = (0..<4).min { states[cursor][$0].cost < states[cursor][$1].cost } ?? 1
        guard states[cursor][fitness].cost.isFinite else {
            return emergencyRanges(text, width: width, offsets: offsets, measure: measure)
        }
        var result: [NSRange] = []
        while cursor > 0 {
            let state = states[cursor][fitness]
            guard state.predecessor >= 0 else {
                return emergencyRanges(text, width: width, offsets: offsets, measure: measure)
            }
            result.append(trimmedRange(ns, from: points[state.predecessor].offset, to: points[cursor].offset))
            cursor = state.predecessor
            fitness = state.fitness
        }
        return result.reversed()
    }

    static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (0x2E80...0x9FFF).contains(scalar.value) || (0xF900...0xFAFF).contains(scalar.value)
                || (0x20000...0x323AF).contains(scalar.value) || (0xAC00...0xD7AF).contains(scalar.value)
                || (0x3040...0x30FF).contains(scalar.value)
        }
    }
    private static func isOpening(_ c: Character) -> Bool { "（［｛〈《「『【〔〖〘〚([{‘“".contains(c) }
    private static func isClosing(_ c: Character) -> Bool { "，。！？；：、）］｝〉》」』】〕〗〙〛,.!?;:)]}’”".contains(c) }
    private static func trimmedRange(_ text: NSString, from start: Int, to end: Int) -> NSRange {
        var lower = start
        var upper = end
        let spaces = CharacterSet.whitespacesAndNewlines
        while lower < upper, let c = UnicodeScalar(text.character(at: lower)), spaces.contains(c) { lower += 1 }
        while upper > lower, let c = UnicodeScalar(text.character(at: upper - 1)), spaces.contains(c) { upper -= 1 }
        return NSRange(location: lower, length: upper - lower)
    }
    private static func emergencyRanges(_ text: String, width: Double, offsets: [Int], measure: (NSRange) -> Double)
        -> [NSRange]
    {
        let ns = text as NSString
        var result: [NSRange] = []
        var startIndex = 0
        while startIndex < offsets.count - 1 {
            var endIndex = startIndex + 1
            while endIndex + 1 < offsets.count
                && measure(NSRange(location: offsets[startIndex], length: offsets[endIndex + 1] - offsets[startIndex]))
                    <= width
            {
                if ns.substring(
                    with: NSRange(location: offsets[endIndex - 1], length: offsets[endIndex] - offsets[endIndex - 1]))
                    == "\n"
                {
                    break
                }
                endIndex += 1
            }
            result.append(trimmedRange(ns, from: offsets[startIndex], to: offsets[endIndex]))
            startIndex = endIndex
        }
        return result
    }
}
