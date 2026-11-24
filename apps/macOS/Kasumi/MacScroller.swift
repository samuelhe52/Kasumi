import AppKit

/// Keep AppKit's tracking, accessibility and overlay fade for a smaller knob.
final class MacScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        var knob = rect(for: .knob)
        guard !knob.isEmpty else { return }
        if bounds.width > bounds.height {
            knob = knob.insetBy(dx: 1, dy: max(0, (knob.height - 6) / 2))
        } else {
            knob = knob.insetBy(dx: max(0, (knob.width - 6) / 2), dy: 1)
        }
        let lightKnob =
            knobStyle == .light
            || (knobStyle == .default && effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        let ink = lightKnob ? NSColor.white : NSColor.black
        ink.withAlphaComponent(lightKnob ? 0.28 : 0.24).setFill()
        NSBezierPath(roundedRect: knob, xRadius: 3, yRadius: 3).fill()
    }
}
