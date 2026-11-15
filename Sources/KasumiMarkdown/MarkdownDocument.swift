import Foundation

/// Parsed content and resource provenance, independent of any viewport or app.
public struct MarkdownDocument: Sendable {
    let parsed: ParsedDocument

    public init(markdown: String, baseURL: URL? = nil) {
        parsed = DocumentParser.parse(markdown, baseURL: baseURL)
    }

    public init(plainText: String, options: PlainTextOptions = .init(), baseURL: URL? = nil) {
        parsed = DocumentParser.parse(plainText, plainText: true, baseURL: baseURL, plainTextOptions: options)
    }

    public init(data: Data, fileExtension: String, encoding: DocumentTextEncoding = .automatic, baseURL: URL? = nil)
        throws
    {
        let source = try DocumentDecoder.decode(data, encoding: encoding).text
        let ext = fileExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if ext == "txt" || ext == "text" {
            self.init(plainText: source, baseURL: baseURL)
        } else {
            self.init(markdown: source, baseURL: baseURL)
        }
    }

    public var outline: [OutlineItem] {
        var counts: [String: Int] = [:]
        return parsed.headings.map { heading in
            let slug = DocumentTypesetter.anchorSlug(heading.text)
            let duplicate = counts[slug, default: 0]
            counts[slug] = duplicate + 1
            return OutlineItem(
                level: heading.level, title: heading.text,
                id: slug + (duplicate == 0 ? "" : "-\(duplicate)"))
        }
    }
}

public struct OutlineItem: Identifiable, Hashable, Sendable {
    public let level: Int
    public let title: String
    /// Matches in-document fragment links, with deterministic duplicate suffixes.
    public let id: String
}
