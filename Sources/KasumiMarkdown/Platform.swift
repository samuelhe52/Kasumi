import CoreGraphics
import CoreText
import Foundation

#if canImport(AppKit)
import AppKit
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
#else
import UIKit
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont

extension UIColor {
    convenience init(srgbRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(cgColor: CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha))
    }
}
#endif

/// Match a real face by name or family, without silently accepting a fallback.
enum PlatformFonts {
    static func named(_ name: String, size: CGFloat) -> PlatformFont? {
        guard !name.isEmpty else { return nil }
        for key in [kCTFontNameAttribute, kCTFontFamilyNameAttribute] {
            let descriptor = CTFontDescriptorCreateWithAttributes([key: name] as CFDictionary)
            if let match = CTFontDescriptorCreateMatchingFontDescriptor(descriptor, NSSet(object: key) as CFSet) {
                return CTFontCreateWithFontDescriptor(match, size, nil) as PlatformFont
            }
        }
        return nil
    }

    static func applying(_ traits: CTFontSymbolicTraits, to font: PlatformFont) -> PlatformFont {
        guard !traits.isEmpty,
              let converted = CTFontCreateCopyWithSymbolicTraits(font as CTFont, font.pointSize, nil, traits, traits) else { return font }
        return converted as PlatformFont
    }
}

/// Semantic colors are resolved from an explicit appearance, never app state.
enum PlatformColors {
    static func semantic(_ role: String, dark: Bool) -> CGColor {
        #if canImport(AppKit)
        let color: NSColor
        switch role {
        case "textBackgroundColor": color = .textBackgroundColor
        case "textColor": color = .textColor
        case "linkColor": color = .linkColor
        case "secondaryLabelColor": color = .secondaryLabelColor
        default: color = .separatorColor
        }
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var result: CGColor!
        appearance.performAsCurrentDrawingAppearance { result = color.usingColorSpace(.sRGB)!.cgColor }
        return result
        #else
        let color: UIColor
        switch role {
        case "textBackgroundColor": color = .systemBackground
        case "textColor": color = .label
        case "linkColor": color = .link
        case "secondaryLabelColor": color = .secondaryLabel
        default: color = .separator
        }
        return color.resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light)).cgColor
        #endif
    }

    static func srgbColor(_ color: CGColor) -> CGColor? {
        // Even a redundant color-space conversion can round the components.
        if color.colorSpace?.name == CGColorSpace.sRGB { return color }
        return color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)
    }

    static func srgb(_ color: CGColor) -> DocumentColor {
        let rgb = srgbColor(color)!
        let components = rgb.components!
        return DocumentColor(red: components[0], green: components[1], blue: components[2], alpha: rgb.alpha)
    }
}
