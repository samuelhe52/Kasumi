# 002.011 — Extend viewport layout to mixed content

## Context and intended change (2026-11-17)

A single table, image, formula or diagram currently sends the complete document
through exact full layout. A link/underline also prevents fragment deferral for
every line in its paragraph. These fallbacks limit the benefit of viewport-first
layout for ordinary mixed Markdown.

- Allow surrounding prepared text to remain estimated in mixed documents. Keep
  table cells and attachment-bearing paragraphs exact in this slice; very large
  tables and attachment paragraphs remain a separate measurement problem.
- Freeze attributed inputs and attachment objects within one snapshot's placement
  passes. Repeated passes must not mix resource versions or recreate layout-owned
  Core Text objects. Each new snapshot constructs fresh width-dependent attachments.
  Cache table column measurement only within that snapshot's construction.
- Permit fragment deferral in prepared paragraphs with underline candidates.
  Underline/clearance construction already touches decorated lines; those lines
  materialize while unadorned lines stay deferred. Reuse immutable glyph values
  wherever the direct painter supports them, preserving all fallback behavior.
- Retain the reader's text-input and horizontal-table scroll views across same-
  width/content refinements. Update their owned drawing layers and geometry while
  preserving semantic selection and horizontal offsets/gesture ownership.
- Verify mixed semantic maps, viewport and table pixels, image/math/diagram
  ownership across snapshots, width-dependent resource sizing, deep navigation,
  underline clearance, and default full-layout/export parity. Measure before and
  after with a frozen authored mixed suffix appended to the existing Mac corpus.
  Keep frozen expectations and `docs/development.md` unchanged; no simulator run.

## Implementation

`ViewportConstruction` now memoizes attributed input by block/slot and attachment
input by block for its placement passes. It also retains table column widths for
that construction. These objects never become session-level resource caches: a
new snapshot builds fresh attachment objects for its width and available resources.
The stored paragraph source and document text storage therefore refer to the same
attachment version even when estimate correction needs another pass.

The document-wide fallback is removed. Table blocks and block attachments force
exact paragraphs; inline attachments remain unprepared/exact through the existing
preparation guard. Other prepared text can stay estimated. Table row/cell coupling
is preserved; this change does not virtualize a large table internally.

Prepared paragraphs can defer fragments even when they have underline candidates.
The existing underline/clearance pass materializes lines that actually need
decoration geometry. Other lines keep their lazy stores. The synchronized glyph
value cache also accepts supported paint in these paragraphs; unsupported styles
retain their original fallback.

Same-width/content page refinement now retains table scroll views by table ID,
replacing their drawing layers and document-space frames. Stable horizontal
geometry preserves offsets and active edge bouncing; changed geometry clamps as
needed. Same-content page replacement also transfers/clamps horizontal offsets.
Viewport prepainting uses those offsets. Non-scrolling Find remaps update geometry
and highlights without revealing a different horizontal position.

## Validation

- The broader Release selection passed 110 tests across 11 suites, covering
  viewport/reflow/reading geometry, paragraph references, interaction/public API,
  table and underline painting, math, diagrams, images and exports. The opt-in
  timing test ran separately. Frozen expectations remain unchanged.
- New mixed checks compare viewport pixels around the section and deep image,
  formula and diagram targets with full layouts at widths 400/800/320. Both table
  edges match independent full-layout pixels; column widths and row heights
  match. Image sizes change with measure. Table and attachment paragraphs remain
  exact while most surrounding paragraphs stay estimated.
- Storage/paragraph attachment identities match within a construction and are
  disjoint across retained snapshots. Semantic maps match freshly derived maps.
  A long linked paragraph initially materializes fewer than one quarter of its
  fragments; ordinary and linked viewport pixels/selection match eager layout.
- The Release app build passed. A subsequent source-editor integration check on
  iPhone 18 Pro/iOS 27.2 Simulator exercised an authored 100-paragraph CJK document
  with a formula/table: horizontal pan survives Source/Preview switching; widening
  until the table fits clamps its offset, and narrowing restores overflow. With
  Find active (1 of 2 table matches), manually panning away and resizing from
  460 to 450 pt does not reveal the current match again. Resize Mode also covered
  600 pt and the scene's 437 pt minimum at that stage, then returned to the
  402 pt main display. Native selection gestures were not checked; these checks
  do not measure frame rate or continuous-drag tails.

## Mac measurements

Baseline `61cc167`, Release, Apple M1 Pro/macOS 27.2.1. The existing authored 50k
English/Chinese corpus (100 paragraphs, 500 characters each) has a fixed suffix
containing a small table with inline formula/image cells, an inline formula,
image block, display formula and diagram. `KASUMI_REFLOW_MIXED=1` selects it in
the opt-in timing harness. There are 110 placed paragraphs. Other settings match
the earlier phase: five widths, 20 samples per width, semantic middle anchor,
800 pt viewport at 2x. Parsing, cold preparation, bitmap allocation and UIKit
installation are excluded; the suffix is offscreen at the sampled anchor.

Combined medians across widths, milliseconds:

| Language | Construction before → after | Paint before → after | Disposal before → after |
| --- | --- | --- | --- |
| English | 19.38 → 4.00 | 1.07 → 1.04 | 0.56 → 0.14 |
| Chinese | 56.91 → 5.19 | 1.57 → 1.35 | 2.67 → 0.28 |

Before, every sample measures all 110 paragraphs. After, English measures 16–20
and Chinese 14–16. Chinese construction p95/maximum fall from 83.50/89.22 to
7.71/9.00 ms. Process high-water RSS at the Chinese case changes from 188.83 to
152.56 MiB. This includes earlier English samples, fonts, the runner, contexts
and overlapping snapshots, not object allocation attribution. Disposal still has
a 5.17 ms outlier. These headless samples do not establish native frame rate.

## Remaining limits

Table column measurement and every cell still build for each snapshot. Every
attachment-bearing paragraph and block attachment remains exact even offscreen.
Very large tables, diagrams, or a giant paragraph with an inline attachment can
therefore dominate layout. Genuinely underlined lines still construct exact
clearance geometry; a link spanning a whole paragraph may touch every line.
Cold preparation and metadata traversal still scale with document length.
UI installation, active Find and final snapshot-release tails remain unprofiled.
