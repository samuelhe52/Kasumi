import Foundation

struct ParagraphInputCluster: Equatable, Sendable {
    var text: String
    var run: Int
    var advance: Float
    init(text: String, run: Int, advance: Float) {
        self.text = text
        self.run = run
        self.advance = advance
    }
}

struct ParagraphRunMetrics: Equatable, Sendable {
    var spaceAdvance: Float
    var hyphenAdvance: Float
    var em: Float
    var isCode: Bool
    /// Original parser RunInfo flags: strong1, emphasis2, code4, link8,
    /// footnote0x10, image0x20, math0x40. Not internal classifier byte flags.
    var flags: UInt32
    init(spaceAdvance: Float, hyphenAdvance: Float, em: Float, isCode: Bool, flags: UInt32 = 0) {
        self.spaceAdvance = spaceAdvance
        self.hyphenAdvance = hyphenAdvance
        self.em = em
        self.isCode = isCode
        self.flags = flags
    }
}

struct ParagraphFragment: Equatable, Sendable {
    var run: Int
    var clusterRange: Range<Int>
    var x: Float
    var width: Float
    var drawDx: Float
    var capsuleLeft: Float
    var capsuleRight: Float
}

struct ParagraphEngineLine: Equatable, Sendable {
    var clusterRange: Range<Int> = 0..<0
    var fragments: [ParagraphFragment]
    var storedRatio: Float
    var hyphenX: Float?
    var hyphenRun: Int?
}

struct ParagraphEngineResult: Equatable, Sendable {
    var lines: [ParagraphEngineLine]
    var autoRagged: Bool
    /// Explicit limits of the currently translated native algorithm. A caller
    /// can report these without treating a successful layout as parity proof.
    var diagnostics: [ParagraphEngineDiagnostic]
}

enum ParagraphEngineDiagnostic: String, Equatable, Sendable {
    case invalidInput
    case unicodeBreakPolicy
    case dictionaryHyphenation
    case emergencyFallback
    case unsupportedRunFlags
}

/// Portable box/glue/penalty paragraph layout. Shaping and drawing are supplied
/// by the caller; this module has no CoreText dependency. The item/DP/emission
/// contract is exercised by frozen authored reference cases, with remaining
/// Unicode and fallback limits explicit.
enum ParagraphEngine {
    private enum Kind { case box, glue, penalty }
    private struct Item {
        var kind: Kind
        var width: Float = 0
        var stretch: Float = 0
        var shrink: Float = 0
        var penalty: Float = 0
        var flagged = false
        var range: Range<Int>
        var run: Int
        var dx: Float = 0
        var left: Float = 0
        var right: Float = 0
    }
    private struct Unit {
        var index: Int
        var scalar: UInt32
        var script: Int
        var side: Int  // opening0, closing1, ordinary2
        var advance: Float
        var excess: Float
        var air: Float
        var run: Int
    }
    private struct Node {
        var end: Int
        var predecessor: Int
        var cost: Float
        var fitness: Int
        var flagged: Bool
        var ratio: Float
        var start: Int
    }
    private struct Totals {
        var width: Float = 0
        var stretch: Float = 0
        var shrink: Float = 0
        var infinite: Float = 0
    }
    private struct Break {
        var start: Int
        var end: Int
        var ratio: Float
        var allowHyphen = true
    }

