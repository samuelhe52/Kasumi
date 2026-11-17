import CoreFoundation
import Foundation

/// Decoded source plus its original bytes and encoding. Reading alone never
/// changes a file; edited output preserves its encoding and byte-order mark.
public struct DocumentSource: Sendable {
    public let text: String
    public let isLossy: Bool
    private let original: Data
    private let encoding: String.Encoding
    private let prefix: Data

    public init(text: String) {
        self.text = text
        isLossy = false
        original = Data(text.utf8)
        encoding = .utf8
        prefix = Data()
    }

    public init(data: Data) throws {
        let decoded = try DocumentDecoder.decode(data)
        text = decoded.text
        isLossy = decoded.isLossy
        original = data
        if decoded.encoding == .utf16 {
            let little = data.starts(with: [0xFF, 0xFE])
            encoding = little ? .utf16LittleEndian : .utf16BigEndian
            prefix = Data(data.prefix(2))
        } else {
            encoding = decoded.encoding.foundationEncoding ?? .utf8
            prefix = decoded.hadByteOrderMark ? Data(data.prefix(3)) : Data()
        }
    }

    /// Returns the exact original bytes for a no-op edit. Throws instead of
    /// silently replacing characters that the original encoding cannot store.
    public func data(replacingText replacement: String) throws -> Data {
        // Swift String equality treats canonically equivalent Unicode as equal;
        // source editing must distinguish their actual scalar sequences.
        if replacement.utf8.elementsEqual(text.utf8) { return original }
        guard !isLossy else { throw SourceWriteError.lossySource }
        guard let bytes = replacement.data(using: encoding, allowLossyConversion: false),
            let roundTrip = String(data: bytes, encoding: encoding),
            roundTrip.utf8.elementsEqual(replacement.utf8)
        else { throw SourceWriteError.unrepresentableText }
        return prefix + bytes
    }

    private enum SourceWriteError: LocalizedError {
        case lossySource, unrepresentableText
        var errorDescription: String? {
            switch self {
            case .lossySource:
                "The original file contains undecodable bytes and cannot be edited safely."
            case .unrepresentableText:
                "Some characters cannot be saved in this file’s original text encoding."
            }
        }
    }
}

public enum DocumentTextEncoding: String, Codable, CaseIterable, Hashable, Sendable {
    case automatic, utf8, gb18030, big5, shiftJIS, eucKR, utf16

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .utf8: "UTF-8"
        case .gb18030: "GB18030"
        case .big5: "Big5"
        case .shiftJIS: "Shift_JIS"
        case .eucKR: "EUC-KR"
        case .utf16: "UTF-16"
        }
    }

    var foundationEncoding: String.Encoding? {
        switch self {
        case .automatic: nil
        case .utf8: .utf8
        case .utf16: .utf16
        case .shiftJIS: .shiftJIS
        // Core Foundation's published CFStringEncodingExt constants.
        case .gb18030: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(0x0632))
        case .big5: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(0x0A03))
        case .eucKR: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(0x0940))
        }
    }
}

struct DecodedDocumentText: Sendable {
    let text: String
    let encoding: DocumentTextEncoding
    let isLossy: Bool
    let isGuessed: Bool
    let hadByteOrderMark: Bool
}

enum DocumentDecodingError: LocalizedError {
    case invalidData(DocumentTextEncoding)
    var errorDescription: String? {
        switch self {
        case .invalidData(let encoding):
            "The document cannot be decoded as \(encoding.title). Choose another text encoding."
        }
    }
}

enum DocumentDecoder {
    /// Always decode original bytes, never a previously decoded String. The
    /// automatic order is BOM → UTF-8 → GB18030.
    static func decode(_ data: Data, encoding: DocumentTextEncoding = .automatic) throws -> DecodedDocumentText {
        let bytes = [UInt8](data.prefix(3))
        let utf8BOM = bytes.starts(with: [0xEF, 0xBB, 0xBF])
        let littleBOM = bytes.starts(with: [0xFF, 0xFE])
        let bigBOM = bytes.starts(with: [0xFE, 0xFF])
        if encoding != .automatic {
            if encoding == .utf16 {
                let decoded = utf16(Data(data.dropFirst(littleBOM || bigBOM ? 2 : 0)), littleEndian: littleBOM)
                guard !decoded.lossy else { throw DocumentDecodingError.invalidData(encoding) }
                return DecodedDocumentText(
                    text: decoded.text, encoding: .utf16, isLossy: false, isGuessed: false,
                    hadByteOrderMark: littleBOM || bigBOM)
            }
            let input = encoding == .utf8 && utf8BOM ? Data(data.dropFirst(3)) : data
            guard let selected = encoding.foundationEncoding, let text = String(data: input, encoding: selected) else {
                throw DocumentDecodingError.invalidData(encoding)
            }
            return DecodedDocumentText(
                text: text, encoding: encoding, isLossy: false, isGuessed: false,
                hadByteOrderMark: (encoding == .utf8 && utf8BOM) || (encoding == .utf16 && (littleBOM || bigBOM)))
        }
        if utf8BOM {
            let input = Data(data.dropFirst(3))
            let strict = String(data: input, encoding: .utf8)
            return DecodedDocumentText(
                text: strict ?? String(decoding: input, as: UTF8.self), encoding: .utf8, isLossy: strict == nil,
                isGuessed: false, hadByteOrderMark: true)
        }
        if littleBOM || bigBOM {
            let decoded = utf16(Data(data.dropFirst(2)), littleEndian: littleBOM)
            return DecodedDocumentText(
                text: decoded.text, encoding: .utf16, isLossy: decoded.lossy, isGuessed: false, hadByteOrderMark: true)
        }
        if let text = String(data: data, encoding: .utf8) {
            return DecodedDocumentText(
                text: text, encoding: .utf8, isLossy: false, isGuessed: false, hadByteOrderMark: false)
        }
        if let selected = DocumentTextEncoding.gb18030.foundationEncoding,
            let text = String(data: data, encoding: selected)
        {
            return DecodedDocumentText(
                text: text, encoding: .gb18030, isLossy: false, isGuessed: true, hadByteOrderMark: false)
        }
        return DecodedDocumentText(
            text: String(decoding: data, as: UTF8.self), encoding: .utf8, isLossy: true, isGuessed: false,
            hadByteOrderMark: false)
    }

    private static func utf16(_ data: Data, littleEndian: Bool) -> (text: String, lossy: Bool) {
        let input = [UInt8](data)
        var units: [UInt16] = []
        var index = 0
        units.reserveCapacity((input.count + 1) / 2)
        while index + 1 < input.count {
            let a = UInt16(input[index])
            let b = UInt16(input[index + 1])
            units.append(littleEndian ? a | b << 8 : a << 8 | b)
            index += 2
        }
        var lossy = index < input.count
        if lossy { units.append(0xFFFD) }
        index = 0
        while index < units.count {
            if (0xD800...0xDBFF).contains(units[index]) {
                if index + 1 < units.count, (0xDC00...0xDFFF).contains(units[index + 1]) {
                    index += 2
                    continue
                }
                lossy = true
            } else if (0xDC00...0xDFFF).contains(units[index]) {
                lossy = true
            }
            index += 1
        }
        return (String(decoding: units, as: UTF16.self), lossy)
    }
}
