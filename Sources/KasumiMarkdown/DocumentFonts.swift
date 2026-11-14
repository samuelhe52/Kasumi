import CoreGraphics
import CoreText
import CryptoKit
import Foundation

/// Text faces used by document presets. Registration is process scoped; it does
/// not install fonts or change the user's font configuration.
enum DocumentFonts {
    struct Face: Sendable, Equatable {
        let fileName: String
        let familyName: String
        let styleName: String
        let postScriptName: String
        let sha256: String
        let resourceURL: URL
    }

    enum RegistrationError: Error, Sendable, Equatable, CustomStringConvertible {
        case missingResource(String)
        case invalidResource(file: String, reason: String)
        case registrationFailed(file: String, code: Int, reason: String)
        case unavailable(postScriptName: String, reason: String)

        var description: String {
            switch self {
            case .missingResource(let file): "Missing bundled document font: \(file)"
            case .invalidResource(let file, let reason): "Invalid bundled document font \(file): \(reason)"
            case .registrationFailed(let file, let code, let reason): "Cannot register document font \(file) (\(code)): \(reason)"
            case .unavailable(let name, let reason): "Document font \(name) is unavailable: \(reason)"
            }
        }
    }

    /// Registers all four unmodified TeX Gyre Pagella 2.501 text faces exactly
    /// once. Every caller receives the same success or explicit failure; no
    /// system-font substitution is reported as success.
    static func registerBundledFonts() throws -> [Face] {
        try registration.get()
    }

    // Swift static initialization serializes concurrent callers. Cache only
    // Sendable value metadata, rather than sharing mutable Core Text objects.
    private static let registration: Result<[Face], RegistrationError> = {
        do { return .success(try register()) }
        catch let error as RegistrationError { return .failure(error) }
        catch { return .failure(.invalidResource(file: "TeX Gyre Pagella", reason: String(describing: error))) }
    }()

    private static func register() throws -> [Face] {
        let specifications = [
            ("regular", "Regular", "Regular", "44e64260716d8f2bbe412baa1ee99b7c995190ac4573177c24def0b9200438c7"),
            ("italic", "Italic", "Italic", "069bb27f48eb98a741715227fc6e4b7baf3639c29fc13925f70d1ed8884ac29a"),
            ("bold", "Bold", "Bold", "dd4f9b69f0b24f1fb9be8634abf1fce2009e5c68a30842a3e9f5d6e535900abd"),
            ("bolditalic", "Bold Italic", "BoldItalic", "556fd64655a92bd9f5485ae2c03f7b9cdaf745a27a91d7edb3c3abde997206d2")
        ]
        // Validate the entire set before changing the process font registry.
        let faces = try specifications.map { fileStyle, style, nameStyle, checksum in
            let stem = "texgyrepagella-\(fileStyle)"
            let fileName = stem + ".otf"
            guard let url = Bundle.module.url(forResource: stem, withExtension: "otf", subdirectory: "Bundled") else {
                throw RegistrationError.missingResource(fileName)
            }
            guard let bytes = try? Data(contentsOf: url), digest(bytes) == checksum,
                  let provider = CGDataProvider(data: bytes as CFData), let graphicsFont = CGFont(provider) else {
                throw RegistrationError.invalidResource(file: fileName, reason: "Font bytes do not match the bundled face")
            }
            let font = CTFontCreateWithGraphicsFont(graphicsFont, 16, nil, nil)
            let postScriptName = "TeXGyrePagella-\(nameStyle)"
            guard CTFontCopyFamilyName(font) as String == "TeX Gyre Pagella",
                  CTFontCopyPostScriptName(font) as String == postScriptName else {
                throw RegistrationError.invalidResource(file: fileName, reason: "Unexpected font family or PostScript name")
            }
            return Face(fileName: fileName, familyName: "TeX Gyre Pagella", styleName: style,
                        postScriptName: postScriptName, sha256: checksum, resourceURL: url)
        }
        for face in faces {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(face.resourceURL as CFURL, .process, &error) {
                let detail = error?.takeRetainedValue()
                let code = detail.map(CFErrorGetCode) ?? -1
                // Another component may have registered the exact same face.
                // The resolution check below still verifies the actual bytes.
                guard code == CTFontManagerError.alreadyRegistered.rawValue else {
                    throw RegistrationError.registrationFailed(file: face.fileName, code: code,
                        reason: detail.map { CFErrorCopyDescription($0) as String } ?? "Unknown Core Text error")
                }
            }
            let font = CTFontCreateWithName(face.postScriptName as CFString, 16, nil)
            guard CTFontCopyPostScriptName(font) as String == face.postScriptName,
                  CTFontCopyFamilyName(font) as String == face.familyName,
                  let resolvedURL = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL,
                  let resolvedBytes = try? Data(contentsOf: resolvedURL), digest(resolvedBytes) == face.sha256 else {
                throw RegistrationError.unavailable(postScriptName: face.postScriptName,
                    reason: "Core Text did not resolve the unmodified bundled face")
            }
        }
        return faces
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