    static func layout(
        clusters: [ParagraphInputCluster], runs: [ParagraphRunMetrics], width: Float,
        outerWidth: Float, baseEm: Float, alignment: ParagraphAlignment = .justified,
        indent: Float = 0, options: ParagraphProfileOptions = .init()
    ) -> ParagraphEngineResult {
        guard width.isFinite, width > 0, outerWidth.isFinite, baseEm.isFinite, indent.isFinite,
            clusters.allSatisfy({ runs.indices.contains($0.run) && $0.advance.isFinite && $0.advance >= 0 }),
            runs.allSatisfy({ $0.em.isFinite && $0.em > 0 && $0.spaceAdvance.isFinite && $0.hyphenAdvance.isFinite })
        else {
            return .init(lines: [], autoRagged: false, diagnostics: [.invalidInput])
        }
        guard !clusters.isEmpty else { return .init(lines: [], autoRagged: false, diagnostics: []) }
        var diagnostics: [ParagraphEngineDiagnostic] = []
        let total = clusters.reduce(Float(0)) { $0 + $1.advance }
        let code = clusters.reduce(Float(0)) { $0 + (runs[$1.run].isCode ? $1.advance : 0) }
        let codeRagged =
            alignment == .justified && options.raggedCodeFraction > 0 && total > 0
            && code / total >= options.raggedCodeFraction
        let effectiveEm = baseEm > 0 ? baseEm : (runs.first?.em ?? 16)
        let narrow =
            alignment == .justified && !codeRagged && options.autoRaggedNarrow
            && (outerWidth > 0 ? outerWidth : width) < effectiveEm * options.autoRaggedMeasureEm
        let ragged = alignment != .justified || codeRagged || narrow
        var items = makeItems(clusters, runs, indent, options, &diagnostics)
        // Last-line infinite glue absorbs positive remaining measure instead
        // of stretching the visible word/CJK spaces to the right margin.
        let end = clusters.count
        let run = clusters.last!.run
        items.append(Item(kind: .glue, stretch: 1_000_000, range: end..<end, run: run))
        items.append(Item(kind: .penalty, penalty: -10_000, range: end..<end, run: run))
        let breaks = selectBreaks(
            items, width, (runs.first?.em ?? effectiveEm) * options.raggedStretch,
            ragged, options, &diagnostics)
        var consumed = 0
        let lines = breaks.map { point in
            var line = emit(point, items, clusters, runs, width, ragged, codeRagged, alignment, options)
            let upper = max(consumed, items[point.end].range.upperBound)
            line.clusterRange = consumed..<min(clusters.count, upper)
            consumed = min(clusters.count, upper)
            return line
        }
        return .init(lines: lines, autoRagged: narrow, diagnostics: diagnostics)
    }

