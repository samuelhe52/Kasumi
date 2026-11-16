import CryptoKit
import Foundation

/// Immutable semantic data contains no Core Text layout objects. The same values
/// can be read by independently locked snapshots while their geometry differs.
final class ParagraphSemanticContent {
    let textMap: DocumentTextMap
    let readingKey: String

    init(_ attributed: NSAttributedString) {
        textMap = DocumentTextMap(attributed)
        readingKey = SHA256.hash(data: Data(textMap.string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

final class DocumentSemanticContent {
    let textMap: DocumentTextMap
    let text: String
    let boundaries: [Int]

    init(_ textMap: DocumentTextMap) {
        self.textMap = textMap
        // place() appends a storage separator after each paragraph. The last
        // separator is not document content and must not create a phantom caret.
        text = textMap.string.hasSuffix("\n") ? String(textMap.string.dropLast()) : textMap.string
        var offset = 0
        var boundaries = [0]
        for character in text {
            offset += String(character).utf16.count
            boundaries.append(offset)
        }
        self.boundaries = boundaries
    }
}
