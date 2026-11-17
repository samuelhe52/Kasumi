#if os(macOS)
import AppKit
import KasumiMarkdown

/// Immutable CGImage crosses the detached prepaint boundary, never a context.
struct LabPreview: @unchecked Sendable {
    let image: CGImage
    let rect: CGRect

    nonisolated static func paint(_ document: RenderedDocument, rect: CGRect, scale: CGFloat) -> LabPreview? {
        guard !rect.isEmpty, rect.width.isFinite, rect.height.isFinite else { return nil }
        return autoreleasepool {
            guard let context = CGContext(
                data: nil, width: Int(ceil(rect.width * scale)), height: Int(ceil(rect.height * scale)),
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            context.translateBy(x: 0, y: CGFloat(context.height))
            context.scaleBy(x: scale, y: -scale)
            context.translateBy(x: -rect.minX, y: -rect.minY)
            document.draw(in: context, rect: rect)
            guard let image = context.makeImage() else { return nil }
            return LabPreview(image: image, rect: rect)
        }
    }
}

@MainActor final class LabCanvas: NSView {
    var rendered: RenderedDocument?
    var preview: LabPreview?
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(rendered?.backgroundColor ?? NSColor.white.cgColor)
        context.fill(dirtyRect)
        guard let rendered else { return }
        if let preview, preview.rect.intersects(dirtyRect) {
            context.saveGState()
            context.translateBy(x: preview.rect.minX, y: preview.rect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(preview.image, in: CGRect(origin: .zero, size: preview.rect.size))
            context.restoreGState()
            if preview.rect.contains(dirtyRect) { return }
            // Paint newly exposed content outside the immutable seed image.
            context.saveGState()
            context.addRect(dirtyRect)
            context.addRect(preview.rect.intersection(dirtyRect))
            context.clip(using: .evenOdd)
            rendered.draw(in: context, rect: dirtyRect)
            context.restoreGState()
        } else {
            rendered.draw(in: context, rect: dirtyRect)
        }
    }
}
#endif
