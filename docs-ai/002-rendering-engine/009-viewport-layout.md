# 002.009 — Viewport-first paragraph layout

## Context and intended change (2026-11-17)

Session snapshots still rebuild every paragraph's exact line geometry before
publication. The previous warm 50k-Chinese Mac measurement was about 60 ms for
construction, despite deferred drawing fragments. Interactive layout should
measure paragraphs near the semantic reading anchor and estimate other heights.

- Add an opt-in session viewport request. Keep ordinary construction, full session
  rendering, and exports exact. Retain full semantic text, paragraph keys and
  offsets in viewport snapshots, including paragraphs without measured lines.
- Index height estimates by paragraph within a content/style/font session. Reuse
  measured heights at the same measure and scale estimates when measure changes.
  Build exact paragraphs around the relocated reading anchor with overscan, then
  expand until the clamped viewport is covered. Construction-local reuse must
  avoid re-typesetting a paragraph when estimate correction expands the window.
- Published snapshots remain immutable. Offscreen geometry in a viewport snapshot
  is explicitly approximate; coverage queries let clients request a refined
  snapshot. Scrolling and navigation retain semantic anchors while estimated
  heights and content extent change. Selection must transfer semantic offsets
  between snapshots of the same content revision.
- Initially use the exact path for documents with tables, block attachments or
  inline image/math attachments. Their coupled/width-dependent geometry is a
  separate coverage extension. An enormous paragraph is still broken in full.
- Do not share mutable Core Text layout objects between snapshots. A session may
  retain preparation and height values; exact paragraph objects may be reused
  only within one snapshot's construction.
- Use vertical proximity to choose estimated hit-test paragraphs, including
  offscreen gaps and document ends; full-measure estimated widths must not
  outrank measured visible text.
  Coverage and viewport selection must conservatively include estimated paint
  overhangs, including quote bars above/below the paragraph body box.
- Explicit anchors for zero-line blocks, such as empty headings, must retain
  their origin after measurement. Normal scroll-position capture still skips
  blocks with no readable line.

## Validation plan

Protect viewport coverage after poor estimates, middle/end anchors, successive
widths, deep navigation, semantic text/search/copy, selection and caret geometry
inside measured paragraphs, independent snapshots, exact export and unsupported
content fallback. Count measured paragraphs so pixel parity cannot hide eager
layout. Compare warm construction and viewport painting against the full-session
path on Mac with the existing English/Chinese sizes and widths. Run focused
package tests and app compilation. Frozen fixtures and `docs/development.md`
remain unchanged; no simulator run.

## Implementation

`DocumentReflowSession.render(width:viewportHeight:anchor:)` opts into viewport
layout. `ViewportLayout.swift` places estimated paragraph slots, relocates the
semantic anchor, then measures intersecting paragraphs with half a viewport of
overscan (at least 128 pt). It expands the measured set until the clamped viewport
and overscan are covered. Exact paragraph objects are reused across construction
passes, then owned by that snapshot; subsequent snapshots receive independent
Core Text objects.

`ReflowPreparation` retains each paragraph's last measured height and measure.
Unknown heights use prepared advance totals; changed measures scale the previous
height by the width ratio and round to line-height units. These are estimates,
not line-breaking results. The snapshot's estimated spans have a sorted prefix
maximum index so `needsLayout(in:)` checks coverage with a binary search.
The spans include a line height of paint allowance on each edge (at least 2 pt
for fixed-width strokes at small font sizes). Viewport selection uses the same
conservative bounds, so a quote bar extending above an unmeasured body cannot
be mistaken for complete painting or an exportable region. Vertical proximity
decides whether hit testing needs an estimated paragraph; estimates do not win
on horizontal width, and gap/end queries remain near their offscreen location.
`ReadingPositionIndex` includes unmeasured paragraphs' keys, offsets and estimated
positions. Explicit text/heading/footnote navigation can produce a semantic anchor
without relying on an estimated rectangle.
Exact-key relocation retains the origin of a zero-line block, so measuring an
empty heading cannot redirect its anchor to a neighboring paragraph. Ordinary
reading-position capture and unmatched-anchor fallback still skip zero-line blocks.

The reader prefetches when scrolling within a quarter viewport of unmeasured
content. Requests carry the anchor and viewport height; a changed anchor rejects
obsolete work while repeated widths at the same anchor can still publish.
Same-width/content refinements retain the text-input view and replace its drawing
layers, keeping UIKit's gesture owner alive. Selections transfer semantic offsets
to the new snapshot's position namespace. UIKit positions use a view-owned UUID
and semantic offsets, so positions held by an active gesture survive same-content
refinement while positions from another page remain invalid. Deep Find, outline
and fragment navigation first refine the target,
then apply the final scroll inset using exact geometry. User dragging cancels a
pending reveal.

