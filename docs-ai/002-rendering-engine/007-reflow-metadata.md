# 002.007 — Reuse reflow metadata and skip absent decorations

## Context and intended change (2026-11-17)

After `a3bdfb9`, warm resize still reconstructs semantic maps, anchor hashes,
grapheme boundaries and paragraph items, and scans every line for decorations
on plain paragraphs. This follow-up implements the next exact optimization slice.

- Record conservative decoration candidates once in paragraph preparation. Keep
  the existing decorated path unchanged; skip it only when there are no candidates.
- Retain immutable per-paragraph semantic maps/anchor keys and document semantic
  text/boundaries across widths. Validate the document map against all placed
  paragraph maps, including rebuilt image/math paragraphs, before reusing it.
  Rebuild width-dependent line geometry and keep Core Text objects snapshot-local.
- Retain the engine's width-independent items, total/code advances and initial
  diagnostics, keyed by indent and paragraph options. Run exact width-dependent
  break selection and emission on every layout. Preserve validation and Float order.
- Extend the opt-in Mac timing harness to measure construction, old-snapshot
  disposal and viewport drawing separately with at least 20 samples per width.
  Record process high-water RSS with two snapshots alive; it is not object-level
  allocation attribution. Capture a same-harness baseline before renderer edits.

## Validation plan

Extend existing reflow checks for semantic offset/anchor equivalence, cached maps,
option/indent invalidation, and decoration parity. Run frozen paragraph, reading,
underline, interaction, table and public API filters. Compare before/after Release
measurements on English and Chinese 10k/50k documents and compile the app. No
simulator run, viewport-height redesign, lazy Core Text storage or changes to
`docs/development.md` in this slice.

## Outcome

Implemented on 2026-11-17.

- `Sources/KasumiMarkdown/DocumentReflowSession.swift` now retains decoration
  candidate flags, semantic content and prepared paragraph items. Item entries
  validate indent and all paragraph options; only one variant per paragraph is
  retained. Width-dependent DP nodes, break results and geometry remain fresh.
- `Sources/KasumiMarkdown/ReflowSemanticContent.swift` owns immutable paragraph
  text maps/reading keys and document semantic text/grapheme boundaries. It owns
  no Core Text layout objects. `ReadingPosition.swift` reuses paragraph metadata;
  `RenderedDocument.swift` reuses document text/boundaries while rebuilding lines.
- `DocumentLayout.swift` validates cached document content against the complete
  ordered paragraph maps. Equal text or equal rendered length alone is insufficient:
  loading an attachment or moving a replacement can change the offset mapping.
  Image/math preparation still rebuilds; their maps participate in this check.
- `TextUnderline.swift` conservatively detects explicit underlines or link
  candidates during preparation. Candidate paragraphs run the existing decoration
  geometry path unchanged. Plain paragraphs avoid per-line attribute enumeration.
- `ParagraphEngine.swift` separates validated width-independent item construction
  from width-dependent break selection. Original Float sums, diagnostics and
  fragment emission are retained; no frozen measurements were changed.
- `Tests/KasumiMarkdownTests/DocumentReflowTests.swift` extends the existing tests
  and opt-in Mac benchmark. No changes to `docs/development.md` or app UI code.

## Validation

- The first focused Release run passed 21 tests, including frozen geometry,
  reading anchors, underline clearance and cached/fresh snapshot checks.
- A broader new-test run failed four nonempty-decoration assertions: raw link
  attributes in the test lacked the renderer's inline link-run flags. The cached
  and forced-decoration geometry already agreed. Constructing the test runs through
  ordinary typography fixed the fixture; the rerun reported 62 tests passing
  across eight suites (the opt-in timing test was skipped). Filters:
  `ParagraphEngineTests|DocumentReflowTests|ReaderReflowTests|reading|ReadingPosition|LinkUnderlineTests|UnderlineClearanceTests|PublicAPITests|TableLayoutTests|paragraph|ShapedClusterIntegrityTests|punctuation|documentFont|bundledDocument`.
