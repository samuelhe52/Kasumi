import Foundation
import Testing

@testable import KasumiMarkdown

@Suite struct DocumentLanguageTests {
    @Test func frontMatterPrecedenceNormalizesTagsAndPreservesSourceLines() {
        let source =
            "---\r\nlang: 'de-DE' # explicit\r\nname: ignored\r\n---\r\n# 汉字 Café 👩‍💻\r\n\r\nle les pour avec dans une cette nous vous sont\r\n"
        let document = MarkdownDocument(markdown: source)
        #expect(document.automaticHyphenationLanguage == "de-1996")
        #expect(document.parsed.languageAnalysis.origin == .frontMatter)
        #expect(document.parsed.languageAnalysis.sampledScalars == 0)
        #expect(document.parsed.blocks.first?.text == "汉字 Café 👩‍💻")
        #expect(document.parsed.blocks.first?.sourceLines?.lowerBound == 5)
        #expect(!document.parsed.blocks.contains { $0.kind == .rule })
        #expect(MarkdownDocument(markdown: "---\nlang: en-GB\n---\nText").automaticHyphenationLanguage == "en-gb")
        #expect(MarkdownDocument(markdown: "\u{FEFF}---\nlang: ru\n...\nТекст").automaticHyphenationLanguage == "ru")
        let unclosed = "---\nlang: fr\nText"
        #expect(DocumentFrontMatter.extract(unclosed).markdown == unclosed)
    }

    @Test func authoredProseSelectsEachSupportedLanguageFamily() {
        let samples = [
            "en-us": "The text is for the reader and this is a document with their words, which are not from a model.",
            "de-1996":
                "Der Text ist für die Leser und wird mit einer Sprache auf dieser Seite dargestellt. Auch werden die Wörter nicht verändert.",
            "fr":
                "Les mots de cette page sont pour les lecteurs avec une langue dans le document. Nous vous montrons ce texte et pas un modèle.",
            "es":
                "Los textos del documento son para los lectores con una lengua que se muestra en esta página, pero no cambia sus palabras.",
            "it":
                "Gli esempi della pagina sono per il lettore con una lingua che non cambia nel documento. Questo testo è anche nella guida.",
            "pt":
                "Os textos dos documentos são para os leitores com uma língua que não muda. Este exemplo é da página, mas está em uma guia.",
            "nl":
                "Het document wordt voor de lezer met een taal weergegeven. Deze woorden zijn niet van een model en ook niet door een vertaler gemaakt.",
            "sv":
                "Det här är ett dokument för den som läser med en språkregel. Orden blir inte ändrade och kommer från texten, också på denna sida.",
            "da":
                "Det er et dokument for den som læser med en regel. Ordene bliver ikke ændret og kommer fra teksten, også på denne side og af hensyn til læseren.",
            "nb":
                "Det er et dokument for den som leser med en regel. Ordene blir ikke endret og kommer fra teksten, også på denne siden av boken for å være tydelig.",
            "fi":
                "Tämä on teksti joka ei ole käännös, mutta myös se voi olla esimerkki. Kun hän lukee, sekä sanat että sisältö ovat mukana.",
            "pl":
                "To jest tekst dla czytelnika, który nie jest tłumaczeniem. Na tej stronie są słowa oraz przykłady tego jak się czyta, ale bez zmian przez model.",
            "cs":
                "To je text pro čtenáře, který není překladem. Na této stránce jsou slova a také příklady jako v knize, ale ne jiné téma nebo model.",
            "ru":
                "Это текст для читателя, который не является переводом. Он и она читают на этой странице, но они также видят слова из книги и что есть в ней."
        ]
        for (language, prose) in samples {
            let document = MarkdownDocument(markdown: prose)
            #expect(document.automaticHyphenationLanguage == language, "Language: \(language)")
            #expect(document.parsed.languageAnalysis.origin == .stopwords, "Language: \(language)")
        }
    }

