import Foundation
import Testing

@testable import KasumiMarkdown

// Frozen reference hyphenation observations.
fileprivate struct HyphenationNativeWord: Decodable {
    let language: String
    let word: String
    let offsets: [Int]
}

@Suite struct HyphenationTests {
    @Test func publicPresetSelectsDictionaryWithoutChangingSemanticText() throws {
        let source = String(repeating: "internationalisation extraordinaire constitution ", count: 6)
        let document = MarkdownDocument(markdown: source)
        let french = try TypographyPreset(id: "fr", name: "French", toml: "[profile]\nhyphenation_language = \"fr\"")
        let automatic = try TypographyPreset(id: "auto", name: "Automatic", toml: "[profile]\n")
        var differs = false
        for width in stride(from: 100, through: 220, by: 20) {
            let baseline = RenderedDocument(
                document, width: CGFloat(width), style: RenderStyle(preset: automatic, insets: .zero))
            let selected = RenderedDocument(
                document, width: CGFloat(width), style: RenderStyle(preset: french, insets: .zero))
            #expect(selected.text(in: selected.documentRange) == baseline.text(in: baseline.documentRange))
            differs =
                differs || selected.size.height != baseline.size.height
                || selected.selectionRects(for: selected.documentRange)
                    != baseline.selectionRects(for: baseline.documentRange)
        }
        #expect(differs, "Selecting French must reach actual paragraph layout")
        #expect(ProfileField.hyphenationLanguage.specification.choices.count == 16)
        for tag in ProfileField.hyphenationLanguage.specification.choices {
            let values = try ProfileValues.parse("[profile]\nhyphenation_language = \"\(tag)\"")
            #expect(ParagraphProfileOptions(values: values).hyphenationLanguage == tag)
        }
        #expect(
            ParagraphHyphenation.opportunities(in: "KasumiMarkdown")
                == ParagraphHyphenation.opportunities(in: "kasumimarkdown"))
        #expect(ParagraphHyphenation.opportunities(in: "macOS") == ParagraphHyphenation.opportunities(in: "macos"))
    }

    @Test func cliAcceptsExplicitDictionaryAndRejectsUnknownLanguage() async throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: output) }
        let input = testRepositoryURL.appendingPathComponent("fixtures/Profiles.md").path
        _ = try await RenderCommand.run(["KasumiRender", input, output.path, "160", "--hyphenation-language", "fr"])
        #expect(FileManager.default.fileExists(atPath: output.path))
        await #expect(throws: (any Error).self) {
            try await RenderCommand.run(["KasumiRender", input, output.path, "--hyphenation-language", "unknown"])
        }
    }

    @Test func frozenNativeWordsAcrossFifteenDictionaries() throws {
        let observations = #"""
            [
              {"language": "en-us","word": "supercalifragilisticexpialidocious","offsets": [2,5,8,13,17,20,22,24,27,29]},
              {"language": "en-gb","word": "supercalifragilisticexpialidocious","offsets": [2,5,8,9,12,15,20,22,24,26,29]},
              {"language": "en-us","word": "hyphenation","offsets": [2,6,7]},
              {"language": "en-us","word": "associate","offsets": [2,4,6]},
              {"language": "en-us","word": "project","offsets": [3]},
              {"language": "en-us","word": "table","offsets": []},
              {"language": "en-gb","word": "organisation","offsets": [2,5,8]},
              {"language": "de-1996","word": "Silbentrennung","offsets": [3,6,10]},
              {"language": "de-1996","word": "Straßenbahn","offsets": [4,8]},
              {"language": "de-1996","word": "STRAẞENBAHN","offsets": [4,9]},
              {"language": "de-1996","word": "STRASSENBAHN","offsets": [5,8]},
              {"language": "fr","word": "constitution","offsets": [6,8]},
              {"language": "fr","word": "algorithmique","offsets": [2,4,8]},
              {"language": "fr","word": "française","offsets": [4]},
              {"language": "fr","word": "internationalisation","offsets": [2,5,7,10,12,14,16]},
              {"language": "fr","word": "éléphant","offsets": [5]},
              {"language": "fr","word": "ordinateurs","offsets": [2,4,6]},
              {"language": "fr","word": "mathématiques","offsets": [2,6,8]},
              {"language": "es","word": "extraordinario","offsets": [2,5,7,9,11]},
              {"language": "es","word": "constitución","offsets": [4,6,8]},
              {"language": "it","word": "internazionale","offsets": [2,5,7,10,12]},
              {"language": "pt","word": "extraordinário","offsets": [2,5,7,9,12]},
              {"language": "nl","word": "lettergrepen","offsets": [3,6,9]},
              {"language": "sv","word": "internationella","offsets": [2,5,7,10,13]},
              {"language": "da","word": "orddeling","offsets": [3,5]},
              {"language": "nb","word": "orddeling","offsets": [3,5]},
              {"language": "fi","word": "tietokone","offsets": [3,5,7]},
              {"language": "pl","word": "międzynarodowy","offsets": [4,7,9,11,13]},
              {"language": "cs","word": "nejneobhospodařovávatelnější","offsets": [3,5,7,10,12,14,17,20,22,25]},
              {"language": "ru","word": "международный","offsets": [6,10,14,20]},
              {"language": "ru","word": "МЕЖДУНАРОДНЫЙ","offsets": [6,10,14,20]},
              {"language": "auto","word": "SUPERCALIFRAGILISTICEXPIALIDOCIOUS","offsets": [2,5,8,13,17,20,22,24,27,29]},
              {"language": "en-us","word": "İnternationalization","offsets": []},
              {"language": "en-us","word": "international1ization","offsets": []},
              {"language": "en-us","word": "internationaĺization","offsets": []},
              {"language": "en-us","word": "Kinternationalization","offsets": []},
              {"language": "ru","word": "internationalization","offsets": []},
              {"language": "de-1996","word": "международный","offsets": []},
              {"language": "en-us","word": "ab","offsets": []},
              {"language": "en-us","word": "abcde","offsets": []},
              {"language": "en-us","word": "extraordinary","offsets": [2,5,7,9]},
              {"language": "fr","word": "ÉLÉPHANT","offsets": [5]},
              {"language": "en-us","word": "encyclopedia","offsets": [2,4,7,9]},
              {"language": "fr","word": "domino","offsets": [2,4]},
              {"language": "fr","word": "cinéma","offsets": [2,5]}
            ]
            """#
        let cases = try JSONDecoder().decode([HyphenationNativeWord].self, from: Data(observations.utf8))
        for sample in cases {
            #expect(
                ParagraphHyphenation.opportunities(in: sample.word, language: sample.language) == Set(sample.offsets),
                "Native dictionary observation: \(sample.language), \(sample.word)")
        }
    }

    @Test func segmentationPreservesOriginalUTF8Coordinates() {
        let prefix = "👩🏽‍💻"
        let separator = " / "
        let word = "STRAẞENBAHN"
        let secondStart = prefix.utf8.count + word.utf8.count + separator.utf8.count
        let expected = Set([4, 9].map { prefix.utf8.count + $0 } + [3, 6, 10].map { secondStart + $0 })
        #expect(
            ParagraphHyphenation.opportunities(in: prefix + word + separator + "Silbentrennung", language: "DE")
                == expected)
        // Auto's ASCII scanner splits around non-ASCII letters as well as punctuation.
        #expect(ParagraphHyphenation.opportunities(in: "éhyphenation") == Set([4, 8, 9]))
        #expect(ParagraphHyphenation.opportunities(in: "extra\u{00AD}ordinary", language: "en-us") == Set([2, 9, 11]))
        #expect(ParagraphHyphenation.opportunities(in: "international1ization") == Set([2, 5, 7, 17]))
    }

    @Test func rejectsWholeWordsWithUnsupportedScalarContext() {
        for inserted in ["1", "\u{0301}", "\u{1AB0}", "\u{1DC0}", "\u{20D0}", "\u{FE20}"] {
            #expect(
                ParagraphHyphenation.opportunities(in: "international" + inserted + "ization", language: "en-us")
                    .isEmpty)
        }
        #expect(ParagraphHyphenation.opportunities(in: "İnternationalization", language: "en-us").isEmpty)
        #expect(ParagraphHyphenation.opportunities(in: "hyphenation中文", language: "en-us").isEmpty)
        let prefix = String(repeating: "中文", count: 2_048) + "hyphenation / "
        #expect(
            ParagraphHyphenation.opportunities(in: prefix + "hyphenation", language: "en-us")
                == Set([2, 6, 7].map { prefix.utf8.count + $0 }))
        #expect(ParagraphHyphenation.opportunities(in: "hyphenation", language: "not-a-language").isEmpty)
        #expect(ParagraphHyphenation.opportunities(in: "hyphenation", language: "EN-US") == Set([2, 6, 7]))
    }
}
