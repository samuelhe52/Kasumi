import CryptoKit
import Foundation

/// Immutable semantic data contains no Core Text layout objects. The same values
/// can be read by independently locked snapshots while their geometry differs.
final class ParagraphSemanticContent {
    let textMap: DocumentTextMap
    let readingKey: String

    init(_ attributed: NSAttributedString) {
        textMap = DocumentTextMap(attributed)
        let digits = Array("0123456789abcdef".utf8)
        var hexadecimal: [UInt8] = []
        hexadecimal.reserveCapacity(64)
        for byte in SHA256.hash(data: Data(textMap.string.utf8)) {
            hexadecimal.append(digits[Int(byte >> 4)])
            hexadecimal.append(digits[Int(byte & 15)])
        }
        readingKey = String(decoding: hexadecimal, as: UTF8.self)
    }
}

final class DocumentSemanticContent {
    let textMap: DocumentTextMap
    let text: String

    init(_ textMap: DocumentTextMap, reusing previous: DocumentSemanticContent? = nil) {
        self.textMap = textMap
        // Refinement may replace raw semantic placeholders with attachments,
        // changing rendered offsets without changing semantic text.
        if let previous, textMap.string.utf8.elementsEqual(previous.textMap.string.utf8) {
            text = previous.text
            return
        }
        // place() appends a storage separator after each paragraph. The last
        // separator is not document content and must not create a phantom caret.
        text = textMap.string.hasSuffix("\n") ? String(textMap.string.dropLast()) : textMap.string
    }
}

/// UTF-16 arithmetic stays exact; only hit testing snaps to a grapheme. Query
/// the containing sequence instead of constructing a document-wide index.
enum SemanticTextBoundary {
    static func nearest(in text: NSString, to offset: Int) -> Int {
        guard offset > 0 else { return 0 }
        guard offset < text.length else { return text.length }
        // Foundation's composed-sequence query separates CR and LF; Swift
        // Character (and Unicode grapheme breaking) treats CRLF as one unit.
        if text.character(at: offset) == 10, text.character(at: offset - 1) == 13 { return offset - 1 }
        let range = text.rangeOfComposedCharacterSequence(at: offset)
        let end = NSMaxRange(range)
        return offset - range.location <= end - offset ? range.location : end
    }
}
