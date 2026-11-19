import KasumiMarkdown
import SwiftUI

/// Quick reader controls and an entry point for editing the selected preset.
struct AppearanceSettings: View {
    @Binding var presetID: String
    @Binding var pairID: String
    @Binding var fontSize: Double
    @Binding var presetSpacing: ReaderPresetSpacing
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var showFonts = false
    @State private var customizingPreset: TypographyPreset?
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
            .softTopScrollEdge()
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
            .sheet(item: $customizingPreset) { preset in
                PresetSpacingSettings(
                    preset: preset, appearance: appearance,
                    edits: Binding(
                        get: { presetSpacing[preset] },
                        set: { presetSpacing[preset] = $0 }))
            }
        }
        .frame(idealHeight: 398)
        .presentationDetents([.height(398)])
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
            Button {
                customizingPreset = appearance.preset
            } label: {
                Text("Customize")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(.fill.tertiary, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("appearance-customize")
            .accessibilityHint("Edit the spacing for \(appearance.preset.name)")
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
        let preset = appearance.preset
        let isEdited = presetSpacing[preset] != nil
        return Menu {
            Picker("Typography", selection: $presetID) {
                ForEach(TypographyPreset.builtin) { option in
                    let edited = presetSpacing[option] != nil
                    Text(verbatim: edited ? "\(option.name)*" : option.name)
                        .accessibilityLabel(edited ? Text("\(option.name), customized") : Text(option.name))
                        .tag(option.id)
                }
            }
        } label: {
            HStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(preset.name).lineLimit(1)
                    if isEdited {
                        Text(verbatim: "*")
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .accessibilityHidden(true)
                    }
                }
                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium)).foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity).frame(height: 48)
            .background(.fill.tertiary, in: Capsule())
        }
        .tint(.primary)
        .menuActionDismissBehavior(.disabled)
        .accessibilityLabel("Typography, \(preset.name)")
        .accessibilityValue(isEdited ? Text("Customized") : Text(""))
        .accessibilityIdentifier("appearance-preset")
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
