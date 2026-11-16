import Foundation
import Testing

@testable import KasumiMarkdown

fileprivate struct ParagraphNativeFixture: Decodable {
    var items: [Case]
    struct Cluster: Decodable {
        var text: String
        var run: Int
        var advance: Float
    }
    struct Metrics: Decodable {
        var spaceAdvance: Float
        var hyphenAdvance: Float
        var em: Float
        var isCode: Bool
        var flags: UInt32
    }
    struct Expected: Decodable {
        var autoRagged: Bool
        var lines: [Line]
    }
    struct Line: Decodable {
        var ratio: Float
        var hyphenX: Float?
        var hyphenRun: Int?
        var fragments: [[Float]]
    }
    struct Case: Decodable {
        var id: String
        var clusters: [Cluster]
        var runs: [Metrics]
        var width: Float
        var outerWidth: Float
        var baseEm: Float
        var alignment: Int
        var indent: Float
        var options: [String: ProfileValue]
        var expected: Expected
        var engineOptions: ParagraphProfileOptions {
            var o = ParagraphProfileOptions()
            for (key, value) in options {
                let f = Float(value.number ?? 0)
                switch key {
                case "tolerance": o.tolerance = f
                case "glue_stretch": o.glueStretch = f
                case "glue_shrink": o.glueShrink = f
                case "cjk_punct_compression": o.punctuationCompression = f
                case "cjk_latin_gap": o.cjkLatinGap = f
                case "inter_cjk_stretch": o.interCJKStretch = f
                case "inter_cjk_shrink": o.interCJKShrink = f
                case "inter_cjk_natural": o.interCJKNatural = f
                case "ragged_code_fraction": o.raggedCodeFraction = f
                case "auto_ragged_measure_em": o.autoRaggedMeasureEm = f
                case "auto_ragged_narrow": o.autoRaggedNarrow = value.flag ?? true
                case "hanging_punctuation": o.hangingPunctuation = value.flag ?? true
                case "ragged_shrink": o.raggedShrink = value.flag ?? false
                case "code_capsule": o.codeCapsule = value.flag ?? false
                case "code_capsule_pad": o.codeCapsulePad = f
                default: break
                }
            }
            return o
        }
        var actual: ParagraphEngineResult {
            ParagraphEngine.layout(
                clusters: clusters.map { .init(text: $0.text, run: $0.run, advance: $0.advance) },
                runs: runs.map {
                    .init(
                        spaceAdvance: $0.spaceAdvance, hyphenAdvance: $0.hyphenAdvance, em: $0.em, isCode: $0.isCode,
                        flags: $0.flags)
                },
                width: width, outerWidth: outerWidth, baseEm: baseEm,
                alignment: [ParagraphAlignment.justified, .leading, .centered, .trailing][alignment], indent: indent,
                options: engineOptions)
        }
    }
}

fileprivate func paragraphFixture() throws -> ParagraphNativeFixture {
    let root = testRepositoryURL
    return try JSONDecoder().decode(
        ParagraphNativeFixture.self,
        from: Data(contentsOf: root.appendingPathComponent("fixtures/reference/Paragraph.core.json")))
}
fileprivate func closeParagraphFloat(_ a: Float, _ b: Float) -> Bool {
    abs(b) == 10_000 ? a == b : abs(a - b) <= max(0.00005, abs(b) * 0.000005)
}