    @Test func weakMixedAndExcludedTextDoNotForceDetection() {
        for prose in ["", "hello", "de la", "the the the the the", "日本語の文章です。", "le les pour avec the which their with"]
        {
            let document = MarkdownDocument(markdown: prose)
            #expect(document.automaticHyphenationLanguage == "en-us")
            #expect(document.parsed.languageAnalysis.origin == .fallback)
        }
        let french = "le les pour avec dans cette nous vous sont"
        let code = String(repeating: "the and which their with ", count: 10).trimmingCharacters(in: .whitespaces)
        let document = MarkdownDocument(
            markdown:
                "```text\n\(code)\n```\n\n`\(code)` $\(code)$ [\(code)](https://example.com) ![\(code)](missing.png)\n\n\(french)"
        )
        #expect(document.automaticHyphenationLanguage == "fr")
        #expect(
            MarkdownDocument(markdown: "---\nlang: unsupported\n---\n" + french).automaticHyphenationLanguage == "fr")
        #expect(MarkdownDocument(plainText: french).automaticHyphenationLanguage == "fr")
    }

    @Test func boundedSampleAndCachedReflowHonorExplicitDictionary() throws {
        let french = String(repeating: "les mots sont pour vous avec une langue dans cette page. ", count: 1000)
        let document = MarkdownDocument(markdown: french + String(repeating: " the which their ", count: 1000))
        #expect(document.automaticHyphenationLanguage == "fr")
        #expect(document.parsed.languageAnalysis.sampledScalars <= DocumentLanguageAnalysis.sampleLimit)
        let hostile = DocumentLanguageAnalysis.analyze([
            DocumentBlock(id: 0, kind: .paragraph, runs: [InlineRun(String(repeating: "x", count: 1_000_000))])
        ])
        #expect(hostile.sampledScalars == DocumentLanguageAnalysis.sampleLimit)
        #expect(hostile.origin == .fallback)
        let cached = document.parsed.languageAnalysis
        let frenchPreset = try TypographyPreset(id: "fr", name: "French", toml: "[profile]\nhyphenation_language='fr'")
        let germanPreset = try TypographyPreset(
            id: "de", name: "German", toml: "[profile]\nhyphenation_language='de-1996'")
        let short = MarkdownDocument(markdown: "---\nlang: de\n---\ninternationalisation extraordinaire constitution")
        var different = false
        let autoPreset = try TypographyPreset(id: "auto", name: "Automatic", toml: "[profile]")
        for width: CGFloat in stride(from: 80, through: 240, by: 10) {
            let overridden = DocumentTypesetter.layout(
                short.parsed, width: width, style: RenderStyle(preset: frenchPreset).typography, insets: .zero)
            let german = DocumentTypesetter.layout(
                short.parsed, width: width, style: RenderStyle(preset: germanPreset).typography, insets: .zero)
            let automatic = DocumentTypesetter.layout(
                short.parsed, width: width, style: RenderStyle(preset: autoPreset).typography, insets: .zero)
            let de = german.paragraphs.flatMap { $0.paragraph.lines }
            let fr = overridden.paragraphs.flatMap { $0.paragraph.lines }
            #expect(automatic.paragraphs.flatMap { $0.paragraph.lines }.map(\.range) == de.map(\.range))
            different =
                different || fr.map(\.range) != de.map(\.range) || fr.map { $0.hyphen?.x } != de.map { $0.hyphen?.x }
        }
        #expect(different, "An explicit dictionary must override the declared document language")
        for width: CGFloat in [200, 360] {
            _ = RenderedDocument(document, width: width, style: RenderStyle())
            #expect(document.parsed.languageAnalysis == cached)
        }
    }

    @Test func scannerPreservesCaseRunBoundariesAndBudgets() {
        func analyze(_ runs: [InlineRun]) -> DocumentLanguageAnalysis {
            DocumentLanguageAnalysis.analyze([DocumentBlock(id: 0, kind: .paragraph, runs: runs)])
        }
        // Tokens continue across styled prose runs, but excluded runs separate
        // them. Unicode case mapping still applies after an ASCII run.
        let split = analyze([InlineRun("LE L"), InlineRun("ES POUR AVEC DANS CETTE NOUS VOUS SONT")])
        #expect(split.hyphenationLanguage == "fr")
        #expect(split.origin == .stopwords)
        let excluded = analyze([InlineRun("th"), InlineRun("ignored", traits: [.code]), InlineRun("e and which")])
        #expect(excluded.origin == .fallback)
        let german = "FÜR DER DIE DAS UND IST NICHT EIN EINE MIT VON AUF SICH AUCH ZU WIRD WERDEN"
        #expect(analyze([InlineRun("F"), InlineRun(String(german.dropFirst()))]).hyphenationLanguage == "de-1996")
        let russian =
            "ЭТО ТЕКСТ ДЛЯ ЧИТАТЕЛЯ КОТОРЫЙ НЕ ЯВЛЯЕТСЯ ПЕРЕВОДОМ ОН И ОНА ЧИТАЮТ НО ОНИ ТАКЖЕ ВИДЯТ ЧТО ЕСТЬ В НЕЙ"
        #expect(analyze([InlineRun(russian)]).hyphenationLanguage == "ru")
        let longToken = String(repeating: "x", count: 49) + "the"
        #expect(analyze([InlineRun(longToken + " and which")]).origin == .fallback)
        let wordBounded = analyze([
            InlineRun(String(repeating: "x ", count: DocumentLanguageAnalysis.wordLimit) + "the and which")
        ])
        #expect(wordBounded.sampledScalars == DocumentLanguageAnalysis.wordLimit * 2)
        #expect(wordBounded.origin == .fallback)
        // A token cut by the scalar budget must not contribute a partial vote.
        for prefix in ["", "中"] {
            let cut =
                prefix
                + String(repeating: " ", count: DocumentLanguageAnalysis.sampleLimit - 13 - prefix.unicodeScalars.count)
                + "the and whichX"
            let scalarBounded = analyze([InlineRun(cut)])
            #expect(scalarBounded.sampledScalars == DocumentLanguageAnalysis.sampleLimit)
            #expect(scalarBounded.origin == .fallback)
        }
    }
}
