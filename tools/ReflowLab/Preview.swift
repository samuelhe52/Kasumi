#if os(macOS)
    import AppKit
    import KasumiMarkdown

    @MainActor final class LabCanvas: NSView {
        var rendered: RenderedDocument?
        var preview: LabPreview?
        override var isFlipped: Bool { true }
        override var isOpaque: Bool { true }

        func invalidateImage(in rect: CGRect) {
            if preview?.rect.intersects(rect) == true { preview = nil }
            setNeedsDisplay(rect.insetBy(dx: -1, dy: -1))
        }

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
