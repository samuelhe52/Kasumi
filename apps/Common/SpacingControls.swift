import KasumiMarkdown
import SwiftUI

struct SpacingControls: View {
    let preset: TypographyPreset
    @Binding var edits: TypographySpacing?

    var body: some View {
        Section("Spacing") {
            SpacingSlider(
                title: "Line spacing", suffix: "×", id: "preset-line-spacing",
                value: setting(\.lineSpacing), range: TypographySpacing.lineSpacingRange)
            #if os(macOS)
                paragraphStylePicker
            #else
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paragraph style")
                    paragraphStylePicker.labelsHidden()
                }
                .padding(.vertical, 4)
            #endif
        }
        Section("Heading spacing") {
            SpacingSlider(
                title: "Above", suffix: " em", id: "preset-heading-above",
                value: setting(\.headingSpaceBefore), range: TypographySpacing.headingSpaceBeforeRange)
            SpacingSlider(
                title: "Below", suffix: " em", id: "preset-heading-below",
                value: setting(\.headingSpaceAfter), range: TypographySpacing.headingSpaceAfterRange)
        }
    }

    private var paragraphStylePicker: some View {
        Picker("Paragraph style", selection: setting(\.paragraphStyle)) {
            Text("Spaced").tag(TypographySpacing.ParagraphStyle.spaced)
            Text("Indented").tag(TypographySpacing.ParagraphStyle.indented)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("preset-paragraph-style")
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<TypographySpacing, Value>) -> Binding<Value> {
        Binding(
            get: { (edits ?? preset.spacing)[keyPath: keyPath] },
            set: { value in
                var spacing = edits ?? preset.spacing
                spacing[keyPath: keyPath] = value
                edits = spacing
            })
    }
}

private struct SpacingSlider: View {
    let title: LocalizedStringKey
    let suffix: String
    let id: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    private static let stepsPerUnit = 20.0

    var body: some View {
        #if os(macOS)
            LabeledContent(title) {
                HStack(spacing: 8) {
                    slider
                        .labelsHidden()
                        .frame(width: 160)
                    Text(verbatim: measurement)
                        .monospacedDigit()
                        .frame(minWidth: 52, alignment: .trailing)
                        .accessibilityHidden(true)
                }
            }
        #else
            VStack(spacing: 4) {
                LabeledContent(title) {
                    Text(verbatim: measurement).monospacedDigit()
                }
                .accessibilityHidden(true)
                slider
            }
            .padding(.vertical, 4)
        #endif
    }

    private var measurement: String {
        value.formatted(.number.precision(.fractionLength(2))) + suffix
    }

    private var slider: some View {
        Slider(
            value: Binding(
                get: { value },
                set: {
                    let rounded = snapped($0)
                    if rounded != value { value = rounded }
                }),
            in: range
        ) { Text(title) }
        // A stepped Slider in a Form draws a tick per step on iOS 26+, with no way to hide
        // them, so the binding snaps instead and VoiceOver gets the step explicitly.
        .accessibilityAdjustableAction { direction in
            let delta = (direction == .increment ? 1 : -1) / Self.stepsPerUnit
            value = snapped(min(max(value + delta, range.lowerBound), range.upperBound))
        }
        .accessibilityValue(Text(verbatim: measurement))
        .accessibilityIdentifier(id)
    }

    private func snapped(_ value: Double) -> Double {
        (value * Self.stepsPerUnit).rounded() / Self.stepsPerUnit
    }
}
