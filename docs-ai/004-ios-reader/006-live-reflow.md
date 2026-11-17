# 004.006 — Live resize reflow

## Context and intended approach (2026-11-17)

The maintainer requested live text reflow during window resizing and emphasized
performance. The current reader scales its old page and cancels/restarts a full
layout on every width change. Synchronous layout does not observe cancellation
until construction returns, so repeated cancellation can overlap expensive work
and prevent any replacement from being published during a continuous drag.

Keep one background layout/viewport-paint pipeline per reader, with one latest
pending request. Publish completed intermediate widths while newer widths arrive;
discard results for superseded content, typography, or font generations. Keep
glyphs at their original size while waiting, and install width changes without
snapshot crossfades. Retain the existing fade for appearance changes.

Preserve a semantic reading anchor across consecutive reflows rather than
recapturing each new line start, which can accumulate backward drift. Intentional
scrolling and navigation replace that anchor. Remap Find highlights without
scrolling back to the current result on every resize.

## Validation plan

- Deterministic request-state tests: continuous resize makes progress, only one
  request runs, pending widths coalesce, stale generations cannot publish, and
  shutdown cannot install a late result.
- Repeated-width semantic-anchor and text-size checks using existing library
  tests; measure repeated layouts before deciding whether further caching is
  justified.
- Build with Makefile routines. Exercise the already booted iOS simulator with
  `sim-use`, including a resize sequence, scrolled position, and Find. No new
  simulator will be booted without approval.

## Outcome

Implemented on 2026-11-17.

- `apps/iOS/Kasumi/ReaderReflowState.swift` tracks desired, running, and installed
  requests. The request generation covers content, typography, and font changes;
  width-only changes do not invalidate a running pipeline.
- `apps/iOS/Kasumi/ReadingSurface.swift` drains requests serially, typesets and
  prepaints off-main, and publishes intermediate widths. It removes resize
  scaling and crossfades, retains appearance transitions, and freezes the
  semantic anchor until scrolling or navigation changes it. Shutdown rejects
  late publication. `Layout`, `ViewportPaint`, and `Install` signposts provide
  separate profiling intervals.
- `apps/iOS/Kasumi/ReaderFind.swift` remaps results with scrolling suppressed
  during replacement, so a resize does not return to a previously active match.
- `Tests/KasumiMarkdownTests/ReaderReflowState.swift` is a relative symlink to
  the actual app scheduler. This keeps deterministic state tests in the package
  without exposing an app-specific public library API.
- `Makefile` accepts `SWIFT_CONFIGURATION=release` for package checks and now
  honors `CONFIGURATION` for `make app`, as the other app routines already did.

Source editor integration retains this scheduler. Hiding Preview clears pending
work and rejects an in-flight result while allowing that worker to drain. Reopening
queues the latest width/content behind it. Source edits replace content without a
snapshot fade; typography/font changes retain the appearance transition. Find
presentation waits until the preview is active.

## Validation

- Initial focused Debug test compilation failed because Swift Testing's
  expression capture cannot call mutating value methods through an immutable
  captured receiver. Calling those mutations in closures fixed the test syntax;
  the rerun passed all five selected tests.
- `KASUMI_REFLOW_TIMING=1 make test SWIFT_CONFIGURATION=release
  FILTER='ReaderReflowTests|liveReflowRetainsOriginalAnchor|readingAnchorSurvivesWidth'`:
  passed five tests, including both repeated-layout cases. The scheduler cases
  cover coalescing, publication during continued input, exclusive work, generation
  invalidation during layout/painting, returning to the installed width, invalid
  widths, and shutdown. Reflow tests check unchanged semantic text and caret
  height, finite anchor restoration at every width, and exact return to the
  original anchor after resizing back.
- `make app` and final `make app CONFIGURATION=Release`: succeeded. The latter
  built `Release-iphonesimulator` after the Makefile correction. Xcode emitted
  its existing no-AppIntents metadata-extraction warning.
