# 002.013 — Reuse glyph and caret values without fragment CTLines

## Context and intended change (2026-11-17)

The native viewport painter still materializes snapshot-local fragment CTLines
and grapheme caret records before using immutable glyph values already retained
by reflow preparation. Those layout objects are unnecessary for a cache-hit draw.
A native Time Profiler sample attributes part of viewport paint to this work;
that attribution is sampled CPU time, not a standalone call-duration measurement.

- Add a non-building lookup for prepared glyph values. Let deferred fragments
  paint cache hits directly using the record's own leading inset and the current
  snapshot's fragment placement.
- Retain bounded immutable source grapheme boundaries, natural width and interior
  caret offsets alongside glyph values. Build at most 64 boundaries per record;
  long fragments keep the previous paint/materialization path. Snapshot-specific
  width scaling remains outside the shared record. Non-grapheme UTF-16 indices
  still use the original CTLine offset query.
- Preserve full snapshot-local materialization on cache misses, unsupported
  paint, long fragments, non-grapheme UTF-16 indices and explicit CTLine access.
  Retain existing cache eviction, glyph order, adjacent-run batching and snapshot locking.
- Keep UIKit's automatic image range. A local renderer probe found standard-range
  rendering faster on text, but it clips wide-gamut and extended colors. Reusing
  renderers was slower in that probe. Neither change belongs in this fast path.
- Validate cached/uncached pixel parity, later interaction geometry and independent
  CTLine ownership, cold misses, unsupported fallback, and concurrent snapshots.
  Compare existing Release reflow timings and native viewport-paint intervals.

## Current state

Implemented in `FragmentGlyphPaint.swift`, `FragmentMaterialization.swift`,
`ShapedLine.swift`, and `ParagraphGlyphDrawing.swift`. No public API or frozen
expectation changes. A non-building cache lookup returns a strongly retained
immutable value. The record also stores the same source grapheme boundaries and
natural CTLine offsets that interaction would otherwise reconstruct. Offset and
hit-testing queries apply the current fragment's width/position to those values.
Missing, unsupported and long-fragment entries retain the existing whole-line
materialization path. Non-grapheme UTF-16 offsets fall back to the original CTLine
query; explicit CTLine access still creates an independent layout object under
the original snapshot lock.

A paint-only variant was rejected after native English substring Find timing
showed installation rising from 1.92 to 2.59 ms median despite slightly lower
paint time. Sharing the bounded natural caret geometry avoids moving that work
to UI installation. The 64-boundary cap limits additional cold-paint Core Text
queries; long fragments retain their existing behavior rather than defer large
caret reconstruction to a later UI operation.

The bounded cache remains an eviction hint. New source ranges still miss, and
independent snapshots continue to create their own Core Text layout objects when
needed, while ordinary cached caret/hit-test queries can stay CTLine-lazy. UIKit
image allocation/rasterization and unsupported/attachment drawing remain
separate costs.

## Validation

The focused Release selection passed 59 tests across eight suites, including
paragraph drawing, reflow, shaping integrity, viewport layout, selection, table
layout, public API and export. Opt-in timing checks were skipped in that run and
executed separately. The final paragraph-drawing selection also passed after
extending the cap test to exactly 64 and 65 boundaries.

The deferred-layout case compares cold/warm pixels with the eager route, verifies
that warm paint and ordinary interaction leave snapshot fragment CTLines unbuilt,
and checks raw UTF-16 offsets and independent CTLine ownership. The cap case
protects bounded preparation and the long-fragment fallback. Existing decoration
checks also exercise cold/warm deferred layouts; concurrent multi-width drawing
remains covered by the reflow test. The Release app build passed.

## Measurements

Apple M1 Pro/macOS 27.2.1, Release, existing 50k-character English/Chinese harness,
100 samples per language over widths 800/500/400/700/440 pt with an 800 pt viewport
at 2x. Preparation/parsing and bitmap allocation are excluded. The previous
snapshot survives layout and paint before release. Separate batches; this is
not a native frame-rate measurement.

| Language | Warm paint median before → after | Snapshot disposal median before → after |
| --- | --- | --- |
| English | 1.276 → 0.725 ms | 0.125 → 0.035 ms |
| Chinese | 1.426 → 0.968 ms | 0.243 → 0.120 ms |

Construction medians were 2.019 → 1.865 ms (English) and 3.617 → 3.585 ms
(Chinese); this change targets paint/interaction, not construction. Process peak
RSS was 109.17 → 108.81 MiB at English and 149.42 → 148.47 MiB at Chinese, including
runner/font caches and earlier samples; these are not allocation attributions.

Native validation used the already booted iPhone 18 Pro/iOS 27.2 simulator,
Release app and 3x display. A 63,524-unit authored mixed Chinese document had
2,800 literal matches. The same 25 paced width requests (480/540/460/520/500 pt,
five cycles, height 874 pt) followed 25 warm-up requests. Time Profiler and
signposts recorded 25 completed pipelines per run.

| Native phase | Median before → after | p95 before → after | Maximum before → after |
| --- | --- | --- | --- |
| Viewport paint | 8.77 → 6.99 ms | 13.17 → 10.94 ms | 18.27 → 11.94 ms |
| Layout | 8.75 → 7.63 ms | 9.65 → 8.66 ms | 19.97 → 30.10 ms |
| UI installation | 2.35 → 2.33 ms | 2.77 → 2.60 ms | 4.08 → 7.64 ms |

The runs were separate batches. Layout and installation outliers remain; these
results establish a measured prepaint reduction on this fixture, not an overall
frame-rate guarantee. Find retained 1/2,800 across the resize sequence, Next moved
to 2/2,800, and long-press selection subsequently displayed the correct Chinese
word with native handles/menu. Screenshots/traces are local and not retained.

An additional 50k-character English fixture had 1,000 literal `ea` matches inside
words. The same 25-width protocol compared the previous painter with the final
glyph/caret cache. The baseline used a temporary diagnostic switch to retain the
previous materialize-before-paint path in an intermediate build. The final app
was rebuilt with bounded caret reuse and without that switch; it is not a runtime
feature. Median/p95/maximum milliseconds:

| English native phase | Before | After |
| --- | --- | --- |
| Viewport paint | 4.58 / 5.82 / 9.43 | 4.12 / 4.95 / 7.25 |
| UI installation | 1.92 / 2.23 / 6.05 | 1.46 / 1.72 / 2.67 |
| Layout | 2.57 / 3.54 / 4.58 | 2.59 / 3.26 / 5.34 |

Find stayed at 1/1,000 through resizing and Next moved to 2/1,000. These are
separate paced batches, not continuous-drag cadence or physical-device evidence.

## Limits

Bounded natural caret geometry avoids first-use reconstruction for ordinary
interior-word highlights. Non-grapheme UTF-16 queries still require snapshot-local
materialization. Cold-cache/image-heavy rendering, physical-device behavior, and
continuous-drag frame cadence remain unverified.
