# 002.015 — Defer offscreen fragment materialization

## Context and intended change (2026-11-17)

After `c5342a5`, exact break selection and fragment Core Text construction remain
hot. Interactive sessions still create drawing/caret CTLines for offscreen text,
then pay to destroy those objects on replacement. This slice changes when those
objects are built while retaining the existing exact line geometry.

- Keep engine fragment descriptors, source ranges, logical CTLines, baselines,
  hyphen widths and paragraph heights eager. Deferred fragments must stay present
  as geometry; an empty fragment list already means the legacy painting path.
- For session-prepared undecorated paragraphs, retain a snapshot-local paragraph
  typesetter and materialize a line's fragment CTLines/insets/grapheme boundaries
  at first drawing or hit-testing access. Cache the materialized line within that
  snapshot; release the factory reference when a line no longer needs it.
- Decorated paragraphs stay eager so underline clearance and construction
  behavior remain exact. Unprepared attachment paragraphs, RTL, verbatim, ordinary
  `RenderedDocument` construction and document-based export keep their current path.
- Audit every public fragment reader: draw, table draw, caret/hit testing, link
  testing, selection and snapshot image export already use `layoutLock`. Lazy
  stores are confined to construction and that same lock after publication;
  typesetters or mutable paint caches must never be shared between snapshots.
- Retain an eager reference path. Validate pixels, glyph origins, carets,
  offscreen interaction, table painting, export and concurrent snapshot queries.
  Instrument fragment counts so parity checks do not conceal eager work.

## Validation plan

Capture a fresh `c5342a5` baseline using the existing 20-samples-per-width Mac
harness before renderer edits. Repeat construction, viewport draw, disposal and
process-RSS measurements, reporting any moved paint cost and tail spikes. Run
focused paragraph, reflow, reading, interaction, table, underline and export/API
checks, plus app compilation. Frozen reference expectations and
`docs/development.md` stay unchanged. No simulator run in this slice.

## Outcome (2026-11-17)

Implemented on `perf/live-text-reflow` on 2026-11-17.

- `Sources/KasumiMarkdown/FragmentMaterialization.swift` owns snapshot-local
  paragraph factories and line stores. The factory performs the same source-backed
  Core Text cuts, glyph-inset correction and grapheme-boundary walk as before.
  A line caches its materialized values at first use and drops its factory/range
  references afterward. No typesetter or mutable store enters session preparation.
- `ShapedLine.swift` separates immutable fragment geometry from eager/deferred
  paint data. Geometry and nonempty fragment lists remain available without
  creating CTLines. `MeasuredParagraphTypesetter.swift` still creates logical
  lines, baseline/height metrics and hyphens eagerly.
- `DocumentLayout.swift` and `Typography.swift` enable deferral only for session-
  prepared paragraphs without decoration candidates. Default construction,
  decorated paragraphs, unprepared attachments, RTL and verbatim paths stay eager.
- `RenderedDocument.swift` serializes materialization with existing Core Text use
  under `layoutLock`. Draw, table draw, hit/caret/link testing, selection and
  snapshot image export take that lock. Immutable anchor/rect/semantic lookups
  need no materialization. Internal fragment statistics read cache state under
  the lock without building it.
- `ParagraphGlyphDrawing.swift` and `UnderlineClearance.swift` fetch one paint
  record per fragment. Drawing and interaction retain the same glyphs, contextual
  inset handling, source offsets and unsupported-paint fallbacks.

## Validation

- The initial focused run passed 32 tests, but parity alone did not prove deferral.
  The first wider build hit a Swift Testing macro/throwing-child-closure inference
  error. Explicit `async throws` and computing throwing pixel calls before the
  assertion resolved the test compilation issue.
- The new materialization assertions then found a missing defer-flag handoff in
  `ParagraphTypesetter`: 75 selected tests reported six issues, all related to
  eagerly populated fragment state. Forwarding the flag with the decoration
  guard corrected the wiring. The next Release run passed all 75 selected tests
  across nine suites (the opt-in timing test skipped). Filters:
  `ParagraphEngineTests|DocumentReflowTests|ReaderReflowTests|reading|ReadingPosition|LinkUnderlineTests|UnderlineClearanceTests|PublicAPITests|TableLayoutTests|paragraph|ShapedClusterIntegrityTests|punctuation|documentFont|bundledDocument|Export|Pagination`.
