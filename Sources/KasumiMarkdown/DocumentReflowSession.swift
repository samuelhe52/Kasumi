import Foundation

/// Retains width-independent text preparation across layouts of one document.
/// Create a new session when content, style, available fonts, or resources change.
/// Calls are serialized; returned snapshots remain independently immutable.
public actor DocumentReflowSession {
    private let document: MarkdownDocument
    private let style: RenderStyle
    private let scrollableTables: Bool
    private let preparation = ReflowPreparation()

    public init(_ document: MarkdownDocument, style: RenderStyle, scrollableTables: Bool = false) {
        self.document = document
        self.style = style
        self.scrollableTables = scrollableTables
    }

    public func render(width: CGFloat) -> RenderedDocument {
        autoreleasepool {
            RenderedDocument(
                document, width: width, style: style, scrollableTables: scrollableTables, preparation: preparation)
        }
    }
}

/// Confined to a session's actor. Only normalized text, fonts, and measured
/// cluster values persist; CTTypesetter/CTLine/CTRun objects belong to snapshots.
final class ReflowPreparation {
    private struct Key: Hashable {
        let block: Int
        let slot: Int
    }
    private struct Request: Equatable {
        let runs: [InlineRun]
        let size: Double?
        let heading: Bool
        let code: Bool
        let level: Int?
    }
    private struct Entry {
        let request: Request
        let attributed: NSAttributedString
    }
    private var attributes: [Key: Entry] = [:]
    private var paragraphs: [ObjectIdentifier: ParagraphPreparation] = [:]
    private var retained = Set<ObjectIdentifier>()
    private(set) var attributedBuilds = 0
    private(set) var shapedBuilds = 0

    func attributed(
        block: Int, slot: Int, runs: [InlineRun], size: Double?, heading: Bool, code: Bool, level: Int?,
        build: () -> NSAttributedString
    ) -> NSAttributedString {
        // Images depend on measure/resource availability. Math attachments own
        // Core Text lines, so they must not be shared by independent snapshots.
        guard !runs.contains(where: { !$0.traits.intersection([.image, .math]).isEmpty }) else { return build() }
        let key = Key(block: block, slot: slot)
        let request = Request(runs: runs, size: size, heading: heading, code: code, level: level)
        if let entry = attributes[key], entry.request == request { return entry.attributed }
        if let old = attributes[key] {
            let id = ObjectIdentifier(old.attributed)
            paragraphs[id] = nil
            retained.remove(id)
        }
        let attributed = NSAttributedString(attributedString: build())
        attributes[key] = Entry(request: request, attributed: attributed)
        retained.insert(ObjectIdentifier(attributed))
        attributedBuilds += 1
        return attributed
    }

    func paragraph(_ attributed: NSAttributedString, fontSize: CGFloat, verbatim: Bool) -> ParagraphPreparation? {
        let id = ObjectIdentifier(attributed)
        guard retained.contains(id) else { return nil }
        if let existing = paragraphs[id], existing.fontSize == fontSize, existing.verbatim == verbatim {
            return existing
        }
        let value = ParagraphPreparation(attributed, fontSize: fontSize, verbatim: verbatim)
        paragraphs[id] = value
        shapedBuilds += 1
        return value
    }
}

struct ParagraphPreparation {
    let attributed: NSAttributedString
    let hasRTL: Bool
    let fontSize: CGFloat
    let verbatim: Bool
    let input: ShapedParagraphInput?

    init(_ source: NSAttributedString, fontSize: CGFloat, verbatim: Bool) {
        self.fontSize = fontSize
        self.verbatim = verbatim
        attributed = TextUnderline.normalized(source)
        hasRTL = attributed.string.unicodeScalars.contains {
            (0x0590...0x08ff).contains($0.value) || (0xfb1d...0xfdff).contains($0.value)
                || (0xfe70...0xfefc).contains($0.value)
        }
        input =
            !verbatim && !hasRTL && attributed.length > 0
            ? ParagraphShaper.shape(attributed, fallbackSize: fontSize) : nil
    }
}
