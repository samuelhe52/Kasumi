import CoreText
import CryptoKit
import Foundation
import Testing

@testable import KasumiMarkdown

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

@Test func bundledDocumentFacesPreserveReferenceBytesAndResolveWithoutFallback() throws {
    let faces = try DocumentFonts.registerBundledFonts()
    let expected = [
        ("Regular", "44e64260716d8f2bbe412baa1ee99b7c995190ac4573177c24def0b9200438c7", false, false),
        ("Italic", "069bb27f48eb98a741715227fc6e4b7baf3639c29fc13925f70d1ed8884ac29a", false, true),
        ("Bold", "dd4f9b69f0b24f1fb9be8634abf1fce2009e5c68a30842a3e9f5d6e535900abd", true, false),
        ("BoldItalic", "556fd64655a92bd9f5485ae2c03f7b9cdaf745a27a91d7edb3c3abde997206d2", true, true)
    ]
    #expect(faces.count == 4)
    for (face, specification) in zip(faces, expected) {
        let (style, checksum, bold, italic) = specification
        let bytes = try Data(contentsOf: face.resourceURL)
        #expect(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() == checksum)
        let font = try #require(PlatformFont(name: "TeXGyrePagella-" + style, size: 16))
        #expect(font.fontName == face.postScriptName)
        #expect(font.familyName == "TeX Gyre Pagella")
        let ctFont = CTFontCreateWithName(font.fontName as CFString, 16, nil)
        #expect(CTFontGetUnitsPerEm(ctFont) == 1000)
        let traits = CTFontGetSymbolicTraits(ctFont)
        #expect(traits.contains(.traitBold) == bold)
        #expect(traits.contains(.traitItalic) == italic)
        let resolvedURL = try #require(CTFontCopyAttribute(ctFont, kCTFontURLAttribute) as? URL)
        #expect(try Data(contentsOf: resolvedURL) == bytes)
    }
    // Family selection used by the serif preset must choose the real regular
    // face, independently of the font being requested by PostScript name.
    let regular = try #require(PlatformFont(name: "TeX Gyre Pagella", size: 16))
    #expect(regular.fontName == "TeXGyrePagella-Regular")
}

@Test func documentFontRegistrationIsSafeForConcurrentLayoutRequests() async throws {
    let results = try await withThrowingTaskGroup(of: [DocumentFonts.Face].self) { group in
        for _ in 0..<24 { group.addTask { try DocumentFonts.registerBundledFonts() } }
        var results: [[DocumentFonts.Face]] = []
        for try await result in group { results.append(result) }
        return results
    }
    let first = try #require(results.first)
    #expect(results.count == 24)
    #expect(results.allSatisfy { $0 == first })
}
