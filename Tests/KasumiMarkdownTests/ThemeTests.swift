import CryptoKit
import Foundation
import ImageIO
import Testing

@testable import KasumiMarkdown

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

@Test func themeResourcePreservesEveryBundledColor() throws {
    let expected = [
        "mono-dark": "f7abcef16e94dc66306dd69a5355be5143fe3409b59dd595e32e26d7a206a864",
        "mono-light": "aa2d3263246f4c51e6d962e6a32695928ab07e7ca916003afda45646fe736de3",
        "one-dark": "c9f7b36788025ee9fe6eb6e92b6a35a2f266778612b643693ae385305377881c",
        "one-light": "984c7fd8814ab31c5e9fe17c4b834c01ecfdf8d76ec62163ebb155d1a9dfdae6",
        "solarized-dark": "09a21ad00752094348f76fdd3ec6159f373a6a2c2b12a5f1827eff75131a05d7",
        "solarized-light": "b22967146a158c189c67125f5215db28df19aa91d9f5da8c88aa150cf159c5cc"
    ]
    let object = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: DocumentThemeCatalog.resourceURL)) as? [String: Any])
    let rows = try #require(object["themes"] as? [[String: Any]])
    #expect(rows.count == 8)
    #expect(Set(DocumentThemeCatalog.themes.map(\.id)).count == 8)
    for row in rows {
        let id = try #require(row["id"] as? String)
        guard let colorHash = expected[id] else { continue }
        var facts: [String] = []
        for section in ["document", "chrome", "syntax"] {
            let values = try #require(row[section] as? [String: String])
            facts += values.keys.sorted().map { "\(section).\($0)=\(values[$0]!)" }
        }
        let hash = SHA256.hash(data: Data(facts.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }
            .joined()
        #expect(hash == colorHash, "All authored color facts for \(id)")
        let theme = DocumentThemeCatalog.theme(id: id, dark: false)
        #expect(theme.document.count == (id.hasPrefix("mono-") ? 46 : 45))
        #expect(theme.syntax.count == 5)
        #expect(theme.chrome.count == 3)
        #expect(theme.dark == id.hasSuffix("-dark"))
        // Decoded model colors must preserve the original sRGB byte values.
        for section in ["document", "chrome", "syntax"] {
            let values = try #require(row[section] as? [String: String])
            for (key, hex) in values {
                let expectedColor = try #require(DocumentColor(hex: hex))
                let color = try #require(theme.color(key)?.kasumiSRGB)
                #expect(abs(color.redComponent - expectedColor.red) < 1e-12)
                #expect(abs(color.greenComponent - expectedColor.green) < 1e-12)
                #expect(abs(color.blueComponent - expectedColor.blue) < 1e-12)
                #expect(color.alphaComponent == 1)
            }
        }
    }
}

@Test func themeClassicPreservesSemanticRolesAndNativeLiteralSpaces() throws {
    for dark in [false, true] {
        let classic = DocumentThemeCatalog.theme(id: "default-" + (dark ? "dark" : "light"), dark: !dark)
        #expect(classic.document.count == 62)
        #expect(classic.syntax.count == 5)
        #expect(classic.chrome.isEmpty)
        #if canImport(AppKit)
            let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
            let semantic: [String: PlatformColor] = [
                "paper": .textBackgroundColor, "text": .textColor,
                "heading": .textColor, "inline_code": .textColor, "link": .linkColor,
                "secondary_text": .secondaryLabelColor, "rule": .separatorColor
            ]
            for (key, native) in semantic {
                var expected: PlatformColor?
                appearance.performAsCurrentDrawingAppearance { expected = native.kasumiSRGB }
                let expectedColor = try #require(expected)
                let actual = try #require(classic.color(key))
                #expect(abs(actual.redComponent - expectedColor.redComponent) < 1e-12)
                #expect(abs(actual.greenComponent - expectedColor.greenComponent) < 1e-12)
                #expect(abs(actual.blueComponent - expectedColor.blueComponent) < 1e-12)
                #expect(actual.alphaComponent == expectedColor.alphaComponent)
            }
        #else
            let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
            let semantic: [String: UIColor] = [
                "paper": .systemBackground, "text": .label,
                "heading": .label, "inline_code": .label, "link": .link,
                "secondary_text": .secondaryLabel, "rule": .separator
            ]
            for (key, native) in semantic {
                let expected = PlatformColors.srgb(native.resolvedColor(with: traits).cgColor)
                #expect(classic.document[key] == expected)
            }
        #endif
        let codeBackground = try #require(classic.document["code_block_background"])
        #expect(
            codeBackground
                == (dark
                    ? DocumentColor(red: 0.145, green: 0.15, blue: 0.165)
                    : DocumentColor(red: 0.958, green: 0.961, blue: 0.969)))
        // The table initializer explicitly uses Generic RGB, unlike code blocks.
        let component: CGFloat = dark ? 0.1259303879737854 : 0.96
        let generic = CGColor(
            colorSpace: CGColorSpace(name: "kCGColorSpaceGenericRGB" as CFString)!,
            components: [component, component, component, 1])!
        let converted = PlatformColors.srgb(generic)
        let table = try #require(classic.color("table_header_background"))
        #expect(abs(table.redComponent - converted.red) < 1e-12)
        #expect(abs(table.greenComponent - converted.green) < 1e-12)
        #expect(abs(table.blueComponent - converted.blue) < 1e-12)
        // Generic RGB requires one conversion, then must survive native-color
        // and sRGB-helper round trips without introducing further drift.
        var roundTrip = converted
        for _ in 0..<4 {
            let native = try #require(roundTrip.nsColor.kasumiSRGB)
            roundTrip = PlatformColors.srgb(native.cgColor)
            #expect(roundTrip == converted)
        }
        #expect(classic.document["diagram_series_ink"] == DocumentColor(red: 0, green: 0, blue: 0))
    }
}