    private static func makeItems(
        _ clusters: [ParagraphInputCluster], _ runs: [ParagraphRunMetrics], _ indent: Float,
        _ o: ParagraphProfileOptions, _ diagnostics: inout [ParagraphEngineDiagnostic]
    ) -> [Item] {
        let text = clusters.map(\.text).joined()
        var prefix = [0]
        for cluster in clusters { prefix.append(prefix.last! + cluster.text.utf8.count) }
        let allowedOffsets = Set(UnicodeLineBreak.boundaries(in: text).filter { !$0.mandatory }.map(\.offset))
        let hyphenOffsets = ParagraphHyphenation.opportunities(in: text, language: o.hyphenationLanguage)
        var items: [Item] = []
        if indent > 0 { items.append(Item(kind: .box, width: indent, range: 0..<0, run: 0)) }
        var previous: Unit?
        var pendingSpace: (start: Int, end: Int, run: Int)?
        func prohibited(_ at: Int, _ run: Int) {
            items.append(Item(kind: .penalty, penalty: 10_000, range: at..<at, run: run))
        }
        for (index, cluster) in clusters.enumerated() {
            let metric = runs[cluster.run]
            let scalar = cluster.text.unicodeScalars.first?.value ?? 0
            if scalar == 10 {
                pendingSpace = nil
                items.append(Item(kind: .glue, stretch: 1_000_000, range: index..<(index + 1), run: cluster.run))
                items.append(Item(kind: .penalty, penalty: -10_000, range: index..<(index + 1), run: cluster.run))
                previous = nil
                continue
            }
            if scalar == 32 || scalar == 9 {
                if let space = pendingSpace {
                    pendingSpace = (space.start, index + 1, space.run)
                } else {
                    pendingSpace = (index, index + 1, cluster.run)
                }
                continue
            }
            let script = scriptClass(scalar, metric)
            let side = punctuationSide(scalar)
            let excess = cluster.advance - metric.em * 0.5
            let compressed = side != 2 && excess > metric.em * 0.01 && metric.flags & 0x50 == 0
            let unit = Unit(
                index: index, scalar: scalar, script: script, side: compressed ? side : 2,
                advance: cluster.advance, excess: compressed ? excess : 0,
                air: compressed ? min(excess, o.punctuationCompression * metric.em) : 0, run: cluster.run)
            if metric.flags & 0xA0 != 0 && !diagnostics.contains(.unsupportedRunFlags) {
                diagnostics.append(.unsupportedRunFlags)
            }
            if let space = pendingSpace, runs[space.run].isCode {
                let owned = clusters[space.start..<space.end].reduce(Float(0)) { $0 + $1.advance }
                let leading = previous?.run != space.run && unit.run == space.run
                var seam: Float = 0
                var stretch: Float = 0
                var shrink: Float = 0
                if let left = previous {
                    let lm = runs[left.run]
                    let acrossScripts = left.script < 2 && unit.script == 2 || left.script == 2 && unit.script < 2
                    let em = left.script < 2 ? lm.em : metric.em
                    if acrossScripts {
                        seam = o.cjkLatinGap * em
                        stretch = o.glueStretch * em * 0.25
                        shrink = o.glueShrink * em * 0.03
                    }
                    if o.codeCapsule && (lm.isCode != metric.isCode || lm.isCode && left.run != unit.run) {
                        let minimum = (min(0.5, max(0, o.codeCapsulePad)) + 0.08) * (lm.isCode ? lm.em : metric.em)
                        seam = max(seam, minimum)
                        shrink = min(shrink, max(0, seam - minimum))
                    }
                }
                let white = Item(
                    kind: .glue, width: owned, range: space.start..<space.end, run: space.run,
                    left: leading ? 0 : owned, right: leading ? owned : 0)
                if leading {
                    if seam != 0 || stretch != 0 {
                        items.append(
                            Item(
                                kind: .glue, width: seam, stretch: stretch, shrink: shrink,
                                range: space.start..<space.start, run: space.run))
                    }
                    items.append(white)
                } else {
                    items.append(white)
                    if seam != 0 || stretch != 0 {
                        items.append(
                            Item(
                                kind: .glue, width: seam, stretch: stretch, shrink: shrink, range: index..<index,
                                run: unit.run))
                    }
                }
            } else if let space = pendingSpace, previous != nil {
                let m = runs[space.run]
                let left = previous!
                let acrossScripts = left.script < 2 && unit.script == 2 || left.script == 2 && unit.script < 2
                let em = left.script < 2 ? runs[left.run].em : metric.em
                var natural = acrossScripts ? o.cjkLatinGap * em : m.spaceAdvance
                var shrinking =
                    acrossScripts ? o.glueShrink * em * 0.03 : (m.isCode ? 0 : o.glueShrink * (m.spaceAdvance / 3))
                if o.codeCapsule
                    && (runs[left.run].isCode != metric.isCode || runs[left.run].isCode && left.run != unit.run)
                {
                    let codeEm = runs[left.run].isCode ? runs[left.run].em : metric.em
                    let minimum = (min(0.5, max(0, o.codeCapsulePad)) + 0.08) * codeEm
                    natural = max(natural, minimum)
                    shrinking = min(shrinking, max(0, natural - minimum))
                }
                items.append(
                    Item(
                        kind: .glue, width: natural,
                        stretch: o.glueStretch * (acrossScripts ? em * 0.25 : m.spaceAdvance * 0.5),
                        shrink: shrinking, range: space.start..<space.end, run: space.run))
            } else if let left = previous, hyphenOffsets.contains(prefix[index]),
                !runs[left.run].isCode, !metric.isCode,
                runs[left.run].flags & 0x10 == 0, metric.flags & 0x10 == 0
            {
                items.append(
                    Item(
                        kind: .penalty, width: runs[left.run].hyphenAdvance,
                        penalty: o.hyphenationPenalty, flagged: true, range: index..<index, run: left.run))
            } else if let left = previous {
                let lm = runs[left.run]
                let breakAllowed = allowedOffsets.contains(prefix[index])
                let sameWord = !breakAllowed && left.side == 2 && unit.side == 2
                let noBreak = !breakAllowed || left.side == 0 || unit.side == 1
                var air: Float = 0
                var shrink: Float = 0
                var stretch: Float = 0
                let asciiOpening = unit.script == 4 && [0x28, 0x5B, 0x7B].contains(unit.scalar)
                let asciiClosing = left.script == 4 && [0x29, 0x5D, 0x7D].contains(left.scalar)
                let cjkLatin =
                    left.script == 0 && unit.script == 2 || left.script == 2 && unit.script == 0
                    || left.script == 0 && asciiOpening
                    || asciiClosing && unit.script == 0
                if left.side == 1 && unit.side == 0 {
                    air = (left.air + unit.air) * 0.5
                    shrink = air * 0.5
                } else if unit.side == 0 {
                    air = unit.air
                    shrink = air
                } else if left.side == 1 && unit.side == 2 {
                    air = left.air
                    shrink = air
                }
                if cjkLatin {
                    let em = left.script < 2 ? lm.em : metric.em
                    air += o.cjkLatinGap * em
                    stretch = o.glueStretch * em * 0.25
                    shrink += o.glueShrink * em * 0.03
                } else if breakAllowed && left.script == 0 && unit.script == 0 && left.side == 2 && unit.side == 2 {
                    air += o.interCJKNatural * metric.em
                    stretch = o.glueStretch * o.interCJKStretch * metric.em
                    shrink += o.glueShrink * o.interCJKShrink * metric.em
                }
                if o.codeCapsule && (lm.isCode != metric.isCode || lm.isCode && left.run != unit.run) {
                    let em = lm.isCode ? lm.em : metric.em
                    let minimum = (min(0.5, max(0, o.codeCapsulePad)) + 0.08) * em
                    air = max(air, minimum)
                    shrink = min(shrink, max(0, air - minimum))
                }
                if air != 0 || stretch != 0 || shrink != 0 {
                    if noBreak { prohibited(index, cluster.run) }
                    items.append(
                        Item(
                            kind: .glue, width: air, stretch: stretch, shrink: shrink, range: index..<index,
                            run: cluster.run))
                } else if !sameWord && !noBreak {
                    items.append(Item(kind: .penalty, penalty: 0, range: index..<index, run: cluster.run))
                }
            } else if unit.side == 0 {
                items.append(
                    Item(kind: .glue, width: unit.air, shrink: unit.air, range: index..<index, run: cluster.run))
            }
            pendingSpace = nil
            let box = Item(
                kind: .box, width: unit.advance - unit.excess, range: index..<(index + 1), run: unit.run,
                dx: unit.side == 0 ? -unit.excess : 0)
            // Same-run ordinary letters form a single shaped box. A CJK box
            // stays separate even if its gap has zero natural width.
            if let last = items.last, last.kind == .box, last.run == unit.run, last.range.upperBound == index,
                last.dx == 0, unit.side == 2, previous?.side == 2
            {
                items[items.count - 1].range = last.range.lowerBound..<(index + 1)
                items[items.count - 1].width += box.width
            } else {
                items.append(box)
            }
            previous = unit
        }
        // Native long-box emergency opportunities are independent of measure:
        // only a multi-cluster box wider than four of its own run em qualifies.
        var rebuilt: [Item] = []
        for item in items {
            guard item.kind == .box, item.range.count >= 2, item.dx == 0,
                item.width > runs[item.run].em * 4
            else {
                rebuilt.append(item)
                continue
            }
            var start = item.range.lowerBound
            var accumulated: Float = 0
            for ci in item.range {
                let a = clusters[ci].advance
                if a > 0 && accumulated > 0 {
                    rebuilt.append(Item(kind: .box, width: accumulated, range: start..<ci, run: item.run))
                    rebuilt.append(Item(kind: .penalty, penalty: 900, range: ci..<ci, run: item.run))
                    rebuilt.append(Item(kind: .glue, stretch: runs[item.run].em * 0.02, range: ci..<ci, run: item.run))
                    start = ci
                    accumulated = 0
                }
                accumulated += a
            }
            rebuilt.append(Item(kind: .box, width: accumulated, range: start..<item.range.upperBound, run: item.run))
        }
        return rebuilt
    }