- `make test SWIFT_CONFIGURATION=release FILTER=ParagraphDrawingTests` separately
  passed five tests covering prior-painter pixels, mixed fonts/baselines/colors,
  decorated fragments, attachment delegates and searchable PDF glyph grouping.
- New reflow tests prove untouched lines stay unbuilt; viewport painting and
  offscreen hit testing materialize only accessed lines; another width receives
  independent stores. They compare eager/deferred pixels and carets across
  concurrent viewport queries, including ligatures, supplementary Han, combining
  marks, curly quotes, emphasis, strikethrough and inline code. Table-local tiles
  at both horizontal edges and decoded snapshot PNG regions match the eager path.
- `make app CONFIGURATION=Release` after final wiring succeeded with the existing
  no-AppIntents metadata-extraction warning. No simulator/device execution.
- `git diff --check` passed. All 782 frozen paragraph expectations and
  `docs/development.md` remain unchanged. No reference tool or binary dependency
  was added.

## Mac measurement

The same Release harness as [014](014-reflow-metadata.md): Apple M1 Pro,
macOS 27.2.1; 500-character paragraphs, fixed 16 pt text, no width cap, widths
800/500/400/700/440 pt, 20 samples per width, 100 per language/size. The baseline
was captured on `c5342a5` before renderer edits. Construction, 2x middle-of-document
800 pt viewport drawing and old-snapshot disposal have separate timers. The old
snapshot survives construction and prepainting. Parsing, cold preparation, bitmap
allocation and UIKit installation are excluded.

Combined medians across widths, milliseconds; after values use the repeat run:

| Characters / language | Construction before → after | Disposal before → after | First viewport draw before → after |
| --- | --- | --- | --- |
| 10k English | 7.59 → 4.16 | 0.74 → 0.22 | 5.81 → 6.97 |
| 10k Chinese | 18.45 → 12.26 | 2.48 → 0.68 | 10.63 → 11.77 |
| 50k English | 36.25 → 18.72 | 3.52 → 0.59 | 5.75 → 6.44 |
| 50k Chinese | 91.65 → 60.08 | 12.03 → 2.64 | 10.60 → 11.79 |

First post-change construction medians were 4.06 / 13.64 / 18.53 / 57.28 ms.
For 50k Chinese, first-paint materialization built 601–1,184 fragments out of
50,000, depending on width, starting from zero at every width. For 50k English,
it built 298–631 out of 13,700. These counters run outside the phase timers, once
per width. Eager reference construction populates every fragment.

The paint increase is a real cost moved to first use. A separate optimized
50k-Chinese probe (100 samples, same widths/viewport) measured 11.84 ms median
for first paint and 10.92 ms for repainting the same viewport. These values do
not isolate materialization from raster/cache warming. Maxima were 26.34 and
49.30 ms; no cause or latency guarantee is established.

Process high-water RSS at the largest Chinese case was 257.02 MiB before and
181.58 / 197.58 MiB after/repeat. These are cumulative macOS process measurements,
including the runner, persistent font/preparation caches, bitmap contexts and
overlapping snapshots, not object allocation attribution or an on-device budget.

Tails remain variable. The baseline's 50k construction maxima were 292.01 ms
English and 504.69 ms Chinese; after/repeat maxima were 26.86 / 24.66 ms English
and 86.93 / 229.12 ms Chinese. Chinese construction p95 was 123.68 ms before and
84.96 / 89.18 ms after/repeat. These local samples do not establish interactive
frame-rate smoothness.

## Remaining limits

- Exact paragraph breaking, logical CTLines and full-document geometry/index
  construction still precede publication. Viewport-first block measurement with
  indexed estimated heights remains the main document-length scaling step; an
  enormous single paragraph still requires whole-paragraph breaking.
- Decorated and unprepared attachment paragraphs remain eager. First-use drawing
  or interaction can build a complete logical line's fragment data under the
  snapshot lock. Full exports or widespread queries may eventually populate all
  lines; the measured disposal/memory gains describe viewport-only access.
- Active Find, UI installation and the identity of the UI's final snapshot owner
  were not profiled here. Headless disposal duration does not establish which
  thread performs the final release in the app.
