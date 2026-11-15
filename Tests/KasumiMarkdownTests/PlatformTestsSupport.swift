import CoreGraphics
import CoreText
import Testing

@testable import KasumiMarkdown

#if canImport(AppKit)
    import AppKit
#else
    import UIKit

    extension UIColor {
        var redComponent: CGFloat { cgColor.components![0] }
        var greenComponent: CGFloat { cgColor.components![1] }
        var blueComponent: CGFloat { cgColor.components![2] }
        var alphaComponent: CGFloat { cgColor.alpha }
    }
#endif

extension PlatformColor {
    var kasumiSRGB: PlatformColor? {
        guard let color = PlatformColors.srgbColor(cgColor) else { return nil }
        return PlatformColor(cgColor: color)
    }
}

extension CGColor {
    var kasumiSRGB: PlatformColor? {
        guard let color = PlatformColors.srgbColor(self) else { return nil }
        return PlatformColor(cgColor: color)
    }
}

/// macOS must exercise the reference faces even when one is unexpectedly absent.
/// iOS may omit these optional system faces; report each missing exact name.
func requiresReferenceFaces(_ postScriptNames: String...) -> ConditionTrait {
    #if os(iOS)
        let missing = postScriptNames.filter { name in
            let font = CTFontCreateWithName(name as CFString, 16, nil)
            return CTFontCopyPostScriptName(font) as String != name
        }
        return .enabled(
            if: missing.isEmpty,
            Comment(rawValue: "Missing iOS PostScript faces: " + missing.joined(separator: ", ")))
    #else
        return .enabled(if: true)
    #endif
}
