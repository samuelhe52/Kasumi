import CoreGraphics
import Foundation
import SwiftDraw

enum SVGImageDecoder {
    private static let intrinsicScale: CGFloat = 3

    struct Pixels: Hashable, Sendable {
        let width: Int
        let height: Int

        init?(size: CGSize, scale: CGFloat) {
            let width = ceil(size.width * scale)
            let height = ceil(size.height * scale)
            guard width.isFinite, height.isFinite, width > 0, height > 0,
                width <= 8192, height <= 8192, width * height <= 40_000_000
            else { return nil }
            self.width = Int(width)
            self.height = Int(height)
        }
    }

    // Avoid building SwiftDraw's command tree in layout for common SVGs
    // whose intrinsic size is stated directly on the root element.
    static func sourceSize(_ data: Data) -> CGSize? {
        guard looksLikeSVG(data) else { return nil }
        let root = SVGRoot()
        let parser = XMLParser(data: data)
        parser.delegate = root
        _ = parser.parse()
        if let size = root.size {
            return Pixels(size: size, scale: intrinsicScale) == nil ? nil : size
        }
        return source(data)?.size
    }

    private final class SVGRoot: NSObject, XMLParserDelegate {
        var size: CGSize?

        func parser(
            _ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
            attributes: [String: String]
        ) {
            defer { parser.abortParsing() }
            guard name == "svg" else { return }
            func dimension(_ key: String) -> Float? {
                guard let value = attributes[key]?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
                let number = value.hasSuffix("px") ? String(value.dropLast(2)).trimmingCharacters(in: .whitespaces) : value
                return Float(number)
            }
            let width = dimension("width")
            let height = dimension("height")
            if let width, let height {
                size = CGSize(width: CGFloat(width), height: CGFloat(height))
                return
            }
            // Match SwiftDraw's root aspect-ratio rule for a missing dimension.
            // Other unit syntax can depend on the root style, so defer it to SwiftDraw.
            guard width != nil || attributes["width"] == nil,
                height != nil || attributes["height"] == nil,
                let viewBox = attributes["viewBox"]?.split(whereSeparator: { $0.isWhitespace || $0 == "," }),
                viewBox.count == 4,
                let boxWidth = Float(viewBox[2]), let boxHeight = Float(viewBox[3]),
                boxWidth.isFinite, boxHeight.isFinite, boxWidth > 0, boxHeight > 0
            else { return }
            let resolvedWidth = width ?? height.map { $0 * boxWidth / boxHeight } ?? boxWidth
            let resolvedHeight = height ?? width.map { $0 * boxHeight / boxWidth } ?? boxHeight
            size = CGSize(width: CGFloat(resolvedWidth), height: CGFloat(resolvedHeight))
        }
    }

    static func source(_ data: Data) -> SVG? {
        guard looksLikeSVG(data), let svg = SVG(data: data),
            Pixels(size: svg.size, scale: intrinsicScale) != nil
        else { return nil }
        return svg
    }

    static func decode(_ data: Data) -> DocumentImage? {
        source(data).flatMap { rasterize($0) }
    }

    static func rasterize(_ svg: SVG, readerPixels: Pixels? = nil) -> DocumentImage? {
        let size = svg.size
        guard let pixels = readerPixels ?? Pixels(size: size, scale: intrinsicScale),
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: pixels.width, height: pixels.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        if let readerPixels {
            context.scaleBy(x: CGFloat(readerPixels.width) / size.width, y: CGFloat(readerPixels.height) / size.height)
        } else {
            context.scaleBy(x: intrinsicScale, y: intrinsicScale)
        }
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(svg)
        return context.makeImage().map { DocumentImage(bitmap: $0, size: size, isSVG: true) }
    }

    private static func looksLikeSVG(_ data: Data) -> Bool {
        let bytes = data.dropFirst(data.starts(with: [0xef, 0xbb, 0xbf]) ? 3 : 0)
            .drop(while: { $0 == 32 || $0 == 9 || $0 == 10 || $0 == 13 })
        guard bytes.first == 60 else { return false }
        if bytes.starts(with: "<svg".utf8) {
            guard let next = bytes.dropFirst(4).first else { return false }
            return next == 32 || next == 9 || next == 10 || next == 13 || next == 62 || next == 47
        }
        if bytes.starts(with: "<?xml".utf8) || bytes.starts(with: "<!DOCTYPE svg".utf8) { return true }
        return bytes.starts(with: "<!--".utf8) && bytes.range(of: Data("<svg".utf8)) != nil
    }
}
