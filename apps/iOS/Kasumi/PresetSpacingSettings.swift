import KasumiMarkdown
import SwiftUI

struct PresetSpacingSettings: View {
    let preset: TypographyPreset
    let appearance: ReaderAppearance
    @Binding var edits: TypographySpacing?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    private let fonts = FontStore.shared

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    SpacingPreview(style: previewStyle)
                        .frame(height: min(240, geometry.size.height * 0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    SpacingControls(preset: preset, edits: $edits)
                }
            }
            .navigationTitle("Customize \(preset.name)")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationSizing(.page)
    }

    private var previewStyle: RenderStyle {
        _ = fonts.revision
        var style = appearance.style(
            dark: colorScheme == .dark, regular: false, preferredOpen: fonts.preferredOpen, spacing: nil)
        style.preset = edits.map(preset.applyingSpacing) ?? preset
        style.insets = .init(top: 14, left: 18, bottom: 10, right: 18)
        return style
    }
}

private struct SpacingPreview: View {
    let style: RenderStyle

    private static let sample = MarkdownDocument(markdown: """
        A path through the pines led down to the shore.

        松林尽头，海面泛着微光。

        ## At the water’s edge

        The tide was turning.
        """)

    var body: some View {
        GeometryReader { geometry in
            let rendered = RenderedDocument(Self.sample, width: max(1, geometry.size.width), style: style)
            ScrollView {
                Canvas { context, size in
                    context.withCGContext {
                        rendered.draw(in: $0, rect: CGRect(origin: .zero, size: size))
                    }
                }
                .frame(height: rendered.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .background(Color(cgColor: rendered.backgroundColor))
        }
        .accessibilityHidden(true)
    }
}

private struct SpacingControls: View {
    let preset: TypographyPreset
    @Binding var edits: TypographySpacing?

    var body: some View {
        Form {
            Section("Spacing") {
                SpacingSlider(
                    title: "Line spacing", suffix: "×", id: "preset-line-spacing",
                    value: setting(\.lineSpacing), range: TypographySpacing.lineSpacingRange)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paragraph style")
                    Picker("Paragraph style", selection: setting(\.paragraphStyle)) {
                        Text("Spaced").tag(TypographySpacing.ParagraphStyle.spaced)
                        Text("Indented").tag(TypographySpacing.ParagraphStyle.indented)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("preset-paragraph-style")
                }
                .padding(.vertical, 4)
            }
            Section("Heading spacing") {
                SpacingSlider(
                    title: "Above", suffix: " em", id: "preset-heading-above",
                    value: setting(\.headingSpaceBefore), range: TypographySpacing.headingSpaceBeforeRange)
                SpacingSlider(
                    title: "Below", suffix: " em", id: "preset-heading-below",
                    value: setting(\.headingSpaceAfter), range: TypographySpacing.headingSpaceAfterRange)
            }
            Section {
                Button("Restore \(preset.name) Defaults") { edits = nil }
                    .disabled(edits == nil)
                    .accessibilityIdentifier("preset-restore-defaults")
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
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

    var body: some View {
        let measurement = value.formatted(.number.precision(.fractionLength(2))) + suffix
        VStack(spacing: 4) {
            LabeledContent(title) {
                Text(verbatim: measurement).monospacedDigit()
            }
            .accessibilityHidden(true)
            Slider(
                value: Binding(
                    get: { value },
                    set: {
                        let rounded = ($0 * 20).rounded() / 20
                        if rounded != value { value = rounded }
                    }),
                in: range
            ) { Text(title) }
            .accessibilityValue(Text(verbatim: measurement))
            .accessibilityIdentifier(id)
        }
        .padding(.vertical, 4)
    }
}
