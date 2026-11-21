import QuartzCore

/// Fade only edges with hidden content. Alpha masking follows any paper color
/// and includes table rules, without covering the view or intercepting touches.
final class ReaderTableEdgeMask: CAGradientLayer {
    override init() {
        super.init()
        startPoint = CGPoint(x: 0, y: 0.5)
        endPoint = CGPoint(x: 1, y: 0.5)
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(viewport: CGRect, contentWidth: CGFloat) {
        guard viewport.width > 0 else { return }
        let fade = min(18, viewport.width / 4)
        let left = min(1, max(0, viewport.minX) / fade)
        let right = min(1, max(0, contentWidth - viewport.maxX) / fade)
        let opaque = CGColor(gray: 0, alpha: 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // UIScrollView moves bounds.origin with its content offset. Keep the
        // gradient fixed to the visible viewport, including during a bounce.
        frame = viewport
        locations = [0, NSNumber(value: fade / viewport.width), NSNumber(value: 1 - fade / viewport.width), 1]
        colors = [CGColor(gray: 0, alpha: 1 - left), opaque, opaque, CGColor(gray: 0, alpha: 1 - right)]
        CATransaction.commit()
    }
}