    private static func totals(_ items: [Item], _ range: Range<Int>) -> Totals {
        var t = Totals()
        for i in range {
            let item = items[i]
            if item.kind != .penalty { t.width += item.width }
            if item.kind == .glue {
                t.stretch += item.stretch
                t.shrink += item.shrink
                if item.stretch >= 1_000_000 { t.infinite += item.stretch }
            }
        }
        return t
    }
    private static func ratio(
        _ t: Totals, _ penaltyWidth: Float, _ width: Float, _ raggedStretch: Float, _ ragged: Bool,
        _ o: ParagraphProfileOptions
    ) -> Float {
        let delta = width - (t.width + penaltyWidth)
        if delta == 0 { return 0 }
        if delta > 0 {
            let capacity = ragged ? raggedStretch + t.infinite : t.stretch
            return capacity > 0 ? delta / capacity : 10_000
        }
        return t.shrink > 0 && (!ragged || o.raggedShrink) ? delta / t.shrink : -10_000
    }
    private static func postBreak(_ end: Int, _ items: [Item]) -> Int {
        var start = end
        if items.indices.contains(start), items[start].kind == .penalty { start += 1 }
        while items.indices.contains(start), items[start].kind == .glue { start += 1 }
        return start
    }
    private static func selectBreaks(
        _ items: [Item], _ width: Float, _ raggedStretch: Float, _ ragged: Bool,
        _ o: ParagraphProfileOptions, _ diagnostics: inout [ParagraphEngineDiagnostic]
    ) -> [Break] {
        var nodes = [Node(end: 0, predecessor: -1, cost: 0, fitness: 1, flagged: false, ratio: 0, start: 0)]
        var active = [0]
        var deferredRescue: Int?
        let tolerance = max(0.1, o.tolerance)
        let hardLimit = max(15, tolerance)
        for end in items.indices {
            let item = items[end]
            guard
                item.kind == .penalty && item.penalty < 10_000
                    || item.kind == .glue && end > 0 && items[end - 1].kind == .box
            else { continue }
            let forced = item.kind == .penalty && item.penalty <= -10_000
            let previousActive = active.isEmpty ? deferredRescue.map { [$0] } ?? [] : active
            deferredRescue = nil
            var best = [Node?](repeating: nil, count: 4)
            var remaining: [Int] = []
            for prior in previousActive {
                let start = prior == 0 ? 0 : postBreak(nodes[prior].end, items)
                guard start <= end else { continue }
                let t = totals(items, start..<end)
                let r = ratio(t, item.kind == .penalty ? item.width : 0, width, raggedStretch, ragged, o)
                if r >= -1 && !forced { remaining.append(prior) }
                let accepted = r >= -1 && (r <= hardLimit || r == 10_000 || forced)
                guard accepted else { continue }
                let magnitude = abs(r)
                var badness = magnitude * magnitude * magnitude * 100
                if r > tolerance { badness += 10_000 }
                var term = o.linePenalty + badness
                if item.kind == .penalty && item.penalty >= 0 { term += item.penalty }
                var cost = term * term
                if item.kind == .penalty && item.penalty > -10_000 && item.penalty < 0 {
                    cost -= item.penalty * item.penalty
                }
                cost += nodes[prior].cost
                let fitness = r < -0.5 ? 0 : r <= 0.5 ? 1 : r <= 1 ? 2 : 3
                if abs(fitness - nodes[prior].fitness) > 1 { cost += o.fitnessDemerits }
                if nodes[prior].flagged && item.flagged { cost += o.doubleHyphenDemerits }
                if forced && nodes[prior].flagged { cost += o.finalHyphenDemerits }
                if ragged && o.raggedShortLinePenalty > 0 && t.width / width < 0.5 {
                    let extra = o.raggedShortLinePenalty * min(1, max(0, (0.5 - t.width / width) * 2))
                    // Native applies this before squaring; keep this branch
                    // explicit rather than adding a post-hoc line length cost.
                    cost += (term + extra) * (term + extra) - term * term
                }
                if best[fitness] == nil || cost < best[fitness]!.cost {
                    best[fitness] = Node(
                        end: end, predecessor: prior, cost: cost, fitness: fitness, flagged: item.flagged, ratio: r,
                        start: start)
                }
            }
            active = remaining
            for value in best.compactMap({ $0 }) {
                active.append(nodes.count)
                nodes.append(value)
            }
            if active.isEmpty,
                let prior = previousActive.max(by: {
                    nodes[$0].end == nodes[$1].end ? nodes[$0].cost > nodes[$1].cost : nodes[$0].end < nodes[$1].end
                })
            {
                let start = prior == 0 ? 0 : postBreak(nodes[prior].end, items)
                var next = end + 1
                while items.indices.contains(next), items[next].kind == .glue { next += 1 }
                let nextIsForced =
                    items.indices.contains(next) && items[next].kind == .penalty && items[next].penalty <= -10_000
                let total = totals(items, min(start, end)..<end)
                // Native defers a discretionary break when only its hyphen
                // would overflow an otherwise shrinkable/fitting prefix.
                let hyphenWouldOverflow =
                    item.kind == .penalty && item.width > 0
                    && (item.width > width
                        || total.width - total.shrink <= width && total.width + item.width - total.shrink > width)
                if !forced && (start >= end || nextIsForced || hyphenWouldOverflow) {
                    deferredRescue = prior
                    continue
                }
                if start <= end {
                    let raw = ratio(total, item.width, width, raggedStretch, ragged, o)
                    let clipped = max(-1, min(hardLimit, raw))
                    let fitness = clipped < -0.5 ? 0 : clipped <= 0.5 ? 1 : clipped <= 1 ? 2 : 3
                    active = [nodes.count]
                    nodes.append(
                        Node(
                            end: end, predecessor: prior, cost: nodes[prior].cost, fitness: fitness,
                            flagged: item.flagged, ratio: raw, start: start))
                }
            }
            if active.isEmpty {
                // This is the explicitly identified native emergency-policy
                // gap. Use legal item candidates, never split measured clusters.
                if !diagnostics.contains(.emergencyFallback) { diagnostics.append(.emergencyFallback) }
                return emergencyBreaks(items, width)
            }
        }
        guard let finish = active.min(by: { nodes[$0].cost < nodes[$1].cost }) else { return [] }
        var result: [Break] = []
        var cursor = finish
        while cursor != 0 {
            let n = nodes[cursor]
            result.append(Break(start: n.start, end: n.end, ratio: n.ratio))
            cursor = n.predecessor
        }
        return result.reversed()
    }
    private static func emergencyBreaks(_ items: [Item], _ width: Float) -> [Break] {
        var result: [Break] = []
        var start = 0
        var candidate: Int?
        for i in items.indices {
            let item = items[i]
            let legal =
                item.kind == .penalty && item.penalty < 10_000
                || item.kind == .glue && i > 0 && items[i - 1].kind == .box
            guard legal else { continue }
            if totals(items, start..<i).width + (item.kind == .penalty ? item.width : 0) > width,
                let previous = candidate, previous > start
            {
                result.append(Break(start: start, end: previous, ratio: 0, allowHyphen: false))
                start = postBreak(previous, items)
            }
            candidate = i
            if item.kind == .penalty && item.penalty <= -10_000 {
                result.append(Break(start: min(start, i), end: i, ratio: 0, allowHyphen: false))
                start = postBreak(i, items)
                candidate = nil
            }
        }
        return result
    }

