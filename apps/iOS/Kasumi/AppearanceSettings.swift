import KasumiMarkdown
import SwiftUI

/// A compact panel: one row of type controls above a grid of theme cards.
/// Its content doesn't grow, so the sheet's only detent is the content height.
struct AppearanceSettings: View {
    @Binding var presetID: String
    @Binding var pairID: String
    @Binding var fontSize: Double
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var showFonts = false
    private var appearance: ReaderAppearance {
        ReaderAppearance(presetID: presetID, pairID: pairID, fontSize: fontSize)
    }

    var body: some View {
        NavigationStack {
            // Scrolls only when accessibility text sizes outgrow the screen.
            ScrollView {
                content
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Fonts", systemImage: "textformat") { showFonts = true }
                        .accessibilityIdentifier("appearance-fonts")
                }
            }
            .sheet(isPresented: $showFonts) { FontStoreView() }
        }
        .frame(idealHeight: 330)
        .presentationDetents([.height(330)])
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                sizeControl
                presetMenu
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(DocumentThemePair.builtin) { card($0) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .padding(.top, 8)
    }

    private var sizeControl: some View {
        let size = appearance.fontSize
        let sizes = ReaderAppearance.fontSizes
        return HStack(spacing: 0) {
            Button {
                fontSize = max(sizes.lowerBound, size - 1)
            } label: {
                Text("A").font(.footnote.weight(.medium)).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .disabled(size <= sizes.lowerBound).accessibilityLabel("Decrease font size")
            Text("\(Int(size))").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                .frame(minWidth: 28).accessibilityIdentifier("reader-font-size")
                .accessibilityLabel("Font size \(Int(size))")
            Button {
                fontSize = min(sizes.upperBound, size + 1)
            } label: {
                Text("A").font(.title2.weight(.medium)).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .disabled(size >= sizes.upperBound).accessibilityLabel("Increase font size")
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity).frame(height: 48)
        .background(.fill.tertiary, in: Capsule())
    }

    private var presetMenu: some View {
        Menu {
            Picker("Typography", selection: $presetID) {
                ForEach(TypographyPreset.builtin) { Text($0.name).tag($0.id) }
            }
        } label: {
            HStack(spacing: 6) {
                Text(appearance.preset.name).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium)).foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity).frame(height: 48)
            .background(.fill.tertiary, in: Capsule())
        }
        .tint(.primary)
        .accessibilityLabel("Typography, \(appearance.preset.name)")
    }

    private func card(_ pair: DocumentThemePair) -> some View {
        let theme = colorScheme == .dark ? pair.dark : pair.light
        let selected = pairID == pair.id
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button {
            pairID = pair.id
        } label: {
            VStack(spacing: 2) {
                Text("Aa").font(.title.weight(.semibold))
                Text(pair.name).font(.caption.weight(.medium)).lineLimit(1)
            }
            .foregroundStyle(color(theme.document["text"]!))
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(color(theme.document["paper"]!), in: shape)
            .overlay {
                if selected {
                    shape.strokeBorder(.tint, lineWidth: 3)
                } else {
                    shape.strokeBorder(.separator)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pair.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("theme-" + pair.id)
    }

    private func color(_ value: DocumentColor) -> Color {
        Color(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
    }
}
