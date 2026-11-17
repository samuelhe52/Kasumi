import CoreGraphics

/// Code-block rendering choices, independent of reader controls. Defaults retain
/// the themed background and ordinary padding, with square corners and no caption.
/// Negative or nonfinite dimensions resolve to zero; caption fonts are at least 1 pt.
public struct CodeBlockStyle: Equatable, Sendable {
    /// An optional language-caption row. Insets are relative to the code's
    /// horizontal content bounds and the row's vertical bounds. Clients may
    /// reserve space for their own decorations by increasing these insets.
    public struct Caption: Equatable, Sendable {
        public var height: CGFloat
        public var insets: DocumentInsets
        public var fontSize: CGFloat

        public init(height: CGFloat = 28, insets: DocumentInsets = .zero, fontSize: CGFloat = 12) {
            self.height = height
            self.insets = insets
            self.fontSize = fontSize
        }
    }

    public var drawsBackground: Bool
    /// Nil uses the document theme's code_block_background color.
    public var backgroundColor: DocumentColor?
    public var cornerRadius: CGFloat
    public var padding: DocumentInsets
    /// Nil draws no caption and reserves no caption row.
    public var caption: Caption?

    public init(
        drawsBackground: Bool = true, backgroundColor: DocumentColor? = nil,
        cornerRadius: CGFloat = 0,
        padding: DocumentInsets = .init(top: 10, left: 14, bottom: 10, right: 14),
        caption: Caption? = nil
    ) {
        self.drawsBackground = drawsBackground
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.caption = caption
    }

    var resolved: Self {
        func dimension(_ value: CGFloat) -> CGFloat { value.isFinite ? max(0, value) : 0 }
        func insets(_ value: DocumentInsets) -> DocumentInsets {
            .init(
                top: dimension(value.top), left: dimension(value.left),
                bottom: dimension(value.bottom), right: dimension(value.right))
        }
        var result = self
        result.cornerRadius = dimension(cornerRadius)
        result.padding = insets(padding)
        if let caption, dimension(caption.height) > 0 {
            result.caption = .init(
                height: dimension(caption.height), insets: insets(caption.insets),
                fontSize: max(1, dimension(caption.fontSize)))
        } else {
            result.caption = nil
        }
        return result
    }

    /// Keep a usable text measure when requested padding exceeds the block width.
    func padding(fitting width: CGFloat) -> DocumentInsets {
        var result = padding
        let available = max(0, width - 12)
        let total = result.left + result.right
        if total > available {
            let factor = available / total
            result.left *= factor
            result.right *= factor
        }
        return result
    }
}
