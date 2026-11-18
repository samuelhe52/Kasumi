/// The spacing settings that a reader can adjust together.
public struct TypographySpacing: Codable, Equatable, Sendable {
    public enum ParagraphStyle: String, Codable, Sendable {
        case spaced = "space"
        case indented = "indent"
    }

    public var lineSpacing: Double
    public var paragraphStyle: ParagraphStyle
    public var headingSpaceBefore: Double
    public var headingSpaceAfter: Double

    public static var lineSpacingRange: ClosedRange<Double> { range(for: .lineSpacing) }
    public static var headingSpaceBeforeRange: ClosedRange<Double> { range(for: .headingSpaceBefore) }
    public static var headingSpaceAfterRange: ClosedRange<Double> { range(for: .headingSpaceAfter) }

    private static func range(for field: ProfileField) -> ClosedRange<Double> {
        let bounds = field.specification.guiRange!
        return bounds[0]...bounds[1]
    }

    init(values: ProfileValues) {
        lineSpacing = values.resolved(.lineSpacing).number!
        paragraphStyle = ParagraphStyle(rawValue: values.resolved(.paraSeparation).string!)!
        headingSpaceBefore = values.resolved(.headingSpaceBefore).number!
        headingSpaceAfter = values.resolved(.headingSpaceAfter).number!
    }
}
