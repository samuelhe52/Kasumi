import Foundation
import Testing

@testable import KasumiMarkdown

// The bundled notices must reach the resource bundle with readable text for every
// distributed component, including the native libraries and the bundled fonts.
@Suite struct ThirdPartyNoticesTests {
    @Test func everyDocumentIsBundledWithItsText() {
        let components = ThirdPartyNotices.components()
        let names = Set(components.map(\.name))

        #expect(names.isSuperset(of: ["Swift Markdown", "TOMLDecoder", "TeX Gyre Pagella"]))
        for component in components {
            #expect(!component.documents.isEmpty, "\(component.name) has no notice documents")
            for document in component.documents {
                let text = ThirdPartyNotices.text(of: document)
                #expect(text?.isEmpty == false, "\(component.name): \(document.path) is missing or empty")
            }
        }
    }
}
