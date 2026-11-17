import CoreText
import Foundation

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

extension NSAttributedString.Key {
    static let kasumiMath = NSAttributedString.Key("KasumiMathAttachment")
    static let kasumiSemanticText = NSAttributedString.Key("KasumiSemanticText")
    static let kasumiMathColor = NSAttributedString.Key("KasumiMathColor")
}

final class MathAttachment: NSObject {
    let source: String
    let result: MathLayoutResult
    private let pointSize: CGFloat
    init(source: String, size: CGFloat, display: Bool, options: MathProfileOptions = .init()) {
        self.source = source
        self.pointSize = size
        self.result = MathTypesetter.layout(source, size: size, display: display, options: options)
    }

    func attributed(color: PlatformColor, fallbackFont: PlatformFont? = nil) -> NSAttributedString {
        let fallback = NSAttributedString(
            string: source,
            attributes: [
                .font: fallbackFont ?? PlatformFont.monospacedSystemFont(ofSize: pointSize * 0.88, weight: .regular),
                .foregroundColor: color
            ])
        // An unavailable glyph rejects the complete formula. Ordinary source
        // text remains selectable, searchable and able to wrap across lines.
        guard result.diagnostics.isEmpty else { return fallback }
        // The delegate owns its reference independently of attribute destruction
        // order; Core Text may retain a run after the source string is released.
        let pointer = Unmanaged.passRetained(self).toOpaque()
        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateVersion1,
            dealloc: { pointer in
                Unmanaged<MathAttachment>.fromOpaque(pointer).release()
            },
            getAscent: { pointer in
                Unmanaged<MathAttachment>.fromOpaque(pointer).takeUnretainedValue().result.box.ascent
            },
            getDescent: { pointer in
                Unmanaged<MathAttachment>.fromOpaque(pointer).takeUnretainedValue().result.box.descent
            },
            getWidth: { pointer in
                Unmanaged<MathAttachment>.fromOpaque(pointer).takeUnretainedValue().result.box.width
            })
        guard let delegate = CTRunDelegateCreate(&callbacks, pointer) else {
            Unmanaged<MathAttachment>.fromOpaque(pointer).release()
            return fallback
        }
        return NSAttributedString(
            string: "\u{FFFC}",
            attributes: [
                NSAttributedString.Key(kCTRunDelegateAttributeName as String): delegate,
                .kasumiMath: self, .kasumiSemanticText: source, .kasumiMathColor: color,
                .foregroundColor: PlatformColor.clear
            ])
    }
}

/// Owns the correspondence between Core Text's drawable storage and text that
/// users can search, copy, and read through accessibility. A formula occupies
/// one layout object but expands to its original TeX in the semantic stream.
struct DocumentTextMap: Equatable {
    private struct Segment: Equatable {
        let rendered: NSRange
        let semantic: NSRange
        let replacement: Bool
    }
    let string: String
    private let segments: [Segment]
    private let renderedLength: Int
    private let semanticLength: Int

    init(_ attributed: NSAttributedString) {
        var text = ""
        var segments: [Segment] = []
        var semanticLength = 0
        let source = attributed.string as NSString
        func append(_ part: String, range: NSRange, replacement: Bool) {
            let length = part.utf16.count
            segments.append(
                Segment(
                    rendered: range, semantic: NSRange(location: semanticLength, length: length),
                    replacement: replacement))
            text += part
            semanticLength += length
        }
        attributed.enumerateAttribute(.kasumiSemanticText, in: NSRange(location: 0, length: attributed.length)) {
            value, range, _ in
            let replacement = value as? String
            if let replacement, (range.location..<NSMaxRange(range)).allSatisfy({ source.character(at: $0) == 0xFFFC })
            {
                // NSAttributedString coalesces equal adjacent attribute values;
                // every attachment still contributes its own semantic text.
                for offset in range.location..<NSMaxRange(range) {
                    append(replacement, range: NSRange(location: offset, length: 1), replacement: true)
                }
            } else {
                append(replacement ?? source.substring(with: range), range: range, replacement: replacement != nil)
            }
        }
        self.string = text
        self.segments = segments
        renderedLength = attributed.length
        self.semanticLength = semanticLength
    }

    func semanticOffset(forRenderedOffset offset: Int) -> Int {
        let offset = min(renderedLength, max(0, offset))
        guard offset < renderedLength else { return semanticLength }
        var lower = 0
        var upper = segments.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if NSMaxRange(segments[middle].rendered) <= offset { lower = middle + 1 } else { upper = middle }
        }
        guard lower < segments.count else { return semanticLength }
        let segment = segments[lower]
        return segment.semantic.location + (segment.replacement ? 0 : offset - segment.rendered.location)
    }

    func substring(in renderedRange: NSRange) -> String {
        let selected = NSIntersectionRange(renderedRange, NSRange(location: 0, length: renderedLength))
        guard selected.length > 0 else { return "" }
        let text = string as NSString
        return segments.compactMap { segment -> String? in
            let overlap = NSIntersectionRange(selected, segment.rendered)
            guard overlap.length > 0 else { return nil }
            let range =
                segment.replacement
                ? segment.semantic
                : NSRange(
                    location: segment.semantic.location + overlap.location - segment.rendered.location,
                    length: overlap.length)
            return text.substring(with: range)
        }.joined()
    }

    func renderedRange(for semanticRange: NSRange) -> NSRange? {
        guard semanticRange.length > 0 else { return nil }
        var start: Int?
        var end = 0
        let first = firstSegment(endingAfter: semanticRange.location)
        for segment in segments[first...].prefix(while: { $0.semantic.location < NSMaxRange(semanticRange) }) {
            let overlap = NSIntersectionRange(semanticRange, segment.semantic)
            guard overlap.length > 0 else { continue }
            let range =
                segment.replacement
                ? segment.rendered
                : NSRange(
                    location: segment.rendered.location + overlap.location - segment.semantic.location,
                    length: overlap.length)
            start = min(start ?? range.location, range.location)
            end = max(end, NSMaxRange(range))
        }
        return start.map { NSRange(location: $0, length: end - $0) }
    }

    /// Carets at attachment interiors snap to the object's leading edge.
    func renderedOffset(forSemanticOffset offset: Int) -> Int {
        let offset = min(semanticLength, max(0, offset))
        guard offset < semanticLength else { return renderedLength }
        let index = firstSegment(endingAfter: offset)
        guard index < segments.count else { return renderedLength }
        let segment = segments[index]
        return segment.rendered.location + (segment.replacement ? 0 : offset - segment.semantic.location)
    }

    /// Semantic intervals are ordered and disjoint, with possible empty spans
    /// for synthetic padding. Skip those at the queried boundary as well.
    private func firstSegment(endingAfter offset: Int) -> Int {
        var lower = 0
        var upper = segments.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if NSMaxRange(segments[middle].semantic) <= offset { lower = middle + 1 } else { upper = middle }
        }
        return lower
    }

    func matches(_ query: String) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let text = string as NSString
        var start = 0
        var result: [NSRange] = []
        while start < text.length {
            let match = text.range(
                of: query, options: [.caseInsensitive, .diacriticInsensitive],
                range: NSRange(location: start, length: text.length - start))
            if match.location == NSNotFound { break }
            if let rendered = renderedRange(for: match) { result.append(rendered) }
            start = NSMaxRange(match)
        }
        return result
    }
}
