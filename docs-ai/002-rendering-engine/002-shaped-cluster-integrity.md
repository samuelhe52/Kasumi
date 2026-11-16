# 002.002 — Shaped-cluster integrity

## Context

On 2026-11-16, follow-up checks of the Chinese curly-quote overlap found two
additional measurement/drawing mismatches on macOS and iOS Simulator:

- Pagella Serif: hyphenation divides `ToffeeOfficeIdentifier` inside a ligature.
  A subsequently reshaped `fi` fragment draws about 9.39 pt in a zero-width box.
- Han combining marks: `汉字\u{0301}汉字` receives excess width because normalization
  replaces the base glyph's partial advance with an em before adding the mark's
  advance. U+302A tone marks expose the same accounting error.

## Change

Implemented on 2026-11-16. The portable paragraph engine is unchanged.
`ParagraphShaper` supplies source-backed shaped spans instead of assuming every
grapheme is independently shaped. Graphemes consumed by an earlier ligature glyph
remain in that glyph's span, preventing hyphenation and emergency opportunities
inside it. `MeasuredParagraphTypesetter` retains every original grapheme boundary
for individual caret and hit-test access inside a ligature.

For graphemes with positioning combining marks, advances come from the shaped
caret boundaries rather than individual component glyphs. Plain Han and
variation-selector sequences retain the existing em policy. This preserves mark
positioning and avoids double-counting overlapping fallback runs.

Disabling ligatures was rejected because it discards intended typography. An
engine-specific ligature exception was rejected because shaping belongs in the
Core Text adapter and glyph spans apply to ordinary and emergency line breaks.

## Validation

- `make test FILTER='[Pp]aragraph|ShapedClusterIntegrityTests|chineseAfterCurlyQuote|latinAfterCJK|fallbackFontLineGap'`:
  38 tests passed on macOS, including the frozen paragraph geometry checks.
- `make test-ios FILTER=ShapedClusterIntegrityTests`: both tests, with five
  parameterized cases, passed on the iPhone 18 Pro simulator running iOS 27.2.
  These verify Pagella glyph identities, positions, ligature carets, narrow-line
  fragment widths, marked-grapheme advances, and premature wrapping.
- An initial version preserved the sum of unnormalized mark advances. It passed
  the macOS tests but failed all three iOS mark cases: fallback glyph runs can
  overlap, so summing their advances still overcounts. A focused glyph-position
  probe established this; caret-boundary measurement fixes it.
- Rendered a local Pagella Serif smoke document with `KasumiRender` and inspected
  the PNG. Both reported Latin words, Han accent/tone marks, and the original
  Chinese curly-quote example render without the reported gaps or overlaps.
- No frozen expectations changed. Temporary probe sources were removed. Physical
  device rendering and the full test suite were not checked for this change.

## Refs

- `Sources/KasumiMarkdown/ParagraphShaping.swift`
- `Sources/KasumiMarkdown/MeasuredParagraphTypesetter.swift`
- `Tests/KasumiMarkdownTests/ParagraphShapingTests.swift`
