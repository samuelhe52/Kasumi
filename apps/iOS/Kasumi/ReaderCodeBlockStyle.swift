import CoreGraphics
import KasumiMarkdown

/// Product styling and native-control geometry belong to the reader. The
/// renderer only receives generic padding and optional caption-row dimensions.
enum ReaderCodeBlockStyle {
    static let reading = CodeBlockStyle(
        cornerRadius: 10, padding: .init(top: 0, left: 14, bottom: 12, right: 14),
        caption: .init(height: 44, insets: .init(top: 0, left: 0, bottom: 0, right: 88)))

    static let exporting = CodeBlockStyle(
        cornerRadius: 10, padding: .init(top: 0, left: 14, bottom: 12, right: 14), caption: .init())

    static func copyButtonFrame(in block: RenderedCodeBlock) -> CGRect? {
        guard let row = block.captionFrame, row.height >= 44, row.width >= 44 else { return nil }
        let width: CGFloat = row.width >= 180 ? 88 : 44
        let trailing = min(6, max(0, (row.width - width) / 2))
        return CGRect(x: row.maxX - trailing - width, y: row.midY - 22, width: width, height: 44)
    }
}
