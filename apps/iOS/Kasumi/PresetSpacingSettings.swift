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
                    Form {
                        SpacingControls(preset: preset, edits: $edits)
                        Section {
                            RestoreSpacingDefaults(preset: preset, edits: $edits)
                        }
                    }
                    .softTopScrollEdge()
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

private struct RestoreSpacingDefaults: View {
    let preset: TypographyPreset
    @Binding var edits: TypographySpacing?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isAtDefaults = edits == nil
        Button {
            edits = nil
        } label: {
            Text("Restore \(preset.name) Defaults")
                .foregroundStyle(isAtDefaults ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.accentColor))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isAtDefaults)
        }
        .disabled(isAtDefaults)
        .accessibilityIdentifier("preset-restore-defaults")
    }
}

private struct SpacingPreview: View {
    let style: RenderStyle

    private static let sample = MarkdownDocument(
        markdown: """
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
            .softTopScrollEdge()
            .background(Color(cgColor: rendered.backgroundColor))
        }
        .accessibilityHidden(true)
    }
}