- New assertions check document metadata reuse, cache invalidation when attachment
  offsets change despite identical text, option/indent invalidation, non-sticky
  diagnostics across widths, and forced-versus-filtered decoration geometry for
  native/Core Text underlines and web/internal links. Existing pixel, selection,
  glyph, font, table, public API and all 782 frozen paragraph cases passed.
- After adding the same-text/same-rendered-length replacement-map case, the
  final `make test SWIFT_CONFIGURATION=release FILTER=DocumentReflowTests` run
  reported six tests passing (timing skipped), including that extension.
- `make app CONFIGURATION=Release`: succeeded with the existing no-AppIntents
  metadata-extraction warning. Compilation only; no simulator or device run.
- `git diff --check`: passed; reference fixtures and `docs/development.md` unchanged.

## Mac measurement

Apple M1 Pro, macOS 27.2.1, optimized Release, fixed 16 pt text and no width cap.
The same 500-character paragraphs and widths (800, 500, 400, 700, 440 pt) are used
before and after. There are 20 samples per width, cycling through widths, for
100 samples per language/size. The baseline uses `a3bdfb9` renderer code with the
new harness before the renderer edits. Parsing, cold preparation, fixture setup
and bitmap allocation are excluded. The initial snapshot and glyph rasterization
are warmed before timing. The previous snapshot stays alive during construction
and a 2x middle-of-document 800 pt viewport draw, then is explicitly released.
Construction, drawing and old-snapshot disposal have separate timers.

Command: `KASUMI_REFLOW_TIMING=1 make test SWIFT_CONFIGURATION=release
FILTER=macReflowTimings`. `KASUMI_REFLOW_SAMPLES` can increase repetitions;
`KASUMI_REFLOW_LANGUAGE=English|Chinese` and `KASUMI_REFLOW_CHARACTERS=10000|50000`
select a workload. No wall-clock thresholds are asserted.

Combined medians across all five widths, in milliseconds:

| Characters / language | Construction before → after repeat | Disposal before → after repeat | Viewport draw before → after repeat |
| --- | --- | --- | --- |
| 10k English | 11.69 → 7.44 | 0.73 → 0.72 | 5.54 → 5.77 |
| 10k Chinese | 25.48 → 18.34 | 2.32 → 2.42 | 9.59 → 9.90 |
| 50k English | 55.37 → 36.65 | 3.46 → 3.57 | 5.45 → 5.98 |
| 50k Chinese | 133.18 → 95.05 | 11.90 → 12.28 | 10.14 → 10.86 |

Construction p95 before → after repeat: 12.37 → 8.25 ms, 30.37 → 24.07 ms,
59.02 → 41.20 ms and 159.78 → 133.62 ms respectively. The first post-change run's
construction medians were 7.49, 19.52, 37.61 and 97.12 ms. Construction improves
in both runs; there is no measured disposal or draw improvement. Tail spikes
remain: 50k English construction maximum was 59.90 ms before, 73.31 ms after,
and 85.38 ms on repeat; repeat viewport draw also had a 36.42 ms outlier. No
cause or tail-latency guarantee is established.

The macOS process high-water RSS at the largest Chinese case was 254.56 MiB
before and 262.14 / 260.09 MiB in the after/repeat runs. It includes the test
runner, persistent caches, five bitmap contexts, prior workloads, and overlap
between two snapshots. It is cumulative process RSS, not allocation attribution
or an on-device memory budget. Retaining items consumes memory, but these values
do not isolate its cost.

A fresh Time Profiler trace of repeated complete 50k Chinese document construction
(100 paragraphs, 500 characters each) sampled no decoration-layout hotspot;
item preparation and semantic construction appeared only in startup samples.
Break selection and fragment construction remain dominant. This is a headless
construction trace, separate from the timings above; local trace/probe artifacts
are not repository dependencies.

## Remaining work

Full paragraph breaking, eager fragment Core Text objects, document geometry and
painting still scale with document size. The headless disposal measurements do
not establish which UI owner performs the final release. Lazy fragment storage,
viewport-height estimation, active Find work and explicit retirement ownership
remain separate follow-ups. No interactive frame-rate or on-device smoothness
claim is established.

The following slice implements [lazy fragment materialization](008-lazy-fragments.md).
