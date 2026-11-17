import CoreGraphics
import CoreText
import Foundation

/// Immutable code-block geometry and metadata in document coordinates. IDs
/// belong to this snapshot. Source is the complete parsed literal, without
/// Markdown fences or decorations, including its original trailing newlines.
public struct RenderedCodeBlock: Identifiable, Sendable {
    public let id: Int
    public let frame: CGRect
    public let contentFrame: CGRect
    public let captionFrame: CGRect?
    /// The fence's first info word, if present; no display-name policy is applied.
    public let language: String?
    public let source: String
}

struct CodeBlockLayout {
    let block: RenderedCodeBlock
    let labelFrame: CGRect?
    let label: CTLine?

    init(id: Int, frame: CGRect, contentFrame: CGRect, language: String?, source: String, style: Typography) {
        let caption = style.codeBlockStyle.resolved.caption
        let row = caption.map { CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: $0.height) }
        block = RenderedCodeBlock(
            id: id, frame: frame, contentFrame: contentFrame, captionFrame: row,
            language: language?.split(whereSeparator: \.isWhitespace).first.map(String.init), source: source)
        guard let caption, let row else {
            labelFrame = nil
            label = nil
            return
        }
        let left = min(caption.insets.left, contentFrame.width)
        let top = min(caption.insets.top, row.height)
        let labelBounds = CGRect(
            x: contentFrame.minX + left, y: row.minY + top,
            width: max(0, contentFrame.width - left - caption.insets.right),
            height: max(0, row.height - top - caption.insets.bottom))
        labelFrame = labelBounds
        let attributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: caption.fontSize, weight: .medium),
            .foregroundColor: style.secondaryColor
        ]
        let name = Self.languageLabel(block.language)
        let full = CTLineCreateWithAttributedString(
            MissingGlyphFallback.applying(to: NSAttributedString(string: name, attributes: attributes)))
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
        label =
            labelBounds.isEmpty
            ? nil
            : CTLineCreateTruncatedLine(full, Double(labelBounds.width), .end, ellipsis) ?? full
    }

    func drawLabel(in context: CGContext) {
        guard let labelFrame, let label, !labelFrame.isEmpty,
            labelFrame.intersects(context.boundingBoxOfClipPath)
        else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: labelFrame)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        _ = CTLineGetTypographicBounds(label, &ascent, &descent, nil)
        context.translateBy(x: labelFrame.minX, y: labelFrame.midY + (ascent - descent) / 2)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(label, context)
    }

    private static func languageLabel(_ language: String?) -> String {
        guard let word = language?.split(whereSeparator: \.isWhitespace).first else { return "Code" }
        // Fence info is untrusted and may be arbitrarily long. The displayed
        // caption is bounded; copying always uses the complete code literal.
        let tag = String(word.prefix(80))
        let names = [
            "rs": "Rust", "rust": "Rust", "swift": "Swift", "py": "Python", "python": "Python",
            "python3": "Python", "js": "JavaScript", "javascript": "JavaScript", "jsx": "JSX",
            "ts": "TypeScript", "typescript": "TypeScript", "tsx": "TSX", "sh": "Shell", "shell": "Shell",
            "bash": "Bash", "zsh": "Zsh", "c": "C", "cpp": "C++", "c++": "C++", "cs": "C#", "c#": "C#",
            "objc": "Objective-C", "objective-c": "Objective-C", "json": "JSON", "yaml": "YAML", "yml": "YAML",
            "toml": "TOML", "html": "HTML", "xml": "XML", "css": "CSS", "sql": "SQL", "go": "Go",
            "rb": "Ruby", "ruby": "Ruby", "java": "Java", "kotlin": "Kotlin", "mermaid": "Mermaid",
            "md": "Markdown", "markdown": "Markdown", "text": "Plain text", "txt": "Plain text",
            "plaintext": "Plain text", "plain": "Plain text", "none": "Plain text"
        ]
        return names[tag.lowercased()] ?? tag
    }
}
