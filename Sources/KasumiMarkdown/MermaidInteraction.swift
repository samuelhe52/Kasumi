import CoreGraphics
import CoreText
import Foundation

struct MermaidNodeLink {
    let path: CGPath
    let target: String
    let labelCommands: Range<Int>

    static func parse(_ source: Substring, requiresHref: Bool = false) -> (String, String)? {
        let fields = source.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard fields.count == 2 else { return nil }
        var action = fields[1]
        if action.hasPrefix("href"), action.dropFirst(4).first?.isWhitespace == true {
            action = action.dropFirst(4).drop(while: \.isWhitespace)
        } else if requiresHref {
            return nil
        }
        guard action.first == "\"", let end = action.dropFirst().firstIndex(of: "\"") else { return nil }
        let target = String(action[action.index(after: action.startIndex)..<end])
        return (String(fields[0]), target)
    }

    static func isSafeTarget(_ target: String) -> Bool {
        guard !target.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
            let url = DocumentLink.url(target, relativeTo: nil),
            !["javascript", "vbscript", "data"].contains(url.scheme?.lowercased() ?? "")
        else { return false }
        return true
    }
}

struct MermaidLabel {
    let text: String
    let frame: CGRect
    let role: Int
    var range: NSRange = NSRange()
}

extension MermaidScene {
    var selectableLabels: [MermaidLabel] {
        commands.compactMap { command -> MermaidLabel? in
            switch command {
            case .text(let text, let rect, let role), .coloredText(let text, let rect, let role, _):
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return MermaidLabel(text: text, frame: rect, role: role)
            default:
                return nil
            }
        }.sorted {
            if $0.frame.midY != $1.frame.midY { return $0.frame.midY < $1.frame.midY }
            return $0.frame.minX < $1.frame.minX
        }
    }
}

/// Geometry belongs to one layout. Core Text label lines are built on first
/// interaction and subsequently read under the owning snapshot's layout lock.
final class PlacedDiagram {
    let attachment: MermaidAttachment
    let renderedOffset: Int
    private let sceneToDocument: CGAffineTransform
    private var positionedLabels: [Int: MermaidTextStyle.PositionedLine] = [:]

    init(attachment: MermaidAttachment, topLeft: CGPoint, renderedOffset: Int) {
        self.attachment = attachment
        self.renderedOffset = renderedOffset
        sceneToDocument = CGAffineTransform(translationX: topLeft.x, y: topLeft.y)
            .scaledBy(x: attachment.scale, y: attachment.scale)
            .translatedBy(x: 1 - attachment.scene.bounds.minX, y: 1 - attachment.scene.bounds.minY)
    }

    func link(at point: CGPoint) -> String? {
        let point = point.applying(sceneToDocument.inverted())
        return attachment.scene.links.reversed().first { $0.path.contains(point) }?.target
    }

    var linkRects: [(target: String, rect: CGRect)] {
        attachment.scene.links.map { ($0.target, $0.path.boundingBoxOfPath.applying(sceneToDocument)) }
    }

    func textOffset(at point: CGPoint) -> Int? {
        let point = point.applying(sceneToDocument.inverted())
        func distance(_ rect: CGRect) -> CGFloat {
            let dx = max(0, rect.minX - point.x, point.x - rect.maxX)
            let dy = max(0, rect.minY - point.y, point.y - rect.maxY)
            return dx * dx + dy * dy
        }
        guard
            let index = attachment.labels.indices.min(by: {
                distance(attachment.labels[$0].frame) < distance(attachment.labels[$1].frame)
            })
        else { return nil }
        let label = attachment.labels[index]
        let positioned = positionedLabel(index)
        let x = min(positioned.bounds.width, max(0, point.x - positioned.bounds.minX))
        let offset = CTLineGetStringIndexForPosition(positioned.line, CGPoint(x: x, y: 0))
        return label.range.location + min(label.range.length, max(0, offset))
    }

    func caretRect(at offset: Int) -> CGRect? {
        guard
            let index = attachment.labels.firstIndex(where: {
                $0.range.location <= offset && offset <= NSMaxRange($0.range)
            })
        else { return nil }
        let label = attachment.labels[index]
        let positioned = positionedLabel(index)
        let x = CTLineGetOffsetForStringIndex(positioned.line, offset - label.range.location, nil)
        let bounds = positioned.bounds
        let rect = CGRect(x: bounds.minX + x, y: bounds.minY, width: 0, height: bounds.height)
            .applying(sceneToDocument)
        return CGRect(x: rect.minX, y: rect.minY, width: 1, height: rect.height)
    }

    func selectionRects(for range: NSRange) -> [CGRect] {
        attachment.labels.indices.flatMap { index -> [CGRect] in
            let label = attachment.labels[index]
            let overlap = NSIntersectionRange(label.range, range)
            guard overlap.length > 0 else { return [] }
            let positioned = positionedLabel(index)
            let local = NSRange(location: overlap.location - label.range.location, length: overlap.length)
            return CoreTextRangeGeometry.extents(in: positioned.line, for: local).map {
                CGRect(
                    x: positioned.bounds.minX + $0.lowerBound, y: positioned.bounds.minY,
                    width: $0.upperBound - $0.lowerBound, height: positioned.bounds.height
                )
                .applying(sceneToDocument)
            }
        }
    }

    private func positionedLabel(_ index: Int) -> MermaidTextStyle.PositionedLine {
        if let positioned = positionedLabels[index] { return positioned }
        let label = attachment.labels[index]
        let positioned = attachment.textStyle.positionedLine(
            label.text, in: label.frame, role: label.role, color: CGColor(gray: 0, alpha: 1))
        positionedLabels[index] = positioned
        return positioned
    }
}