Snapshot PNG/JPEG export accepts a measured region; it throws
`DocumentExportError.incompleteLayout` when the requested image includes
unmeasured text. Clients can request a full-session layout for a complete image.
This preserves frozen snapshot content instead of silently omitting paragraphs
or re-resolving mutable fonts/resources during snapshot export. The app's
document-based export path continues to build exact full layouts.

## Validation

- `make test SWIFT_CONFIGURATION=release` with the focused viewport, reflow,
  scheduler, reading-position, paragraph-engine/drawing, public-API, table,
  underline, shaped-cluster, export and pagination filters passed 67 tests across
  11 suites; the opt-in timing test was skipped in that run. The engine suite
  includes the 782 frozen reference cases, whose expectations are unchanged.
- New viewport checks compare visible pixels and caret geometry against full
  layouts at narrow/wide widths and beginning/middle/end anchors with nonzero
  semantic offsets. They cover cold deep navigation, severely overestimated
  heights, headings and footnotes, selection-position transfer, complete semantic
  text/search, snapshot independence, measured-region exports and incomplete-image
  rejection. Additional checks compare wide-margin hit positions/carets against
  full layout, protect offscreen gap/EOF locality, and require quote-bar crop
  refinement before decoded-pixel export parity. Empty and duplicate-empty
  headings retain their origin across measurement and width changes, including
  after a preceding paragraph taller than the viewport. Tables, inline math,
  block math, images and diagrams exercise exact
  fallback; a huge single paragraph exercises the full-paragraph limit.
- The Release app build passed. UIKit interaction and display behavior were not
  executed. No simulator or device was launched.
- The opt-in Mac phase benchmark passed in full and viewport modes, 100 samples
  per language/size, using `KASUMI_REFLOW_TIMING=1` and
  `KASUMI_REFLOW_VIEWPORT=1` for the viewport run.

## Mac measurements

Release, Apple M1 Pro, macOS 27.2.1; 500-character paragraphs, 16 pt text, no
width cap, widths 800/500/400/700/440 pt, 20 samples per width (100 per case).
Both paths use the same semantic middle-of-document anchor and paint an 800 pt
viewport at 2x. Construction, first paint and old-snapshot disposal have separate
timers. Parsing, cold preparation, bitmap allocation and UIKit installation are
excluded; preparation is warmed with a full layout at 600 pt.

Combined medians across widths, milliseconds; viewport values use the repeat run:

| Text | Full → viewport construction | Full → viewport first paint | Full → viewport disposal |
| --- | --- | --- | --- |
| 10k English | 3.82 → 1.64 | 6.49 → 6.40 | 0.20 → 0.15 |
| 10k Chinese | 10.75 → 2.47 | 10.90 → 10.65 | 0.65 → 0.27 |
| 50k English | 16.76 → 2.00 | 6.18 → 6.23 | 0.55 → 0.16 |
| 50k Chinese | 54.10 → 3.25 | 11.34 → 10.50 | 2.55 → 0.31 |

The original 50k snapshots measure 6–10 of 100 English paragraphs and 3–6 of 100 Chinese
paragraphs, depending on width. For 50k Chinese, construction p95 falls from
82.32 to 6.41 ms and maximum from 84.65 to 6.53 ms in these samples. First-paint
p95 remains 17.83 ms (18.58 ms maximum). The first viewport run measured 2.96 ms
median construction for 50k Chinese and 1.76 ms for English. Disposal still had a
4.04 ms outlier in the repeat run. These phase samples do not establish
native resize frame rate or end-to-end latency.

With conservative paint-overhang coverage enabled, a final 50k-only check (100
samples per language, same widths/anchor) measured 1.90 ms English and 3.64 ms
Chinese median construction. It measured 6–11 English and 3–6 Chinese paragraphs.
Chinese construction p95/maximum were 5.79/6.47 ms; first-paint median/p95 were
10.13/17.32 ms. This check confirms the boundary guards retain the construction
improvement; it does not measure UIKit responsiveness.

Process high-water RSS reaches 198.66 MiB in the full run and 159.53 MiB in the
viewport repeat run (159.77 MiB on the first viewport run). Each run includes
earlier sizes/languages, runner/font caches,
bitmap contexts and overlapping snapshots; this is not allocation attribution.

## Remaining limits

- Cold preparation still processes the complete document. Placement and semantic
  metadata assembly remain proportional to paragraph count, though exact line
  breaking and geometry are restricted to the measured window.
- Tables, block attachments and inline image/math attachments currently send the
  complete document through full layout. Decorated text can use viewport layout,
  but its measured paragraphs still build decoration-dependent fragments eagerly.
- An enormous paragraph is still broken and measured as a whole. Poor estimates
  or large jumps can expand the measured set; the scrollbar extent changes as
  heights refine. Content beyond the prepared window can be temporarily unpainted
  while its next snapshot is built.
- UIKit resizing, selection handles during refinement, keyboard insets, animated
  navigation, installation and final UI ownership have no runtime validation in
  this slice. Painting and UI tail costs remain separate optimization priorities.
