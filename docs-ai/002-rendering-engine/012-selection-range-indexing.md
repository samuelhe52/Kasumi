# 002.012 — Bound selection lookup to overlapping text

## Context and intended change (2026-11-17)

Active Find requests selection rectangles for every result after each installed
snapshot and horizontal table scroll. Each request currently scans every semantic
map segment, measured line and paragraph, even when it covers one word. This
repeats document-length work for each match after viewport layout has already
reduced construction costs.

- Seek into ordered semantic segments before mapping a selection or caret to
  rendered offsets. Preserve expansion of attachment interiors, adjacent equal
  attachments and zero-semantic-length capsule padding.
- Seek into ordered measured-line and paragraph source ranges before building
  selection geometry. Keep measured/estimated geometry, table cell ordering and
  snapshot-local lazy-fragment locking unchanged.
- Keep the public API and Find matching/navigation behavior unchanged. Match
  searching and UIKit highlight-path construction remain separate costs.
- Compare indexed lookup with exhaustive reference geometry and independent
  semantic mapping cases, including UTF-16/graphemes, gaps, empty paragraphs,
  attachments, tables, hard breaks, RTL fallback and viewport estimates. Measure
  warm headless search and geometry separately before/after; exclude layout and
  native UI from those measurements. No simulator run.

The ordered ranges already exist in each immutable layout. Binary search avoids
a document-wide selection-result cache and its invalidation/ownership cost. A
prefix-end index is unnecessary here: logical line starts/ends are ordered by
source, including RTL fallback, empty code rows and table cells. Paragraph and
semantic-segment intervals are disjoint and ordered.

## Implementation

`DocumentTextMap` binary-searches the first semantic segment ending after the
requested offset. Range conversion visits segments only until the selection's
end. Zero-length semantic spans are skipped at the boundary; an interior offset
still expands to its attachment's rendered range. End-of-document carets retain
their existing rendered-end behavior, including trailing synthetic padding.

`RenderedDocument.selectionRects(for:)` similarly seeks into its existing logical
lines and placed paragraphs. It visits intersecting source coverage, keeps Core
Text access under the same snapshot lock, and preserves the existing combination
and vertical ordering of exact/estimated rectangles. It adds no per-line index,
mutable cache, public API or cross-snapshot layout object.

## Validation

- Exhaustive semantic-offset/range checks cover every UTF-16 position in a small
  authored sequence with family emoji, combining marks, CJK, adjacent identical
  attachments, multi-character replacements and empty capsule padding.
- Selection geometry is compared with an exhaustive scan at two widths, in full
  and viewport layouts. Queries include logical line/paragraph boundaries,
  interior offsets, empty selections and selections extending to the document
  end. The corpus includes wrapped links, capsule code, a multirow table,
  formulas, a missing-image fallback, blank code rows, hard breaks and RTL.
- The initial six focused Release tests passed, including existing public API,
  adjacent-object and capsule checks. The broader Release selection passed 106
  tests across six suites, including the new exact boundary queries plus
  viewport/reflow, reading, public API, math, shaping and profile regressions.
- The Release app build passed. On iPhone 18 Pro/iOS 27.2 Simulator, Find for
  `文` in the authored 100-paragraph CJK/table document painted dense highlights;
  Next Result moved the active highlight and scrolled to it, and closing Find
  returned to the reader. These observations are functional, not latency/frame
  measurements. The narrow search bar did not display a numeric result count.
  Frozen measurements and `docs/development.md` remain unchanged in this slice.

## Mac measurements

Release on Apple M1 Pro/macOS 27.2.1, 500 pt width. An authored 50k-character
English/Chinese body is split into either 100 paragraphs of 500 characters or
1,000 paragraphs of 50 characters, excluding added paragraph separators. Find
queries are `text` and `文`. Each full/viewport snapshot is built once; viewport
layout covers an 800 pt middle region. A geometry pass warms lazy fragments
before 30 timed repetitions. Timings exclude layout, text-field handling, word
segmentation, UIKit path construction/installation, bitmap painting and disposal.

Baseline `f89888c`; subsequent integration of `main` does not change this plain-text
corpus. Before/after match counts and aggregate rectangle checksums agree. The
opt-in harness is `KASUMI_FIND_TIMING=1 make test SWIFT_CONFIGURATION=release
FILTER=macFindTimings` in `Tests/KasumiMarkdownTests/SelectionLookupTests.swift`.

Median time to obtain rectangles for all results, milliseconds:

| Language | Paragraphs | Matches | Full before → after | Viewport before → after |
| --- | --- | --- | --- | --- |
| English | 100 | 400 | 13.51 → 0.50 | 2.39 → 0.15 |
| English | 1,000 | 1,000 | 34.92 → 1.24 | 36.88 → 0.42 |
| Chinese | 100 | 1,200 | 82.61 → 1.85 | 7.59 → 0.41 |
| Chinese | 1,000 | 2,000 | 144.35 → 3.34 | 75.39 → 0.76 |

For Chinese with 1,000 paragraphs, viewport geometry p95/maximum change from
76.47/77.47 to 0.91/0.94 ms. Search is unchanged: its viewport median is
2.76 ms before and 2.90 ms after, a separate measurement rather than an
improvement claim. These samples do not establish native frame rate.

## Remaining limits

Find still searches the complete semantic text and optionally segments words on
each installed snapshot. The reader still constructs paths for every match,
including offscreen estimated matches. Huge selections must visit every
overlapping line/paragraph and can materialize their fragments. UI installation,
final snapshot-release tails, cold preparation and offscreen table/attachment
layout remain separate optimization targets.
