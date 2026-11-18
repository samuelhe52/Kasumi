# 004.008 — Reader preset spacing

## Context

The maintainer chose to keep text size as a reader-wide control and let each
typography preset remember its own spacing. Appearance remains the place to
switch presets and change size. Customize opens a full-height editor for the
selected preset with a live sample above the controls.

## Design

- Keep the existing reader font-size preference. Interpret the legacy zero as
  the reader default of 16 pt, which matches the shipped presets' base size.
- Save spacing by preset ID. The preset's bundled values supply the starting
  point and reset target. Mark edited presets in the picker.
- Resolve saved spacing into the preset used by the reader, sample, export,
  and print. PDF and image output retain their format-specific font sizes.

## Implementation

The Appearance panel retains its global size stepper and adds Customize beneath
the theme cards. The editor names the preset, pins a sample rendered by
`RenderedDocument` above the controls, and saves changes live. Restoring the
preset removes its spacing entry from reader preferences. The picker marks
presets with a stored edit using an asterisk.

`apps/iOS/Kasumi/ReaderAppearance.swift` persists spacing separately from the
bundled presets. `TypographyPreset.applyingSpacing` in
`Sources/KasumiMarkdown/RenderStyle.swift` derives the effective preset used by
the reader and its existing export path. Spacing follows the output font size.

## Validation

- `make test FILTER=editedPresetSpacingReachesReaderAndExport` passed. The test
  exercises reader geometry, file-backed PDF pagination, and PNG height.
- `make app` built for iPhone 18 Pro (iOS 27.2). On that simulator, Serif's
  edited line spacing and marker persisted through a preset switch and app
  relaunch. Book retained its factory spacing, updating its paragraph style
  enabled Restore, and Restore returned Book to Indented and disabled itself.
  Both heading sliders accepted edits. The global size stayed at 17 pt
  through the preset switch and relaunch.
- The app opened a two-page system Print preview with the edited Serif
  preset active.
- The preview and controls were visually checked on iPhone. The iPad
  presentation remains to be checked.
