import Foundation
import CoreGraphics
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

