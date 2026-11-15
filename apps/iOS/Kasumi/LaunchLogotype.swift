import SwiftUI

/// The launch header: a light serif wordmark resting on slow drifts of mist.
/// The scene's own title is a blank placeholder that
/// keeps the system layout; this view draws the name in its place.
///
/// `DocumentLaunchGeometryProxy.titleViewFrame` spans the whole region above
/// the browser sheet rather than the title text, so the wordmark sits at a
/// fixed offset from its top, just above the first action button.
struct LaunchLogotype: View {
    let titleFrame: CGRect

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private static let wordmarkHeight: CGFloat = 80
    /// Gap between the top of `titleViewFrame` and the wordmark's bottom edge.
    private static let wordmarkBottom: CGFloat = 100
    private static let leadingInset: CGFloat = 22

    private var paused: Bool { reduceMotion || lowPower }

    var body: some View {
        GeometryReader { proxy in
            let focusY = titleFrame.minY + Self.wordmarkBottom - Self.wordmarkHeight / 2
            TimelineView(.animation(minimumInterval: 1 / 30, paused: paused)) { context in
                // A fixed moment with a light veil when motion is off.
                let t = paused ? 14 : context.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .topLeading) {
                    // The mist runs under the status bar and sheet; extending
                    // past the top inset moves its origin up by that much.
                    MistField(time: t, focusY: focusY + proxy.safeAreaInsets.top, color: mistColor)
                        .opacity(colorScheme == .dark ? 0.22 : 0.55)
                        .ignoresSafeArea()
                    wordmark
                        .offset(
                            x: Self.leadingInset,
                            y: titleFrame.minY + Self.wordmarkBottom - Self.wordmarkHeight)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private var wordmark: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: "Kasumi")
                .font(.system(size: 58, weight: .light, design: .serif))
                .tracking(4)
            // New York has no CJK glyphs and would fall back to PingFang (sans).
            Text(verbatim: "霞")
                .font(.custom("HiraMinProN-W3", fixedSize: 22))
                .opacity(0.65)
        }
        .foregroundStyle(inkColor)
        .frame(height: Self.wordmarkHeight)
        .fixedSize()
    }

    private var inkColor: Color {
        colorScheme == .dark
            ? Color(red: 0.96, green: 0.94, blue: 0.98)
            : Color(red: 0.24, green: 0.22, blue: 0.36)
    }

    private var mistColor: Color {
        colorScheme == .dark ? Color(red: 0.92, green: 0.88, blue: 0.98) : .white
    }
}

/// Soft cloud banks drifting sideways around `focusY`.
///
/// Banks differ in speed, direction, height, size, softness and density, and
/// each is a cluster of puffs whose arrangement slowly shifts and breathes, so
/// no two passes look alike. Each bank's loop is longer than the screen is
/// wide, leaving stretches of clear air between passes. The layout is seeded,
/// so it is the same on every launch.
private struct MistField: View {
    let time: TimeInterval
    let focusY: CGFloat
    let color: Color

    private struct Puff {
        /// Offsets and sizes as fractions of the bank's width and height.
        let dx: Double, dy: Double, width: Double, height: Double, drift: Double
    }

    private struct Bank {
        let period: Double, phase: Double, direction: Double, slack: Double
        /// Vertical offset from `focusY` and nominal height, in points.
        let dy: Double, height: Double
        /// Width as a fraction of the view's width.
        let width: Double
        let opacity: Double, blur: Double
        let bob: Double, bobPeriod: Double, breathePeriod: Double
        let puffs: [Puff]
    }

    private static let banks: [Bank] = {
        var rng = SeededRandom(seed: 0x6B61_7375_6D69)
        return (0..<7).map { index in
            let puffCount = Int(rng.next(in: 3...6))
            return Bank(
                period: rng.next(in: 34...95),
                phase: rng.next(in: 0...1),
                // Mostly drifting one way, with the odd counter-current.
                direction: index == 2 || index == 5 ? -1 : 1,
                slack: rng.next(in: 1.3...2.2),
                dy: rng.next(in: -80...70),
                height: rng.next(in: 28...95),
                width: rng.next(in: 0.35...1.1),
                opacity: rng.next(in: 0.45...1),
                blur: rng.next(in: 14...34),
                bob: rng.next(in: 3...14),
                bobPeriod: rng.next(in: 14...40),
                breathePeriod: rng.next(in: 18...50),
                puffs: (0..<puffCount).map { _ in
                    Puff(
                        dx: rng.next(in: -0.4...0.4), dy: rng.next(in: -0.35...0.35),
                        width: rng.next(in: 0.3...0.75), height: rng.next(in: 0.5...1.1),
                        drift: rng.next(in: 0...(2 * .pi)))
                })
        }
    }()

    var body: some View {
        Canvas { context, size in
            for bank in Self.banks {
                let w = bank.width * size.width
                let travel = (size.width + w) * bank.slack
                let progress = (time / bank.period + bank.phase).truncatingRemainder(dividingBy: 1)
                let leading = -w + progress * travel
                let centerX = (bank.direction > 0 ? leading : size.width - leading - w) + w / 2
                let centerY = focusY + bank.dy + bank.bob * sin(time * 2 * .pi / bank.bobPeriod)
                let breathe = 1 + 0.18 * sin(time * 2 * .pi / bank.breathePeriod)
                let h = bank.height * breathe

                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: bank.blur))
                    layer.opacity = bank.opacity
                    for puff in bank.puffs {
                        // Puffs wander within the bank so its outline keeps changing.
                        let wander = sin(time * 2 * .pi / bank.breathePeriod + puff.drift)
                        let pw = puff.width * w * (1 + 0.15 * wander)
                        let ph = puff.height * h
                        let px = centerX + (puff.dx + 0.06 * wander) * w
                        let py = centerY + (puff.dy + 0.08 * cos(time / bank.bobPeriod + puff.drift)) * h
                        let rect = CGRect(x: px - pw / 2, y: py - ph / 2, width: pw, height: ph)
                        layer.fill(Ellipse().path(in: rect), with: .color(color))
                    }
                }
            }
        }
    }
}

/// SplitMix64, so the mist layout is the same on every launch.
private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        let unit = Double(z >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