@Suite struct ParagraphEngineTests {
    @Test func frozenNativeParagraphGeometry() throws {
        let fixture = try paragraphFixture()
        var failures: [String] = []
        for sample in fixture.items {
            let actual = sample.actual
            let expected = sample.expected
            if actual.autoRagged != expected.autoRagged || actual.lines.count != expected.lines.count {
                failures.append(
                    "\(sample.id): line count \(actual.lines.count)/\(expected.lines.count), autoRagged \(actual.autoRagged)/\(expected.autoRagged)"
                )
                continue
            }
            var reason: String?
            for (a, e) in zip(actual.lines, expected.lines) {
                if !closeParagraphFloat(a.storedRatio, e.ratio) {
                    reason = "ratio \(a.storedRatio)/\(e.ratio)"
                    break
                }
                if a.hyphenRun != e.hyphenRun || (a.hyphenX == nil) != (e.hyphenX == nil) {
                    reason = "hyphen"
                    break
                }
                if let x = a.hyphenX, let y = e.hyphenX, !closeParagraphFloat(x, y) {
                    reason = "hyphen x"
                    break
                }
                if a.fragments.count != e.fragments.count {
                    reason = "fragment count \(a.fragments.count)/\(e.fragments.count)"
                    break
                }
                for (f, v) in zip(a.fragments, e.fragments) {
                    let values: [Float] = [
                        Float(f.run), Float(f.clusterRange.lowerBound), Float(f.clusterRange.upperBound), f.x, f.width,
                        f.drawDx, f.capsuleLeft, f.capsuleRight
                    ]
                    if zip(values, v).contains(where: { !closeParagraphFloat($0.0, $0.1) }) {
                        reason = "fragment \(values)/\(v)"
                        break
                    }
                }
                if reason != nil { break }
            }
            if let reason { failures.append("\(sample.id): \(reason)") }
        }
        #expect(
            failures.isEmpty,
            Comment(
                rawValue: "\(failures.count) / \(fixture.items.count) native mismatches:\n"
                    + failures.prefix(60).joined(separator: "\n")))
    }

    @Test func consumedClusterRangesIncludeHardBreakAndDiscardedSpaces() throws {
        let fixture = try paragraphFixture()
        let hard = try #require(fixture.items.first { $0.id == "paragraph-emission-cases/break-0-AA  \nBB CC" })
        #expect(hard.actual.lines.map(\.clusterRange) == [0..<3, 3..<8])
        let words = try #require(fixture.items.first { $0.id == "paragraph-cases/latin-25-align1" })
        #expect(words.actual.lines.map(\.clusterRange) == [0..<6, 6..<12, 12..<17])
    }

    @Test func compactnessResolvesNativeToleranceAndShrink() {
        let defaults = ParagraphProfileOptions(values: .init())
        #expect(defaults.tolerance == 10 && defaults.glueShrink == 1)
        let tight = ParagraphProfileOptions(values: .init([.compactness: .number(0)]))
        #expect(tight.tolerance == 2.5 && tight.glueShrink == 1.1)
        let loose = ParagraphProfileOptions(values: .init([.compactness: .number(1)]))
        #expect(loose.tolerance == 20 && loose.glueShrink == 1)
    }

    @Test func cjkLatinGapSkipsFullwidthPunctuation() {
        func latinX(after cjk: String, gap: Float) -> Float? {
            var options = ParagraphProfileOptions()
            options.cjkLatinGap = gap
            let result = ParagraphEngine.layout(
                clusters: [.init(text: cjk, run: 0, advance: 10), .init(text: "K", run: 0, advance: 6)],
                runs: [.init(spaceAdvance: 3, hyphenAdvance: 3, em: 10, isCode: false, flags: 0)], width: 100,
                outerWidth: 100, baseEm: 10, alignment: .leading, options: options)
            return result.lines.first?.fragments.first { $0.clusterRange.contains(1) }?.x
        }
        #expect(latinX(after: "中", gap: 0.25) != latinX(after: "中", gap: 0))
        #expect(latinX(after: "。", gap: 0.25) == latinX(after: "。", gap: 0))
    }

    @Test func invalidInputDoesNotIndexRunMemory() {
        let result = ParagraphEngine.layout(
            clusters: [.init(text: "a", run: 7, advance: 5)], runs: [], width: 20, outerWidth: 20, baseEm: 10)
        #expect(result.lines.isEmpty && result.diagnostics == [.invalidInput])
    }
}
