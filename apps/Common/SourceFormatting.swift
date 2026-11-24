import Foundation
import KasumiMarkdown

/// One replacement in Markdown source plus the selection afterward. Ranges are
/// UTF-16 offsets, as UITextView uses them; `range` is in the original text and
/// `selection` in the edited text.
struct SourceEdit: Equatable {
    var range: NSRange
    var text: String
    var selection: NSRange
}

/// Markdown commands for the editor's keyboard bar. They act on the current
/// line or selection, so a single tap replaces several keyboard-page switches.
enum SourceFormatting {
    /// Cycles the current line's heading `# ` → `## ` → … → `###### ` → none,
    /// or sets `level` directly (0 removes the heading).
    static func heading(in text: String, selection: NSRange, level: Int? = nil) -> SourceEdit {
        let source = text as NSString
        let line = source.lineRange(for: NSRange(location: selection.location, length: 0))
        // Keep the indentation, which can place the heading in a list item. Any
        // spaces or tabs can follow the marker.
        func end(of units: Set<unichar>, from start: Int, limit: Int = .max) -> Int {
            var next = start
            while next < NSMaxRange(line), next - start < limit, units.contains(source.character(at: next)) {
                next += 1
            }
            return next
        }
        var indent = end(of: [0x09, 0x20], from: line.location)
        let prefix = source.substring(with: NSRange(location: line.location, length: indent - line.location))
        // Deeper indentation is a heading only inside a list; elsewhere it is code.
        if prefix.contains("\t") || prefix.utf16.count >= 4 {
            let marked =
                source.character(at: min(indent, source.length - 1)) == 0x23
                ? text : source.replacingCharacters(in: NSRange(location: indent, length: 0), with: "# ")
            let number = lineNumber(in: source, at: line.location)
            if !MarkdownDocument(markdown: marked).outline.contains(where: { $0.sourceLine == number }) {
                indent = line.location
            }
        }
        let next = end(of: [0x23], from: indent, limit: 6)
        let hashes = next - indent
        let endsMarker = next >= NSMaxRange(line) || [0x09, 0x20, 0x0A, 0x0D].contains(source.character(at: next))
        let current = hashes > 0 && endsMarker ? hashes : 0
        let oldEnd = current > 0 ? end(of: [0x09, 0x20], from: next) : indent
        let old = NSRange(location: indent, length: oldEnd - indent)
        let target = level ?? (current == 6 ? 0 : current + 1)
        let marker = target == 0 ? "" : String(repeating: "#", count: target) + " "
        let delta = marker.utf16.count - old.length
        let start = max(selection.location + delta, indent + marker.utf16.count)
        return SourceEdit(range: old, text: marker, selection: NSRange(location: start, length: selection.length))
    }

    private static func lineNumber(in source: NSString, at location: Int) -> Int {
        var number = 1
        for index in 0..<location {
            let unit = source.character(at: index)
            if unit == 0x0A || (unit == 0x0D && (index + 1 == source.length || source.character(at: index + 1) != 0x0A))
            {
                number += 1
            }
        }
        return number
    }

    static func bold(in text: String, selection: NSRange) -> SourceEdit {
        emphasis(in: text, selection: selection, width: 2)
    }

    static func italic(in text: String, selection: NSRange) -> SourceEdit {
        emphasis(in: text, selection: selection, width: 1)
    }

    private static func emphasis(in text: String, selection: NSRange, width: Int) -> SourceEdit {
        let source = text as NSString
        // A delimiter next to whitespace on its inner side does not open or close.
        let whole = selection
        var selection = selection
        while selection.length > 0, isWhitespace(source.character(at: selection.location)) {
            selection.location += 1
            selection.length -= 1
        }
        while selection.length > 0, isWhitespace(source.character(at: NSMaxRange(selection) - 1)) {
            selection.length -= 1
        }
        let selected = source.substring(with: selection)
        if selection.length == 0, whole.length > 0 {
            return SourceEdit(range: whole, text: source.substring(with: whole), selection: whole)
        }
        for symbol: unichar in [0x2A, 0x5F] {
            func run(before location: Int) -> Int {
                var start = location
                while start > 0, source.character(at: start - 1) == symbol { start -= 1 }
                return location - start
            }
            func run(after location: Int) -> Int {
                var end = location
                while end < source.length, source.character(at: end) == symbol { end += 1 }
                return end - location
            }
            func hasMarker(_ count: Int) -> Bool { width == 2 ? count >= 2 : count % 2 == 1 }

            func removing(_ edit: SourceEdit, betweenMarkers inner: NSRange) -> SourceEdit? {
                switch (width == 2 ? MarkdownEmphasis.bold : .italic).removal(from: text, to: edit.applied(to: text)) {
                case .emphasis: edit
                // Also undo a pair just inserted where Markdown reads it
                // literally: an empty pair, or beside punctuation.
                case .literalAsterisks:
                    symbol == 0x2A && !source.substring(with: inner).contains("*") ? edit : nil
                case .invisible: inner.length == 0 ? edit : nil
                case nil: nil
                }
            }
            if hasMarker(run(before: selection.location)), hasMarker(run(after: NSMaxRange(selection))) {
                let start = selection.location - width
                let edit = SourceEdit(
                    range: NSRange(location: start, length: selection.length + 2 * width), text: selected,
                    selection: NSRange(location: start, length: selection.length))
                if let edit = removing(edit, betweenMarkers: selection) { return edit }
            }
            if selection.length > 2 * width,
                hasMarker(run(after: selection.location)), hasMarker(run(before: NSMaxRange(selection)))
            {
                let inner = NSRange(location: selection.location + width, length: selection.length - 2 * width)
                let edit = SourceEdit(
                    range: selection, text: source.substring(with: inner),
                    selection: NSRange(location: selection.location, length: inner.length))
                if let edit = removing(edit, betweenMarkers: inner) { return edit }
            }
        }
        let marker = String(repeating: "*", count: width)
        return SourceEdit(
            range: selection, text: marker + selected + marker,
            selection: NSRange(location: selection.location + width, length: selection.length))
    }

