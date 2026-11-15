import CryptoKit
import Foundation

/// A position in semantic document text, independent of font and viewport size.
/// Hashes identify paragraphs and their neighbors without persisting excerpts.
public struct ReadingAnchor: Codable, Equatable, Sendable {
    var blockKey: String
    var blockIndex: Int
    var offset: Int
    /// Nearest previous paragraph first.
    var previousKeys: [String]
    /// Nearest following paragraph first.
    var nextKeys: [String]
    var blockCount: Int
    var verticalFraction: Double

    init(
        blockKey: String, blockIndex: Int, offset: Int, previousKeys: [String] = [], nextKeys: [String] = [],
        blockCount: Int, verticalFraction: Double
    ) {
        self.blockKey = blockKey
        self.blockIndex = blockIndex
        self.offset = offset
        self.previousKeys = previousKeys
        self.nextKeys = nextKeys
        self.blockCount = blockCount
        self.verticalFraction = verticalFraction
    }
}

/// Built once after typesetting. Capturing a scroll position does not hash or
/// scan document text; restoration can relocate an unchanged or edited block.
struct ReadingPositionIndex {
    private struct Block {
        let key: String
        let textMap: DocumentTextMap
        let lines: [Line]
    }
    private struct Line {
        let block: Int
        let range: NSRange
        let semanticOffset: Int
        let top: CGFloat
        let bottom: CGFloat
        let x: CGFloat
        var height: CGFloat { max(1, bottom - top) }
    }
    private let blocks: [Block]
    private let lines: [Line]
    private let prefixBottoms: [CGFloat]
    private let indicesByKey: [String: [Int]]

    init(layout: DocumentLayout) {
        var blocks: [Block] = []
        var lines: [Line] = []
        var indices: [String: [Int]] = [:]
        for (index, item) in layout.paragraphs.enumerated() {
            let paragraph = item.paragraph
            let map = DocumentTextMap(paragraph.attributed)
            let key = SHA256.hash(data: Data(map.string.utf8)).map { String(format: "%02x", $0) }.joined()
            let blockLines = paragraph.lines.compactMap { line -> Line? in
                let top = item.origin.y + line.origin.y - line.ascent
                let bottom = item.origin.y + line.origin.y + line.descent
                guard top.isFinite, bottom.isFinite, bottom >= top else { return nil }
                let start = min(paragraph.attributed.length, max(0, line.range.location))
                return Line(
                    block: index, range: line.range, semanticOffset: map.semanticOffset(forRenderedOffset: start),
                    top: top, bottom: bottom, x: item.origin.x + line.origin.x)
            }
            blocks.append(Block(key: key, textMap: map, lines: blockLines))
            indices[key, default: []].append(index)
            lines += blockLines
        }
        lines.sort {
            if $0.top != $1.top { return $0.top < $1.top }
            if $0.x != $1.x { return $0.x < $1.x }
            if $0.block != $1.block { return $0.block < $1.block }
            return $0.range.location < $1.range.location
        }
        var maximum = -CGFloat.infinity
        var prefix: [CGFloat] = []
        for line in lines {
            maximum = max(maximum, line.bottom)
            prefix.append(maximum)
        }
        self.blocks = blocks
        self.lines = lines
        prefixBottoms = prefix
        indicesByKey = indices
    }

    func capture(y: CGFloat) -> ReadingAnchor? {
        guard y.isFinite, !lines.isEmpty else { return nil }
        var lower = 0
        var upper = prefixBottoms.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if prefixBottoms[middle] > y { upper = middle } else { lower = middle + 1 }
        }
        let line = lines[min(lower, lines.count - 1)]
        let block = line.block
        let previous = (1...2).compactMap { distance in block >= distance ? blocks[block - distance].key : nil }
        let following = (1...2).compactMap { distance in
            block + distance < blocks.count ? blocks[block + distance].key : nil
        }
        return ReadingAnchor(
            blockKey: blocks[block].key, blockIndex: block, offset: line.semanticOffset, previousKeys: previous,
            nextKeys: following, blockCount: blocks.count, verticalFraction: Double((y - line.top) / line.height))
    }

    func y(for anchor: ReadingAnchor) -> CGFloat? {
        guard anchor.verticalFraction.isFinite, let index = relocatedBlock(for: anchor), !blocks[index].lines.isEmpty
        else { return nil }
        let block = blocks[index]
        let semanticLength = block.textMap.string.utf16.count
        let offset = min(max(0, anchor.offset), max(0, semanticLength - 1))
        let rendered =
            block.textMap.renderedRange(for: NSRange(location: offset, length: semanticLength > 0 ? 1 : 0))?.location
            ?? 0
        guard
            let line = block.lines.first(where: { NSLocationInRange(rendered, $0.range) })
                ?? block.lines.first(where: { $0.range.location >= rendered })
                ?? block.lines.last
        else { return nil }
        let result = line.top + CGFloat(anchor.verticalFraction) * line.height
        return result.isFinite ? result : nil
    }

    private func relocatedBlock(for anchor: ReadingAnchor) -> Int? {
        guard !blocks.isEmpty else { return nil }
        let denominator = anchor.blockCount > 1 ? Double(anchor.blockCount - 1) : 1
        let ratio = min(1, max(0, Double(anchor.blockIndex) / denominator))
        let expected = ratio * Double(max(0, blocks.count - 1))
        func closest(_ candidates: [Int], score: (Int) -> Int) -> Int? {
            candidates.filter { blocks[$0].lines.count > 0 }.min { a, b in
                let aScore = score(a)
                let bScore = score(b)
                if aScore != bScore { return aScore > bScore }
                let aDistance = abs(Double(a) - expected)
                let bDistance = abs(Double(b) - expected)
                return aDistance == bDistance ? a < b : aDistance < bDistance
            }
        }
        if let matches = indicesByKey[anchor.blockKey],
            let match = closest(matches, score: { neighborScore(at: $0, anchor: anchor) })
        {
            return match
        }

        var votes: [Int: Int] = [:]
        for (distance, key) in anchor.previousKeys.prefix(2).enumerated() {
            for match in indicesByKey[key] ?? [] {
                let candidate = match + distance + 1
                if candidate < blocks.count { votes[candidate, default: 0] += 2 - distance }
            }
        }
        for (distance, key) in anchor.nextKeys.prefix(2).enumerated() {
            for match in indicesByKey[key] ?? [] {
                let candidate = match - distance - 1
                if candidate >= 0 { votes[candidate, default: 0] += 2 - distance }
            }
        }
        if let neighbor = closest(Array(votes.keys), score: { votes[$0] ?? 0 }) { return neighbor }
        return closest(Array(blocks.indices), score: { _ in 0 })
    }

    private func neighborScore(at index: Int, anchor: ReadingAnchor) -> Int {
        var score = 0
        for (distance, key) in anchor.previousKeys.prefix(2).enumerated() {
            let candidate = index - distance - 1
            if candidate >= 0, blocks[candidate].key == key { score += 2 - distance }
        }
        for (distance, key) in anchor.nextKeys.prefix(2).enumerated() {
            let candidate = index + distance + 1
            if candidate < blocks.count, blocks[candidate].key == key { score += 2 - distance }
        }
        return score
    }
}