    private static func emit(
        _ line: Break, _ items: [Item], _ clusters: [ParagraphInputCluster], _ runs: [ParagraphRunMetrics],
        _ width: Float, _ ragged: Bool, _ codeRagged: Bool, _ alignment: ParagraphAlignment,
        _ o: ParagraphProfileOptions
    ) -> ParagraphEngineLine {
        var geometry =
            ragged
            ? (o.raggedShrink ? max(-1, min(0, line.ratio)) : 0) : max(-1, min(max(0.1, o.tolerance), line.ratio))
        let boundary = items[line.end]
        let hyphen = line.allowHyphen && boundary.kind == .penalty && boundary.flagged
        if !ragged && o.hangingPunctuation,
            let last = items[line.start..<line.end].last(where: { $0.kind == .box && !$0.range.isEmpty }),
            runs[last.run].flags & 0x40 == 0, let ci = last.range.last
        {
            let allowance =
                hangingFraction(clusters[ci].text.unicodeScalars.first?.value ?? 0)
                * (last.range.count == 1 ? last.width : clusters[ci].advance)
            if allowance > 0 {
                let t = totals(items, line.start..<line.end)
                geometry = max(
                    -1,
                    min(max(0.1, o.tolerance), ratio(t, hyphen ? boundary.width : 0, width + allowance, 0, false, o)))
            }
        }
        var fragments: [ParagraphFragment] = []
        var cursor: Float = 0
        var correction: Float = 0
        var pendingCapsule: (run: Int, amount: Float)?
        for index in line.start..<line.end {
            let item = items[index]
            if item.kind == .box {
                if item.range.isEmpty && item.width < 0 {
                    correction += item.width
                    continue
                }
                fragments.append(
                    .init(
                        run: item.run, clusterRange: item.range, x: cursor, width: item.width, drawDx: item.dx,
                        capsuleLeft: pendingCapsule?.run == item.run ? pendingCapsule!.amount : 0, capsuleRight: 0))
                pendingCapsule = nil
                cursor += item.width
            } else if item.kind == .glue {
                let amount = item.width + geometry * (geometry >= 0 ? item.stretch : item.shrink)
                let positive = max(0, amount)
                let left = min(item.left, positive)
                if left > 0, let last = fragments.indices.last, fragments[last].run == item.run {
                    fragments[last].capsuleRight += left
                }
                let right = min(item.right, max(0, positive - left))
                if right > 0 {
                    pendingCapsule = (item.run, (pendingCapsule?.run == item.run ? pendingCapsule!.amount : 0) + right)
                }
                cursor += amount
            }
        }
        var hyphenX: Float? = hyphen ? cursor : nil
        if alignment == .centered {
            let offset = max(0, (width - (cursor + correction + (hyphen ? boundary.width : 0))) * 0.5)
            for i in fragments.indices { fragments[i].x += offset }
            if hyphenX != nil { hyphenX! += offset }
        }
        return .init(
            fragments: fragments, storedRatio: codeRagged ? geometry : line.ratio,
            hyphenX: hyphenX, hyphenRun: hyphen ? boundary.run : nil)
    }

