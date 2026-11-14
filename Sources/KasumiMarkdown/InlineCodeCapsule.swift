import AppKit
import CoreText

extension NSAttributedString.Key {
    static let kasumiCodeCapsule = NSAttributedString.Key("KasumiCodeCapsule")
}

/// Padding occupies layout space without appearing in copied/searched text.
/// The code itself remains ordinary text, including when it wraps across lines.
final class InlineCodeCapsule: NSObject {
    let color: NSColor
    let padding: CGFloat
    let radius: CGFloat
    let ascent: CGFloat
    let descent: CGFloat
    init(color: NSColor, font: NSFont, padding: Double) {
        self.color = color; self.padding = font.pointSize * padding
        radius = font.pointSize * 0.2
        ascent = font.ascender; descent = -font.descender
    }
    func attributed(_ text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: spacer())
        result.append(text); result.append(spacer())
        result.addAttribute(.kasumiCodeCapsule, value: self, range: NSRange(location: 0, length: result.length))
        return result
    }
    private func spacer() -> NSAttributedString {
        let pointer = Unmanaged.passRetained(self).toOpaque()
        var callbacks = CTRunDelegateCallbacks(version: kCTRunDelegateVersion1, dealloc: {
            Unmanaged<InlineCodeCapsule>.fromOpaque($0).release()
        }, getAscent: { _ in 0 }, getDescent: { _ in 0 }, getWidth: {
            Unmanaged<InlineCodeCapsule>.fromOpaque($0).takeUnretainedValue().padding
        })
        guard let delegate = CTRunDelegateCreate(&callbacks, pointer) else {
            Unmanaged<InlineCodeCapsule>.fromOpaque(pointer).release()
            return NSAttributedString(string: "")
        }
        return NSAttributedString(string: "\u{FFFC}", attributes: [
            NSAttributedString.Key(kCTRunDelegateAttributeName as String): delegate,
            .kasumiSemanticText: "", .foregroundColor: NSColor.clear
        ])
    }
}
