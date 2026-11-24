import Foundation

/// Bold or italic, for editors that toggle Markdown emphasis markers.
public enum MarkdownEmphasis: Sendable {
    case bold
    case italic

    /// What taking one pair of markers out of a Markdown source does.
    public enum Removal: Sendable {
        /// Only this emphasis is removed. The text and other formatting stay.
        case emphasis
        /// The markers were literal asterisks outside code and math.
        case literalAsterisks
        /// Nothing rendered changes.
        case invisible
    }

    /// Compares the parsed documents. Returns nil when the edit has any other effect.
    public func removal(from source: String, to edited: String) -> Removal? {
        let before = Self.units(in: source)
        let after = Self.units(in: edited)
        if before.count == after.count {
            var removed = false
            for (old, new) in zip(before, after) {
                guard old.scalar == new.scalar, old.context == new.context else { return nil }
                let lost = self == .bold ? old.bold && !new.bold : old.italic && !new.italic
                let keepsRest = self == .bold ? old.italic == new.italic : old.bold == new.bold
                guard keepsRest, lost || old.bold == new.bold && old.italic == new.italic else { return nil }
                removed = removed || lost
            }
            return removed ? .emphasis : .invisible
        }
        guard before.count - after.count == (self == .bold ? 4 : 2) else { return nil }
        var index = 0
        for old in before {
            if index < after.count, old == after[index] {
                index += 1
            } else if old.scalar != "*" || old.context.isLiteral {
                return nil
            }
        }
        return index == after.count ? .literalAsterisks : nil
    }

    private struct Context: Equatable {
        let kind: DocumentBlock.Kind
        let level: Int
        let prefix: String
        let language: String?
        var traits: Set<InlineRun.Trait> = []
        var destination: String?
        var imageSource: String?
        var isLiteral: Bool {
            [.code, .math, .diagram].contains(kind) || !traits.isDisjoint(with: [.code, .math])
        }
    }

    private struct Unit: Equatable {
        let scalar: Unicode.Scalar
        var bold = false
        var italic = false
        let context: Context
    }

    private static func units(in source: String) -> [Unit] {
        var units: [Unit] = []
        for block in DocumentParser.parse(source).blocks where block.kind != .rule {
            let blockContext = Context(
                kind: block.kind, level: block.level, prefix: block.prefix, language: block.language)
            // A boundary per block and cell, so structural changes never match.
            for runs in [block.runs] + block.rows.joined() {
                units.append(Unit(scalar: "\0", context: blockContext))
                for run in runs {
                    var context = blockContext
                    context.traits = run.traits.subtracting([.strong, .emphasis])
                    context.destination = run.destination
                    context.imageSource = run.imageSource
                    for scalar in run.text.unicodeScalars {
                        units.append(
                            Unit(
                                scalar: scalar, bold: run.traits.contains(.strong),
                                italic: run.traits.contains(.emphasis), context: context))
                    }
                }
            }
        }
        return units
    }
}
