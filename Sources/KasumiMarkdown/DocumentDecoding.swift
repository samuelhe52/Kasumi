import Foundation
import CoreFoundation

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
        case let .invalidData(encoding): "The document cannot be decoded as \(encoding.title). Choose another text encoding."
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
                return DecodedDocumentText(text: decoded.text, encoding: .utf16, isLossy: false, isGuessed: false, hadByteOrderMark: littleBOM || bigBOM)
            }
            let input = encoding == .utf8 && utf8BOM ? Data(data.dropFirst(3)) : data
            guard let selected = encoding.foundationEncoding, let text = String(data: input, encoding: selected) else { throw DocumentDecodingError.invalidData(encoding) }
            return DecodedDocumentText(text: text, encoding: encoding, isLossy: false, isGuessed: false, hadByteOrderMark: (encoding == .utf8 && utf8BOM) || (encoding == .utf16 && (littleBOM || bigBOM)))
        }
        if utf8BOM {
            let input = Data(data.dropFirst(3))
            let strict = String(data: input, encoding: .utf8)
            return DecodedDocumentText(text: strict ?? String(decoding: input, as: UTF8.self), encoding: .utf8, isLossy: strict == nil, isGuessed: false, hadByteOrderMark: true)
        }
        if littleBOM || bigBOM {
            let decoded = utf16(Data(data.dropFirst(2)), littleEndian: littleBOM)
            return DecodedDocumentText(text: decoded.text, encoding: .utf16, isLossy: decoded.lossy, isGuessed: false, hadByteOrderMark: true)
        }
        if let text = String(data: data, encoding: .utf8) {
            return DecodedDocumentText(text: text, encoding: .utf8, isLossy: false, isGuessed: false, hadByteOrderMark: false)
        }
        if let selected = DocumentTextEncoding.gb18030.foundationEncoding, let text = String(data: data, encoding: selected) {
            return DecodedDocumentText(text: text, encoding: .gb18030, isLossy: false, isGuessed: true, hadByteOrderMark: false)
        }
        return DecodedDocumentText(text: String(decoding: data, as: UTF8.self), encoding: .utf8, isLossy: true, isGuessed: false, hadByteOrderMark: false)
    }

    private static func utf16(_ data: Data, littleEndian: Bool) -> (text: String, lossy: Bool) {
        let input = [UInt8](data)
        var units: [UInt16] = [], index = 0
        units.reserveCapacity((input.count + 1) / 2)
        while index + 1 < input.count {
            let a = UInt16(input[index]), b = UInt16(input[index + 1])
            units.append(littleEndian ? a | b << 8 : a << 8 | b)
            index += 2
        }
        var lossy = index < input.count
        if lossy { units.append(0xFFFD) }
        index = 0
        while index < units.count {
            if (0xD800...0xDBFF).contains(units[index]) {
                if index + 1 < units.count, (0xDC00...0xDFFF).contains(units[index + 1]) { index += 2; continue }
                lossy = true
            } else if (0xDC00...0xDFFF).contains(units[index]) { lossy = true }
            index += 1
        }
        return (String(decoding: units, as: UTF16.self), lossy)
    }
}
