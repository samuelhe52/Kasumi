# 002.004 — Shared underline geometry and glyph clearance

## Context

The maintainer supplied enlarged `p` and `g` examples showing that underlines avoid descender outlines. The preceding implementation recovered the base decoration rectangle but omitted the subsequent glyph-clearance pass. Its uninterrupted-rectangle raster expectation therefore enforced the wrong behavior.

Ordinary attributed underlines should use the same geometry and clearance as links, not a separate font-dependent painter. Isolated parser probes also showed that `<u>` and `<ins>` remove the tags without producing an underline paint flag; this work does not invent standalone Markdown underline syntax or add an attributed-string public API.

## Approach (2026-11-16)

- Normalize enabled attributed underline styles into private rendering metadata before shaping. Use the shared single-line decoration, preserving explicit underline color when present. Avoid native underline attributes reaching Core Text drawing.
- Cache ordinary and link decorations with `ParagraphLayout`, after shaping, so drawing uses the same engine geometry in both paths. Remove the placed-paragraph-only link cache.
- For each underline band, inspect the actual painted glyph outlines, including font fallback, ligatures, italic outlines, baseline offsets, and inline math. Exclude outline intersections, not a whole character's advance box and not a hard-coded list of descenders.
- Clip each outline element's control polygon against the band as straight segments: lines and closes as themselves, quadratics as `start→control→end`, cubics as `start→control₁→control₂→end`. This matches the reference's path callback, which never evaluates the curve itself. Because a control polygon encloses its curve, the cut can only be wider than the exact outline. In New York the two agree to about 0.001 em, since its curve extrema are on-curve points. Fonts whose curves bulge past their endpoints get slightly wider cuts.
- Recovered clearance parameters: normalized glyph-band coordinates quantized to 1/10,000 em; collision detection begins 0.02 decoration-em below the stripe's top; contour measurement expands the vertical band by 0.06 glyph-em and the resulting horizontal exclusion by 0.06 glyph-em. Merge exclusions before subtracting them from the base rectangle. Preserve the original dash phase across gaps.
- Reuse per-layout glyph/band results; never recompute contours during tile painting. Keep fallback behavior for unrelated Core Text paint effects.

## Validation plan

Focused geometry/raster checks for ordinary versus linked underlines, `p` stems and `g` loops separately, curves, wrapping, scripts, math, dash-phase continuity, and tiled rendering. Inspect enlarged macOS-rendered examples corresponding to the supplied crops. No simulator, external binary, or analysis tool is a build/test dependency.

## Current state

Implemented in `Sources/KasumiMarkdown/UnderlineClearance.swift`, with geometry and caching in `Sources/KasumiMarkdown/TextUnderline.swift`.

- 2026-11-16, first pass: clearance solved the exact Bézier roots of each outline segment.
- 2026-11-16, review: subpixel measurement of the maintainer's crops gave matching gaps from the underline end to the `g` loop ink (0.049 em reference, 0.044 em Kasumi, within compression noise) and matching `p` foot clearance. Clearance now clips control polygons and the exact root solver is gone. In New York the cut changes by at most about 0.001 em for `g` and not at all for `p`.
- Performance, 2026-11-16: a release render of a 6,000-paragraph document where nearly every phrase is a link took about 7.7–8.4 s with underlines and 6.75 s with the underline pass disabled. A per-layout glyph-extent check, keyed by font identity, now rejects glyphs that cannot reach the stripe before the full cache key is hashed. Rendered output is byte-identical; the gain is small. The remaining cost is that each underline segment re-walks every fragment and run on its line. Collecting a line's glyphs once, limited to the underlined span, is the next step if real documents show it.

Validation: `make test FILTER='UnderlineClearanceTests|LinkUnderlineTests|ParagraphDrawingTests'` passed (12 tests in 3 suites). `UnderlineClearanceTests` uses densely sampled point-in-outline queries as an independent oracle and requires each cut to cover the outline, exceeding it by less than 0.01 em. Rendered `fixtures/LinkIndicators.md` in Mono Dark with `KasumiRender` and inspected the `p` and `g` lines. No simulator or device run. No frozen reference measurements changed.
