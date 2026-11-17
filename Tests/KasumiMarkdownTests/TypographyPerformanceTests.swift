import Foundation
import Testing

@testable import KasumiMarkdown

@Suite struct TypographyPerformanceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["KASUMI_TYPOGRAPHY_BENCHMARKS"] == "1"))
    func boundedAnalysisAndPunctuationCosts() {
        func measure(_ name: String, repeats: Int = 15, _ work: () -> Int) {
            var times: [Double] = []
            var checksum = 0
            _ = work() // Warm static tables and font caches outside measurement.
            for _ in 0..<repeats {
                let start = ContinuousClock.now
                checksum &+= work()
                let elapsed = start.duration(to: .now).components
                times.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
            }
            times.sort()
            print(String(format: "TYPOGRAPHY_BENCH %@ median_ms=%.4f p95_ms=%.4f checksum=%d", name, times[times.count / 2], times[min(times.count - 1, Int(Double(times.count) * 0.95))], checksum))
        }
        let prose = "Les mots de cette page sont pour les lecteurs avec une langue dans le document. Nous vous montrons ce texte et pas un modèle. "
        for length in [2_048, 32_768, 1_000_000] {
            let text = String(String(repeating: prose, count: length / prose.count + 1).prefix(length))
            let blocks = [DocumentBlock(id: 0, kind: .paragraph, runs: [InlineRun(text)])]
            measure("language_\(length)_chars") {
                let result = DocumentLanguageAnalysis.analyze(blocks)
                return result.sampledScalars + result.hyphenationLanguage.utf8.count
            }
        }
        let english = String(String(repeating: "The text is for the reader and this is a document with their words. ", count: 10).prefix(512))
        let blocks = (0..<1_000).map { DocumentBlock(id: $0, kind: .paragraph, runs: [InlineRun(english)]) }
        measure("language_1000_paragraphs_512_chars", repeats: 10) { DocumentLanguageAnalysis.analyze(blocks).sampledScalars }
        let chinese = String(String(repeating: "中文,混排 with English words. 这里有(例子),数字 3.14 和保护的内容! ", count: 20).prefix(512))
        let runs = [InlineRun(chinese)]
        for strategy in ["faithful", "fold", "spacing"] {
            measure("punctuation_plan_1000_paragraphs_\(strategy)", repeats: 10) {
                var marks = 0
                for _ in 0..<1_000 {
                    marks += PunctuationPlan.make(runs: runs, strategy: strategy)?.offsets[0].count ?? 0
                }
                return marks
            }
        }
        let document = DocumentParser.parse(Array(repeating: chinese, count: 50).joined(separator: "\n\n"))
        for strategy in ["faithful", "fold", "spacing"] {
            let style = Typography().applying(ProfileValues([
                .punctStrategy: .string(strategy), .hanFamily: .string("PingFang SC")
            ]))
            measure("layout_50_paragraphs_512_chars_\(strategy)", repeats: 5) {
                let layout = DocumentTypesetter.layout(document, width: 500, style: style)
                return layout.paragraphs.count + Int(layout.height)
            }
        }
    }
}
