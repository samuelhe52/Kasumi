import CoreGraphics
import KasumiMarkdown

/// Product styling and native-control geometry belong to the reader. The
/// renderer only receives generic padding and optional caption-row dimensions.
enum ReaderCodeBlockStyle {
    static let reading = CodeBlockStyle(
        cornerRadius: 10, padding: .init(top: 0, left: 12, bottom: 10, right: 12),
        caption: .init(height: 36, insets: .init(top: 0, left: 0, bottom: 0, right: 44)))

    static let exporting = CodeBlockStyle(
        cornerRadius: 10, padding: .init(top: 0, left: 14, bottom: 12, right: 14), caption: .init())

    static func copyButtonFrame(in block: RenderedCodeBlock) -> CGRect? {
        guard let row = block.captionFrame, row.height >= 36, row.width >= 44 else { return nil }
        return CGRect(x: row.maxX - 44, y: row.minY, width: 44, height: 36)
    }
}
