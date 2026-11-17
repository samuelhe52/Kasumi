# 002.008 — Configurable code-block rendering and reader-owned controls

## Context and plan (2026-11-17, before implementation)

Status: Implemented. The maintainer questioned the library/reader ownership of
[002.007](007-code-block-presentation.md), then approved correcting the boundary.
The rendering library should offer styles; the reader selects its appearance.
The fixed 44 pt header and public copy-button frame were reader policy in the
core, and forced unused control space into file exports.

## Intended change

- Add a public `CodeBlockStyle` value on `RenderStyle`: configurable background
  visibility/color, corner radius, padding, and an optional language caption.
  Caption dimensions/insets are rendering parameters with no knowledge of buttons.
- Default library rendering uses its existing themed background, square corners,
  ordinary padding, and no caption. No header/control space is reserved by default.
- Expose only block/content/caption geometry, source, and language metadata through
  `RenderedCodeBlock`. Remove copy-specific frame and UI foreground fields.
- Add reader-owned style/geometry policy. The reader explicitly selects 10 pt
  corners and a 44 pt caption row with room for its native Copy control. App
  exports explicitly select compact captions without control reservations.
- Keep syntax highlighting, source fidelity, semantic text, native Copy feedback,
  and gesture admission intact. Add CLI caption/radius options for headless QA.

## Validation criteria

Extend the focused code-panel tests for independent library defaults and custom
styles, optional captions, pixel paint, semantic/source invariance, generic frame
bounds and pagination. Test the actual reader geometry/style policy through a
repository-local source link. Run relevant API/theme/paragraph/export regressions,
compile the generic unsigned iOS app, and inspect default/captioned light/dark/
narrow renders plus a PDF. No simulator/device execution or commits.

## Outcome (2026-11-17)

Implemented on `feat/syntect-highlighting`.

- `Sources/KasumiMarkdown/CodeBlockStyle.swift` adds `CodeBlockStyle` and its
  optional `Caption` style. `RenderStyle.codeBlockStyle` controls background
  visibility and optional color override, corner radius, padding, and caption
  height/insets/font size. Missing background color inherits the document theme.
  Negative/nonfinite dimensions resolve to zero; caption fonts are at least 1 pt.
  Excess horizontal padding scales down to retain a usable text measure.
- Defaults retain the original themed rectangle with 10 pt vertical and 14 pt
  horizontal padding, radius zero, and no caption. A nil caption creates neither
  a label nor a reserved row. The choices are per-render values; they do not
  change the persisted typography-profile format.
- `RenderedCodeBlock` exposes `frame`, `contentFrame`, optional `captionFrame`,
  the raw first fence-info word (`language`), complete parsed `source`, and ID.
  Copy-specific geometry and UI control colors are removed from the library API.
  Optional captions remain renderer decorations outside semantic text/search.
- `apps/iOS/Kasumi/ReaderCodeBlockStyle.swift` owns the reader's 10 pt radius,
  44 pt caption row, caption inset reserving room for Copy, and button placement.
  Its separate exporting style uses a 28 pt caption with no control reservation.
  `ReaderAppearance` selects the reading style; `ReaderExportJob` applies the
  compact style to document-based PDF/PNG/JPG exports. Frozen-snapshot exports
  continue to preserve their caller-selected snapshot layout.
- The reader selects native control colors and supplies button frames itself.
  Clipboard, feedback, accessibility, and control/selection gesture handling
  remain in the reader. No source-editor changes were made.
- The headless CLI accepts `--code-caption` and `--code-radius POINTS`, allowing
  explicit styling checks while leaving defaults neutral.

## Validation

On macOS 27.2.1 arm64; no simulator/device launched or driven:

- `make build` passed.
- `make test FILTER='CodeBlockPresentationTests|CodeSyntaxTests'`: 11 tests passed.
  Public API tests within the presentation suite check default/alternate styles,
  independent snapshots, source/semantic invariance, custom padding/background,
  caption removal, rounded/caption pixels, and pagination. The actual app-owned
  style/geometry source is linked into the test target; 60/180/360 px checks
  verify reader controls and compact export rows without duplicating its policy.
- The same named parser/theme/profile/paragraph/export/API regression selection
  as [002.007](007-code-block-presentation.md): 52 tests passed in four suites,
  with no skips. An initial exact floating-point padding assertion differed by
  approximately 7e-15; geometry comparisons now use 0.001 pt tolerance.
- `make app-check` succeeded for an unsigned generic iOS device. Xcode emitted
  its no-AppIntents-dependency metadata-extraction warning; no compile errors.
- `make render` produced an 800 px default One Light PNG, explicit rounded/
  captioned 800 px One Light and One Dark PNGs, a 360 px One Dark PNG, and an
  explicit captioned One Light PDF. All four PNGs and both headless PDFKit page
  images were visually inspected. The default has no label/header space; opt-in
  captions and rounding survive wrapping. Five PDF code-text extraction checks
  passed. Output images/PDF/logs are local and not retained in the repository.
- `git diff --check` passed. No frozen reference expectations changed.

## Remaining limits

Native taps, clipboard writes, feedback timing, scrolling from a control, and
VoiceOver remain unverified at runtime under the no-simulator constraint. Enabled captions are now repeated on PDF continuation pages; see
[002.010](010-pdf-code-continuations.md). Syntax coverage
and size fallbacks remain as recorded in [002.006](006-syntax-highlighting.md).