    private static func scriptClass(_ s: UInt32, _ m: ParagraphRunMetrics) -> Int {
        if m.flags & 0x50 != 0 { return 2 }
        if [0x3005, 0x3006, 0x3007, 0x303B].contains(s) { return 0 }
        if s == 9 || s == 32 { return 3 }
        if (0x3400...0x4DBF).contains(s) || (0x4E00...0x9FFF).contains(s) || (0xF900...0xFAFF).contains(s)
            || (0x3040...0x30FF).contains(s) || (0xAC00...0xD7AF).contains(s)
        {
            return 0
        }
        if (0x3000...0x303F).contains(s) || (0xFF01...0xFF60).contains(s) { return 1 }
        if (0x30...0x39).contains(s) || (0x41...0x5A).contains(s) || (0x61...0x7A).contains(s)
            || (0xC0...0x24F).contains(s)
        {
            return 2
        }
        return 4
    }
    private static func punctuationSide(_ s: UInt32) -> Int {
        if openings.contains(s) { return 0 }
        if closings.contains(s) { return 1 }
        return 2
    }
    private static let openings: Set<UInt32> = [
        0x3008, 0x300A, 0x300C, 0x300E, 0x3010, 0x3014, 0x3016, 0x3018, 0x301A, 0x301D, 0xFF08, 0xFF3B, 0xFF5B, 0xFF5F,
        0xFF62
    ]
    private static let closings: Set<UInt32> = [
        0x3001, 0x3002, 0x3009, 0x300B, 0x300D, 0x300F, 0x3011, 0x3015, 0x3017, 0x3019, 0x301B, 0x301E, 0x301F, 0xFF01,
        0xFF09, 0xFF0C, 0xFF0E, 0xFF1A, 0xFF1B, 0xFF1F, 0xFF3D, 0xFF5D, 0xFF60, 0xFF61, 0xFF63, 0xFF64
    ]
    private static let halfHanging: Set<UInt32> = [
        0x21, 0x22, 0x27, 0x29, 0x3A, 0x3B, 0x3F, 0x5D, 0x2019, 0x201D, 0x3009, 0x300B, 0x300D, 0x300F, 0x3011, 0x3015,
        0x3017, 0x3019, 0x301B, 0x301E, 0x301F, 0xFF01, 0xFF09, 0xFF1A, 0xFF1B, 0xFF1F
    ]
    private static func hangingFraction(_ s: UInt32) -> Float {
        if [0x2C, 0x2E, 0x3001, 0x3002, 0xFF0C, 0xFF0E].contains(s) { return 1 }
        return halfHanging.contains(s) ? 0.5 : 0
    }
}