    private static func isWhitespace(_ unit: unichar) -> Bool {
        Unicode.Scalar(unit).map(CharacterSet.whitespacesAndNewlines.contains) ?? false
    }

    /// Wraps the selection in backticks, or a fenced block when it spans lines.
    /// Unwraps a selection already enclosed in single backticks. With nothing
    /// selected, inserts a pair with the caret between them.
    static func code(in text: String, selection: NSRange) -> SourceEdit {
        let source = text as NSString
        let selected = source.substring(with: selection)
        let before = selection.location - 1
        let after = NSMaxRange(selection)
        if selection.length > 0, before >= 0, after < source.length,
            source.character(at: before) == 0x60, source.character(at: after) == 0x60
        {
            return SourceEdit(
                range: NSRange(location: before, length: selection.length + 2), text: selected,
                selection: NSRange(location: before, length: selection.length))
        }
        // Swift sees CRLF as one character, distinct from "\n".
        if let lineBreak = selected.first(where: \.isNewline).map(String.init) {
            let opening = "```" + lineBreak
            return SourceEdit(
                range: selection, text: opening + selected + lineBreak + "```",
                selection: NSRange(location: selection.location + opening.utf16.count, length: selection.length))
        }
        return SourceEdit(
            range: selection, text: "`" + selected + "`",
            selection: NSRange(location: selection.location + 1, length: selection.length))
    }

    /// Toggles `> ` on every line the selection touches. Removes the markers
    /// only when every non-empty line already has one.
    static func quote(in text: String, selection: NSRange) -> SourceEdit {
        let source = text as NSString
        // A selection ending just after a newline does not include the next line.
        let endsAtBreak = selection.length > 0 && [0x0A, 0x0D].contains(source.character(at: NSMaxRange(selection) - 1))
        let lines = source.lineRange(
            for: NSRange(location: selection.location, length: selection.length - (endsAtBreak ? 1 : 0)))
        let block = source.substring(with: lines)
        let trailing = block.last?.isNewline == true ? String(block.suffix(1)) : ""
        let body = block.dropLast(trailing.count)
        let separators = body.filter(\.isNewline).map(String.init)
        var parts = body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        let quoted =
            parts.allSatisfy { $0.isEmpty || $0.hasPrefix(">") }
            && parts.contains { !$0.isEmpty }
        var shifts: [Int] = []
        parts = parts.map { line in
            if quoted {
                let removed = line.hasPrefix("> ") ? 2 : line.hasPrefix(">") ? 1 : 0
                shifts.append(-removed)
                return String(line.dropFirst(removed))
            }
            let marker = line.isEmpty ? ">" : "> "
            shifts.append(marker.utf16.count)
            return marker + line
        }
        let replaced = zip(parts, separators + [trailing]).map { $0 + $1 }.joined()
        let result: NSRange
        if selection.length == 0 {
            let caret = selection.location + shifts[0]
            result = NSRange(location: max(lines.location, caret), length: 0)
        } else {
            let length = replaced.utf16.count - trailing.utf16.count
            result = NSRange(location: lines.location, length: length)
        }
        return SourceEdit(range: lines, text: replaced, selection: result)
    }

    /// Makes `[selection](|)`, or `[|](url)` when the selection is a URL, or
    /// `[|]()` with nothing selected; the caret lands in the empty part.
    static func link(in text: String, selection: NSRange) -> SourceEdit {
        let selected = (text as NSString).substring(with: selection)
        let start = selection.location
        if selected.isEmpty {
            return SourceEdit(range: selection, text: "[]()", selection: NSRange(location: start + 1, length: 0))
        }
        if selected.contains("://"), !selected.contains(where: \.isWhitespace) {
            return SourceEdit(
                range: selection, text: "[](" + selected + ")", selection: NSRange(location: start + 1, length: 0))
        }
        let caret = start + 1 + selected.utf16.count + 2
        return SourceEdit(
            range: selection, text: "[" + selected + "]()", selection: NSRange(location: caret, length: 0))
    }
}

extension SourceEdit {
    /// The source text after this edit.
    func applied(to text: String) -> String {
        (text as NSString).replacingCharacters(in: range, with: self.text)
    }
}
