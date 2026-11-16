import CoreText
import Foundation

/// Ordered, process-local lookup only. The library never downloads; a client
/// that registers or downloads a face makes it available to the next lookup.
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

    /// Openly licensed faces that stand in for Apple faces iOS only offers as
    /// an on-demand download. Apps may fetch them; the library never does.
    static let openSubstitutes = ["Songti SC": "Noto Serif SC", "Songti TC": "Noto Serif TC"]

    static func chain(for requested: String, role: Role, preferring preferred: Set<String> = []) -> [String] {
        switch role {
        case .latin: return [requested, "New York"]
        case .han:
            // The requested face and its open substitute, in the caller's order,
            // before the generic chain, so a Traditional preset stays Traditional.
            let pair = [requested] + [openSubstitutes[requested]].compactMap { $0 }
            return (pair.contains(where: preferred.contains) ? pair.reversed() : pair)
                + ["Songti SC", "Noto Serif SC", "PingFang SC", "Songti TC"]
        case .code: return [requested]
        }
    }

    static func resolve(_ requested: String, role: Role, preferring preferred: Set<String> = []) -> String {
        // Empty code family intentionally reaches monospacedSystemFont. The
        // other empty-family defaults have already been applied by Typography.
        firstAvailable(in: chain(for: requested, role: role, preferring: preferred)) ?? ""
    }
}
