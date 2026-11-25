import KasumiMarkdown
import SwiftUI

struct MacAppearancePreferences: DynamicProperty {
    @AppStorage("reader.preset") var presetID = "serif"
    @AppStorage("reader.theme-pair") var pairID = "mono"
    @AppStorage("reader.font-size") var fontSize = ReaderAppearance.defaultFontSize
    @AppStorage("reader.preset-spacing") var presetSpacing = ReaderPresetSpacing()

    var appearance: ReaderAppearance {
        ReaderAppearance(presetID: presetID, pairID: pairID, fontSize: fontSize)
    }
}

struct MacSettings: View {
    var body: some View {
        TabView {
            Tab("Appearance", systemImage: "textformat.size") { MacAppearanceSettings() }
            Tab("Spacing", systemImage: "line.3.horizontal.decrease") { MacSpacingSettings() }
            Tab("Fonts", systemImage: "textformat") { MacFontSettings() }
        }
        .frame(width: 535, height: 430)
    }
}

private struct MacAppearanceSettings: View {
    private var preferences = MacAppearancePreferences()

    var body: some View {
        Form {
            Picker("Theme", selection: preferences.$pairID) {
                ForEach(DocumentThemePair.builtin) { Text($0.name).tag($0.id) }
            }
            Picker("Typography", selection: preferences.$presetID) {
                ForEach(TypographyPreset.builtin) { Text($0.name).tag($0.id) }
            }
            LabeledContent("Reading size") {
                Slider(value: preferences.$fontSize, in: ReaderAppearance.fontSizes, step: 1)
                    .labelsHidden()
                    .accessibilityLabel("Reading size")
                Text("\(Int(preferences.appearance.fontSize)) pt").monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .formStyle(.grouped)
    }
}

private struct MacSpacingSettings: View {
    private var preferences = MacAppearancePreferences()

    var body: some View {
        let preset = preferences.appearance.preset
        let edits = Binding(
            get: { preferences.presetSpacing[preset] },
            set: { preferences.presetSpacing[preset] = $0 })

        VStack(spacing: 0) {
            Form {
                Picker("Typography", selection: preferences.$presetID) {
                    ForEach(TypographyPreset.builtin) { Text($0.name).tag($0.id) }
                }
                SpacingControls(preset: preset, edits: edits)
            }
            .formStyle(.grouped)

            Divider()
            Button("Restore \(preset.name) Defaults") { edits.wrappedValue = nil }
                .disabled(edits.wrappedValue == nil)
                .accessibilityIdentifier("preset-restore-defaults")
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
    }
}

private struct MacFontSettings: View {
    private let store = FontStore.shared

    var body: some View {
        Form {
            ForEach(FontChoice.all) { choice in
                Section(choice.title) {
                    FontPackageRow(package: choice.apple)
                    FontPackageRow(package: choice.open)
                    if store.state(choice.open) == .installed {
                        Button("Remove \(choice.open.name) Download", role: .destructive) { store.remove(choice.open) }
                    }
                }
            }
            Section("Supporting Fonts") {
                ForEach(FontChoice.supporting) { FontPackageRow(package: $0) }
            }
        }
        .formStyle(.grouped)
    }
}
