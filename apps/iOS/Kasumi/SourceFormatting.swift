import Foundation

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
        var hashes = 0
        while hashes < 6, hashes < line.length,
            source.character(at: line.location + hashes) == 0x23
        { hashes += 1 }
        let next = line.location + hashes
        let endsMarker = next >= NSMaxRange(line) || [0x20, 0x0A, 0x0D].contains(source.character(at: next))
        let current = hashes > 0 && endsMarker ? hashes : 0
        let spaced = current > 0 && next < NSMaxRange(line) && source.character(at: next) == 0x20
        let old = NSRange(location: line.location, length: current + (spaced ? 1 : 0))
        let target = level ?? (current == 6 ? 0 : current + 1)
        let marker = target == 0 ? "" : String(repeating: "#", count: target) + " "
        let delta = marker.utf16.count - old.length
        let start = max(selection.location + delta, line.location + marker.utf16.count)
        return SourceEdit(range: old, text: marker, selection: NSRange(location: start, length: selection.length))
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
        if selected.contains("\n") {
            let fenced = "```\n" + selected + "\n```"
            return SourceEdit(
                range: selection, text: fenced,
                selection: NSRange(location: selection.location + 4, length: selection.length))
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
        let endsAtBreak = selection.length > 0 && source.character(at: NSMaxRange(selection) - 1) == 0x0A
        let lines = source.lineRange(
            for: NSRange(location: selection.location, length: selection.length - (endsAtBreak ? 1 : 0)))
        let block = source.substring(with: lines)
        let trailingNewline = block.hasSuffix("\n")
        var parts = (trailingNewline ? String(block.dropLast()) : block)
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
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
        let replaced = parts.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        let result: NSRange
        if selection.length == 0 {
            let caret = selection.location + shifts[0]
            result = NSRange(location: max(lines.location, caret), length: 0)
        } else {
            let length = replaced.utf16.count - (trailingNewline ? 1 : 0)
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
