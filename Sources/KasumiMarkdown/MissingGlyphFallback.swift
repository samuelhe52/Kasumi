import CoreText
import Foundation

enum MissingGlyphFallback {
    /// Distinct objects keep identical adjacent replacements separate in the
    /// semantic map. A missing grapheme contributes its original UTF-16 text.
    final class Source: NSObject {
        let text: String
        init(_ text: String) { self.text = text }
    }

    static func applying(to attributed: NSAttributedString) -> NSAttributedString {
        let original = attributed.string
        // Ordinary Latin text has no need for a second shaping pass. For other
        // scripts, check the selected font's coverage before consulting the cascade.
        guard original.utf8.contains(where: { $0 >= 0x80 }) else { return attributed }
        let source = original as NSString
        let whole = NSRange(location: 0, length: attributed.length)
        var mayNeedFallback = false
        attributed.enumerateAttribute(.font, in: whole) { value, range, stop in
            guard let value else { return }
            let font = value as! CTFont
            let coverage = CTFontCopyCharacterSet(font) as CharacterSet
            if source.substring(with: range).unicodeScalars.contains(where: {
                $0.value >= 0x80 && isVisible($0) && !coverage.contains($0)
            }) {
                mayNeedFallback = true
                stop.pointee = true
            }
        }
        guard mayNeedFallback else { return attributed }

        let line = CTLineCreateWithAttributedString(attributed)
        var missing = Set<NSRange>()
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let values = CTRunGetAttributes(run) as NSDictionary
            guard values[kCTRunDelegateAttributeName] == nil, let font = values[kCTFontAttributeName] else { continue }
            let lastResort = (CTFontCopyPostScriptName(font as! CTFont) as String) == "LastResort"
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            let glyphs = CTRunGetGlyphsPtr(run)
            var copiedGlyphs: [CGGlyph] = []
            if !lastResort && glyphs == nil {
                copiedGlyphs = [CGGlyph](repeating: 0, count: count)
                CTRunGetGlyphs(run, CFRange(), &copiedGlyphs)
            }
            for glyph in 0..<count where lastResort || (glyphs?[glyph] ?? copiedGlyphs[glyph]) == 0 {
                var location = 0
                CTRunGetStringIndices(run, CFRange(location: glyph, length: 1), &location)
                guard NSLocationInRange(location, whole) else { continue }
                // Core Text may emit invisible glyphs for variation selectors
                // or joiners. Check the indexed scalar before replacing its grapheme.
                let unit = source.character(at: location)
                let units = (0xd800...0xdbff).contains(unit) && location + 1 < whole.length ? 2 : 1
                let part = source.substring(with: NSRange(location: location, length: units))
                guard let scalar = part.unicodeScalars.first, scalar.value != 0xfffd || unit == 0xfffd,
                    isVisible(scalar)
                else { continue }
                missing.insert(source.rangeOfComposedCharacterSequence(at: location))
            }
        }
        guard !missing.isEmpty else { return attributed }

        let replacement = NSMutableAttributedString(attributedString: attributed)
        for range in missing.sorted(by: { $0.location > $1.location }) {
            var attributes = attributed.attributes(at: range.location, effectiveRange: nil)
            if attributes[.kasumiSemanticText] == nil {
                attributes[.kasumiSemanticText] = Source(
                    DocumentTextMap(attributed.attributedSubstring(from: range)).string)
            }
            replacement.replaceCharacters(in: range, with: NSAttributedString(string: "□", attributes: attributes))
        }
        return replacement
    }

    private static func isVisible(_ scalar: Unicode.Scalar) -> Bool {
        !scalar.properties.isDefaultIgnorableCodePoint && !CharacterSet.controlCharacters.contains(scalar)
    }
}
