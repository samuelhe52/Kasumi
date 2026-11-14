import AppKit
import CoreText

extension NSAttributedString.Key {
    static let kasumiDiagram = NSAttributedString.Key("KasumiDiagramAttachment")
}

final class MermaidAttachment: NSObject {
    let source: String
    let scene: MermaidScene
    let fontSize: CGFloat
    let fontFamily: String
    let dark: Bool
    let scale: CGFloat
    let size: CGSize

    init(source: String, scene: MermaidScene, fontSize: CGFloat, fontFamily: String, dark: Bool, maximumWidth: CGFloat, renderScale: CGFloat = 1) {
        self.source = source; self.scene = scene
        self.fontSize = fontSize; self.fontFamily = fontFamily; self.dark = dark
        // Include stroke ink so fitting/cropping cannot remove a border.
        let bounds = scene.bounds.insetBy(dx: -1, dy: -1)
        scale = min(renderScale, maximumWidth / max(1, bounds.width))
        size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }
    func attributed() -> NSAttributedString {
        let pointer = Unmanaged.passRetained(self).toOpaque()
        var callbacks = CTRunDelegateCallbacks(version: kCTRunDelegateVersion1, dealloc: {
            Unmanaged<MermaidAttachment>.fromOpaque($0).release()
        }, getAscent: { Unmanaged<MermaidAttachment>.fromOpaque($0).takeUnretainedValue().size.height },
           getDescent: { _ in 0 },
           getWidth: { Unmanaged<MermaidAttachment>.fromOpaque($0).takeUnretainedValue().size.width })
        guard let delegate = CTRunDelegateCreate(&callbacks, pointer) else {
            Unmanaged<MermaidAttachment>.fromOpaque(pointer).release()
            return NSAttributedString(string: source)
        }
        return NSAttributedString(string: "\u{FFFC}", attributes: [
            NSAttributedString.Key(kCTRunDelegateAttributeName as String): delegate,
            .kasumiDiagram: self, .kasumiSemanticText: source, .foregroundColor: NSColor.clear
        ])
    }
    /// Called in the upward-positive baseline coordinates used by CTLine.
    func draw(in context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: 1 - scene.bounds.minX, y: 1 - scene.bounds.minY)
        scene.draw(in: context, size: fontSize, fontFamily: fontFamily, dark: dark)
        context.restoreGState()
    }
}