@Test func themeResolutionUsesNativeSparseOverlayAndAppearanceFallback() throws {
    for dark in [false, true] {
        let base = DocumentThemeCatalog.theme(id: "unknown", dark: dark)
        #expect(base.id == (dark ? "default-dark" : "default-light"))
        #expect(DocumentThemeCatalog.resolved(id: "unknown", dark: dark) == base)
        for family in ["one", "solarized", "mono"] {
            let id = family + (dark ? "-dark" : "-light")
            let raw = DocumentThemeCatalog.theme(id: id, dark: !dark)
            let effective = DocumentThemeCatalog.resolved(id: id, dark: !dark)
            #expect(effective.id == id)
            #expect(effective.dark == dark)
            #expect(effective.document.count == 62)
            #expect(effective.chrome == raw.chrome)
            #expect(effective.syntax == raw.syntax)
            for (key, color) in raw.document { #expect(effective.document[key] == color) }
            for index in 1...8 {
                for kind in ["fill", "edge"] {
                    let key = "diagram_series_\(index)_\(kind)"
                    #expect(raw.document[key] == nil)
                    #expect(effective.document[key] == base.document[key])
                }
            }
            if family != "mono" {
                #expect(raw.document["inline_code"] == nil)
                #expect(effective.document["inline_code"] == base.document["text"])
                #expect(effective.document["inline_code"] != raw.document["text"])
            }
            #expect(effective.color("absent") == nil)
        }
    }
}

@Test func themeColorCodableRejectsMalformedDataAndRetainsAlpha() throws {
    let decoder = JSONDecoder()
    let color = try decoder.decode(DocumentColor.self, from: Data("\"#12345678\"".utf8))
    #expect(color == DocumentColor(red: 18.0 / 255, green: 52.0 / 255, blue: 86.0 / 255, alpha: 120.0 / 255))
    #expect(try decoder.decode(DocumentColor.self, from: JSONEncoder().encode(color)) == color)
    for invalid in ["\"#xyzxyz\"", "\"#12345\"", "{\"red\":2,\"green\":0,\"blue\":0}"] {
        #expect(throws: DecodingError.self) { try decoder.decode(DocumentColor.self, from: Data(invalid.utf8)) }
    }
}

@Test func builtinThemePairsCoverEachAppearanceExactlyOnce() {
    let pairs = DocumentThemePair.builtin
    #expect(Set(pairs.map(\.id)) == Set(["default", "mono", "one", "solarized"]))
    #expect(Set(pairs.flatMap { [$0.light.id, $0.dark.id] }) == Set(DocumentTheme.builtin.map(\.id)))
    for pair in pairs {
        #expect(pair.light.appearance == .light && pair.dark.appearance == .dark)
        #expect(pair.light.id == pair.id + "-light" && pair.dark.id == pair.id + "-dark")
        #expect(!pair.name.contains("Light") && !pair.name.contains("Dark"))
    }
    for preset in TypographyPreset.builtin {
        #expect(preset.defaultFontSize == CGFloat(Typography().applying(preset.values).size))
    }
}

@Test func themeFileLoadsSparsePairsAndKeepsBuiltinCatalogIndependent() throws {
    let builtin = DocumentTheme.builtin
    let url = testRepositoryURL.appendingPathComponent("fixtures/CustomTheme.json")
    let pair = try DocumentThemePair(contentsOf: url)
    #expect(pair.id == "ink" && pair.name == "Ink")
    #expect(pair.light.appearance == .light && pair.dark.appearance == .dark)
    #expect(pair.light.id == "ink-light" && pair.dark.id == "ink-dark")
    #expect(pair.light.document["paper"] == DocumentColor(hex: "#FFF8EA"))
    #expect(pair.dark.document["paper"] == DocumentColor(hex: "#182020"))
    #expect(pair.light.syntax["keyword"] == DocumentColor(hex: "#985030"))
    #expect(pair.light.document["rule"] == nil)
    for theme in [pair.light, pair.dark] {
        let typography = RenderStyle(theme: theme).typography
        let classic = DocumentThemeCatalog.theme(id: "default-" + theme.appearance.rawValue, dark: theme.dark)
        #expect(typography.documentTheme.document["rule"] == classic.document["rule"])
        let document = DocumentParser.parse("```swift\nlet word = \"value\"\n```")
        let layout = DocumentTypesetter.layout(document, width: 300, style: typography)
        let text = try #require(layout.paragraphs.first?.paragraph.attributed)
        let color = try #require(text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? PlatformColor)
        let expected = try #require(theme.syntax["keyword"])
        let actual = PlatformColors.srgb(color.cgColor)
        #expect(abs(actual.red - expected.red) < 1e-12)
        #expect(abs(actual.green - expected.green) < 1e-12)
        #expect(abs(actual.blue - expected.blue) < 1e-12)
    }
    #expect(DocumentTheme.builtin == builtin)
}

@Test func themeFileValidatesEnvelopeAndReusesNativeColorGrammar() throws {
    func file(_ palette: String, version: Int = 1, id: String = "test") -> Data {
        Data("{\"schema_version\":\(version),\"id\":\"\(id)\",\"name\":\"Test\",\"light\":\(palette),\"dark\":{}}".utf8)
    }
    let pair = try DocumentThemePair(json: file(##"{"document":{"text":{"system":"textColor"},"paper":{"space":"sRGB","rgba":[0.1,0.2,0.3,0.4]}}}"##))
    #expect(pair.light.document["text"] == DocumentThemeCatalog.theme(id: "default-light", dark: false).document["text"])
    #expect(pair.light.document["paper"] == DocumentColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4))
    for palette in [
        ##"{"document":{"paper":"#xyz"}}"##,
        ##"{"document":{"paper":{"space":"sRGB","rgba":[1,2,3,4]}}}"##,
        ##"{"document":{"paper":{"system":"notAColor"}}}"##,
        ##"{"document":{"paper":{"space":"unknown","rgba":[0,0,0,1]}}}"##,
        ##"{"syntax":{"keyword":false}}"##
    ] { #expect(throws: (any Error).self) { _ = try DocumentThemePair(json: file(palette)) } }
    #expect(throws: DocumentThemeFileError.self) { _ = try DocumentThemePair(json: file("{}", version: 2)) }
    #expect(throws: DocumentThemeFileError.self) { _ = try DocumentThemePair(json: file("{}", id: " ")) }
    #expect(throws: (any Error).self) { _ = try DocumentThemePair(json: Data(##"{"schema_version":1,"id":"x","name":"X","light":{}}"##.utf8)) }
    #expect(throws: DocumentThemeFileError.self) { _ = try DocumentThemePair(json: Data(repeating: 32, count: 4 * 1024 * 1024 + 1)) }
}

@Test func themeFileCLISelectsAppearanceAndRejectsConflictingSelections() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = directory.appendingPathComponent("input.md")
    try "A custom theme.\n\n```swift\nlet word = \"value\"\n```".write(to: input, atomically: true, encoding: .utf8)
    let file = testRepositoryURL.appendingPathComponent("fixtures/CustomTheme.json").path
    let output = directory.appendingPathComponent("output.png")
    for (arguments, expected): ([String], [UInt8]) in [
        (["--theme-file", file], [255, 248, 234]),
        (["--dark", "--theme-file", file], [24, 32, 32]),
        (["--theme-file", file, "--dark"], [24, 32, 32])
    ] {
        _ = try await RenderCommand.run(["KasumiRender", input.path, output.path, "240"] + arguments)
        let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let context = try #require(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixel = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        for index in 0..<3 { #expect(abs(Int(pixel[index]) - Int(expected[index])) <= 1) }
    }
    for arguments in [["--theme", "one-light", "--theme-file", file], ["--theme-file", file, "--theme", "one-dark"]] {
        await #expect(throws: (any Error).self) {
            try await RenderCommand.run(["KasumiRender", input.path, output.path] + arguments)
        }
    }
}
