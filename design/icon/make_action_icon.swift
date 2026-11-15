#!/usr/bin/env swift
import AppKit

// The app icon's four bars, centered without its opaque background or glow.
// Run: swift design/icon/make_action_icon.swift
let output = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("apps/iOS/ImportExtension")
let scales = [2, 3]
let barHeight: CGFloat = 62
let artWidth: CGFloat = 618
let artHeight: CGFloat = 380
let bars: [(top: CGFloat, width: CGFloat)] = [(0, 618), (106, 618), (212, 618), (318, 401)]

for imageScale in scales {
    let size = 60 * imageScale
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) * 0.75 / artWidth
    let x = (CGFloat(size) - artWidth * scale) / 2
    let y = (CGFloat(size) - artHeight * scale) / 2
    NSColor.black.setFill()
    for bar in bars {
        let rect = NSRect(
            x: x, y: y + (artHeight - bar.top - barHeight) * scale,
            width: bar.width * scale, height: barHeight * scale
        )
        NSBezierPath(roundedRect: rect, xRadius: barHeight * scale / 2,
                     yRadius: barHeight * scale / 2).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(
        to: output.appendingPathComponent("ActionIcon@\(imageScale)x.png")
    )
}
