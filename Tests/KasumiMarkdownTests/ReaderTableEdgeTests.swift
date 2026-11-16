import CoreGraphics
import QuartzCore
import Testing

// ReaderTableEdgeMask.swift links to the actual app source. Render nested
// layers with moving bounds so a mask that scrolls away cannot pass this test.
@MainActor @Suite struct ReaderTableEdgeTests {
    @Test func fadesTrackTheViewportAndDisappearAtContentEnds() throws {
        for (offset, leftFades, rightFades) in [
            (CGFloat(0), false, true), (120, true, true), (680, true, false),
            (-12, false, true), (692, true, false)
        ] {
            let pixels = try drawEdges(offset: offset)
            #expect(leftFades ? pixels[0] > 230 : pixels[0] < 20)
            #expect(rightFades ? pixels[319] > 230 : pixels[319] < 20)
            #expect(pixels[18] < 20 && pixels[301] < 20)
        }
        let nearStart = try drawEdges(offset: 9)
        #expect((110...140).contains(nearStart[0]))
        let nearEnd = try drawEdges(offset: 671)
        #expect((110...140).contains(nearEnd[319]))
        let fitted = try drawEdges(offset: 0, contentWidth: 320)
        #expect(fitted.allSatisfy { $0 < 20 })
    }

    private func drawEdges(offset: CGFloat, contentWidth: CGFloat = 1000) throws -> [UInt8] {
        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: 320, height: 40)
        root.backgroundColor = CGColor(gray: 1, alpha: 1)
        let scroll = CALayer()
        scroll.frame = root.bounds
        scroll.bounds.origin.x = offset
        let content = CALayer()
        // Cover bounce regions too: this test isolates mask opacity from the
        // blank space naturally exposed by an actual scroll view's bounce.
        content.frame = CGRect(x: -100, y: 0, width: contentWidth + 200, height: 40)
        content.backgroundColor = CGColor(gray: 0, alpha: 1)
        scroll.addSublayer(content)
        let mask = ReaderTableEdgeMask()
        mask.update(viewport: scroll.bounds, contentWidth: contentWidth)
        #expect(mask.frame == scroll.bounds)
        scroll.mask = mask
        root.addSublayer(scroll)
        var rgba = [UInt8](repeating: 0, count: 320 * 40 * 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try #require(
                CGContext(
                    data: bytes.baseAddress, width: 320, height: 40, bitsPerComponent: 8, bytesPerRow: 320 * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            root.render(in: context)
        }
        return (0..<320).map { rgba[(20 * 320 + $0) * 4] }
    }
}
