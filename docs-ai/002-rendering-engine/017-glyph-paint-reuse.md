# 002.017 — Reuse source-range glyph paint values

## Context and intended change (2026-11-17)

Viewport-first construction reduces warm 50k-Chinese layout to a few milliseconds,
but first viewport paint still takes about 10 ms. The painter repeatedly reads
Core Text run attributes, resolves fonts/colors, and extracts glyph/position
arrays for source ranges that recur at different widths.

- Retain immutable glyph IDs, natural positions, fonts, colors and leading inset
  per source range within a prepared paragraph. These values are independent of
  engine fragment placement. Apply each snapshot's fragment position at draw time.
- Use a synchronized, cost/count-limited value cache; eviction only loses reuse.
  Cache no CTLine, CTRun or CTTypesetter. Concurrent snapshots keep their own Core
  Text layout objects and existing snapshot locks.
- Enable reuse only for session-prepared measured paragraphs without underline
  decoration candidates.
  Unsupported paint/matrices and attachment delegates keep the original painter.
  Preserve glyph order, compatible-run batching, baseline offsets and text state.
- Keep the uncached path as a parity reference. Check independent snapshots,
  multi-width pixels, mixed fonts/colors/baselines, unsupported paints and PDF
  grouping, then compare construction, paint, disposal and process memory on Mac.
  Do not change frozen expectations or `docs/development.md`; no simulator run.

## Implementation

`FragmentGlyphPaint.swift` holds immutable per-run glyph/position arrays, CTFont
and CGColor assets, and the leading contextual inset. A prepared paragraph lazily
creates its own `NSCache` namespace, keyed by source NSRange. Its count limit is
2,048 entries and cost limit is 256 KiB, with a heuristic array/record cost.
These are eviction hints, not strict allocation caps. Concurrent misses may build
equivalent value records twice; eviction changes reuse rather than output.

Each snapshot's `ParagraphFragmentFactory` still creates its own CTLines and
caret/grapheme records. When materializing a fragment it looks up or extracts
paint values under the owning snapshot lock. The cached values contain no CTLine,
CTRun, CTTypesetter, mutable source attributes or drawing context. The shared
NSCache handles synchronization independently of snapshot locks. The painter
applies current fragment positions and retains its existing adjacent-font/color
batching. Unsupported matrices, paint attributes and run delegates use the
unchanged Core Text fallback, including flush order and text-position handling.

Reuse is enabled for session-prepared measured paragraphs without underline
decoration candidates. Default `RenderedDocument` construction and document-based export keep
the uncached path; RTL/verbatim and unprepared attachments retain their existing
routes. New content, styles or fonts get a new preparation/cache namespace.

## Mac measurement

Baseline `340706e`, Release, Apple M1 Pro/macOS 27.2.1. Same 50k English/Chinese
documents (100 paragraphs of 500 characters), semantic reading anchor, widths
800/500/400/700/440 pt, 800 pt viewport at 2x, and 20 samples per width. Parsing,
cold preparation, bitmap allocation and UIKit installation are excluded. Paint
values warm through repeated reflows, as they do while resizing a document.

Combined medians across widths, milliseconds:

| Language | Construction before → after | First viewport paint before → after | Disposal before → after |
| --- | --- | --- | --- |
| English | 2.05 → 1.79 | 6.33 → 1.09 | 0.16 → 0.10 |
| Chinese | 3.82 → 4.11 | 11.04 → 1.69 | 0.30 → 0.27 |

Chinese paint p95/maximum fell from 18.55/19.22 to 2.54/5.04 ms. Construction
p95/maximum were 6.35/14.16 ms after, versus 6.04/6.46 ms before; no cause for
the construction outlier is established. Process high-water RSS at the Chinese
case was 148.92 MiB before and 148.98 MiB after. This includes earlier English
samples, font/runner caches, bitmap contexts and overlapping snapshots; it is
not an allocation attribution or a native frame-time measurement.

A separate 20-fresh-session Chinese probe kept width 500, viewport 800, scale 2,
and the same source anchor. Fonts/rasterization were warmed; each session's
paint-value cache started empty. Painting an uncached eager reference snapshot
took 10.35 ms median. First use of a lazy viewport snapshot took 7.55 ms median
(8.32 ms p95, 16.16 ms maximum); a new snapshot reusing values took 1.47 ms
median (1.74 ms p95). Layout/preparation are excluded. The reference's fragments
were already materialized, whereas the lazy first paint includes materialization;
these numbers do not isolate a single extraction/rasterization cost.

## Validation and limits

- The focused paragraph-drawing, reflow and viewport run passed 21 tests across
  three suites. Added checks prove value-record reuse with separate CTLine
  ownership, cached/uncached pixel equality across widths and mixed font/color/
  baseline/emoji content, unsupported-stroke fallback, and concurrent independent
  snapshots compared with fresh uncached layouts.
- The broader Release selection passed 69 tests across 11 suites, including
  reader scheduling/anchors, viewport boundaries, paragraph reference geometry,
  interaction/public API, table/underline painting and file exports. The opt-in
  timing test ran separately for the measurements above. Frozen expectations
  remain unchanged.
- The Release app build passed. No simulator or device execution.
- Cache misses and newly encountered source ranges still pay extraction cost.
  Fragment CTLine/grapheme construction remains snapshot-local. Decoration and
  attachment coverage, active Find, installation, and final UI release tails
  remain separate work; native smoothness has not been measured.


## Follow-up

[Paint-only reuse](020-paint-without-caret-materialization.md) lets warm immutable
value hits draw without constructing snapshot-local fragment CTLines or caret
records. Bounded natural caret geometry also stays reusable. Snapshot-local
CTLines remain independently built for misses, unsupported or long fragments,
non-grapheme UTF-16 offsets, and explicit layout-object access. The measurements above describe the
original implementation, before that follow-up.
