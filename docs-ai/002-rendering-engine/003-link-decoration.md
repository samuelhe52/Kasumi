# 002.003 — Link decoration geometry

## Context

The initial link indicators used attributed-string single underlines. The maintainer rejected their appearance: native underlines use font-specific placement, opacity, and descender gaps, rather than a consistent document decoration. Footnote references also acquired a disconnected underline at the body baseline.

## Approach (2026-11-16)

Replace native underline attributes with rectangles computed once from the paragraph engine's source-backed line positions and cached with `ParagraphLayout`. Paint them after paragraph contents, including code capsules and inline math. Keep glyphs, hit testing, selection, wrapping, and pagination unchanged.

The recovered geometry is independent of font underline metrics:

- Top edge: baseline + 0.185 × paragraph font size.
- Thickness: max(0.5 pt, 0.07 × paragraph font size).
- Heading fragments and HTTP(S) destinations: solid, text color with alpha 0.4.
- File and other destinations: dashed, text color with alpha 0.7; dash 0.3 em, gap 0.15 em.
- Footnote references and images: no underline. Linked inline code and math participate.
- Contiguous styles within one link share base coverage; wrapping produces a separate stripe on each line. Glyph-outline clearance then cuts descender gaps from that stripe; see [004-underline-clearance.md](004-underline-clearance.md).

This corrects the earlier footnote treatment rather than preserving it. Ordinary attributed underlines now use the same normalized metadata and glyph-clearance geometry as links; they no longer use native underline painting. The general Core Text fallback remains for unrelated effects.

## Validation plan

Focused geometry and raster regressions must distinguish the new indicator from native underlines, cover wrapped/mixed links and non-underlined footnotes/images, and verify dashed targets and alpha in both appearances. Render `fixtures/LinkIndicators.md` and `fixtures/LinkJumps.md` on macOS; provide light/dark screenshots. No simulator or external application is a build/test dependency.

## Current state

Implemented in `Sources/KasumiMarkdown/TextUnderline.swift` and
`Sources/KasumiMarkdown/UnderlineClearance.swift`, with painting in
`Sources/KasumiMarkdown/DocumentLayout.swift`. `Typography.swift` normalizes
ordinary underline attributes before shaping. The placed-paragraph-only link
cache was replaced by shared paragraph decoration storage in [004](004-underline-clearance.md).

Initial validation on macOS, 2026-11-16 (before the glyph-clearance follow-up):

- `make test FILTER=LinkUnderlineTests`: four tests passed (seven parameterized
  cases), including independent raster comparison, wrapped mixed-style links,
  file/email dashes, linked math/code, and unmarked images/footnotes.
- The first focused run failed: `CGRect.union` changed rectangle height by a
  floating-point ulp, splitting later styles into separate indicators. Horizontal
  coalescing now preserves vertical metrics; the same regressions then passed.
- Rendered `fixtures/LinkIndicators.md` in Mono Light and Mono Dark with
  `KasumiRender`; inspected both PNGs. Also rendered the four heading links from
  `fixtures/LinkJumps.md` at 32 pt for comparison with the maintainer's screenshot.
  Screenshots are local build output, not retained regression assets.
- No simulator/device run. No frozen reference measurements changed.