- `git diff --check`: passed. Frozen reference measurements were not changed by
  this work.

### Headless timing

Apple M1 Pro, macOS 27.2.1, optimized Release package. One parsed document and
fixed 16 pt text; warm immutable snapshots at widths 800, 500, 320, 700, 360, 600,
and 440 pt. The first 440 pt snapshot warms fonts and is excluded. These values
measure `RenderedDocument` construction, including its immutable reading/text
indices, but exclude parsing, viewport painting, UIKit installation, and Find.

| Mixed Chinese/English source | Median | Maximum |
| --- | --- | --- |
| 1,936 UTF-8 bytes | 5.69 ms | 7.32 ms |
| 19,216 UTF-8 bytes | 39.63 ms | 54.28 ms |

No new shaping cache was introduced in the initial slice. The initial mixed-text
benchmark above was English-heavy and did not justify concluding that resize
responsiveness was adequate. The maintainer subsequently reported poor Chinese
performance and English lag as well. The scheduling change is implemented; the
responsiveness goal remains unresolved.

### Broader Mac reproduction (2026-11-17)

A separate optimized headless probe linked the Release library without changing
production code. It parses each source once, warms one snapshot, and measures
complete snapshots at 800, 500, 400, 700, and 440 pt, using fixed 16 pt text, no
width cap, and 500-character paragraphs. Sources are measured by visible character
count, not UTF-8 byte size. The language samples have different glyph widths and
line counts. These times still exclude drawing and UI publication.

| Characters | English median / max | Chinese median / max |
| --- | --- | --- |
| 2,000 | 4.16 / 5.10 ms | 22.28 / 37.20 ms |
| 10,000 | 19.74 / 24.85 ms | 111.22 / 186.39 ms |
| 50,000 | 103.28 / 129.44 ms | 528.48 / 914.86 ms |

A Time Profiler recording of repeated complete 5,000-character Chinese paragraph
snapshots attributed approximately 49% of sampled CPU weight to break selection,
27% to attributed-text construction, and 6% to shaping. The break selector
rescans item spans for each active predecessor/candidate pair in
`Sources/KasumiMarkdown/ParagraphEngine.swift`. Chinese attributed construction
calls `addAttributes` per Han character in
`Sources/KasumiMarkdown/Typography.swift`. Both repeat on every width change.
Sampling is approximate, and this paragraph workload differs from the table's
500-character paragraphs.

Needed follow-up: retain width-independent per-block preparation, remove repeated
break-candidate span scans without changing typography, and introduce viewport
measurement with indexed estimated heights. Serializing full-document builds
alone does not make latency independent of document length. No renderer
optimization was applied during that investigation. The subsequent
[renderer follow-up](../002-rendering-engine/013-reflow-preparation.md) implements
retained preparation and incremental break totals; viewport measurement remains
outstanding. No interactive frame-rate claim is established. Local profiling artifacts and external comparison tools
remain outside the repository.

## Deviations and remaining limits

- The maintainer subsequently said simulator verification was unnecessary. It
  stopped at that point and the temporary resize session was ended. Before that,
  the already booted iPhone 18 Pro simulator (iOS 27.2) opened `LinkJumps` at one
  wide resize-mode size; that is not verification of continuous resizing,
  scrolled-anchor retention, or active Find. Two Instruments attachment attempts
  failed with `Cannot find process for provided pid`; no usable trace or UI
  performance conclusion was produced. Local screenshots/logs are not retained
  as repository evidence.
- Layout remains synchronous within its background worker and covers the whole
  document. A newer width can wait for the previous layout and viewport paint;
  the old page stays at native text size and may be clipped until publication.
  Very long or complex documents need incremental layout to improve this bound.
- Scrolling a long distance while viewport prepainting is in flight can move
  beyond the seed rect. The new semantic anchor is respected, but asynchronous
  tiles may briefly draw without a matching preview there; this predates the
  reflow change.
