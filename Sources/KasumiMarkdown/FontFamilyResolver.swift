import CoreText
import Foundation

/// Ordered, process-local lookup only. No UI font picker or downloadable-font API.
enum FontFamilyResolver {
    enum Role { case latin, han, code }

    // Registration and byte/provenance validation happen once. Bundled names
    // then use a set lookup instead of repeated registration or font matching.
    private static let bundledNames: Set<String> = {
        guard let faces = try? DocumentFonts.registerBundledFonts() else { return [] }
        return Set(faces.flatMap { [$0.familyName, $0.postScriptName] })
    }()

    static func isAvailable(_ family: String) -> Bool {
        if ["New York", "SF Pro", "SF Pro Text"].contains(family) { return true }
        if bundledNames.contains(family) { return true }
        // Do not cache system-font misses: a client may install a font later.
        guard let font = PlatformFonts.named(family, size: 16) else { return false }
        return CTFontCopyFamilyName(font as CTFont) as String == family || font.fontName == family
    }

    static func firstAvailable(in chain: [String], available: (String) -> Bool = isAvailable) -> String? {
        chain.first { !$0.isEmpty && available($0) }
    }

    static func resolve(_ requested: String, role: Role) -> String {
        let fallbacks: [String]
        switch role {
        case .latin: fallbacks = ["New York"]
        case .han: fallbacks = ["Songti SC", "PingFang SC", "Songti TC"]
        case .code: fallbacks = []
        }
        // Empty code family intentionally reaches monospacedSystemFont. The
        // other empty-family defaults have already been applied by Typography.
        return firstAvailable(in: [requested] + fallbacks) ?? ""
    }
}
