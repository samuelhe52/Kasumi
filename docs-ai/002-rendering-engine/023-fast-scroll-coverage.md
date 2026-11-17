# 002.023 — Idle preparation for rapid scrolling

## Context

The maintainer reproduced blank regions during very fast scrolling of the 200k
mixed sample after `25b5d21`. The prior 80-point/16 ms protocol does not cover that
case. The renderer publishes only measured windows, so an arbitrarily large jump
can outrun finite overscan even when ordinary scrolling is covered.

## Change

Prepare a complete snapshot during idle time for bounded documents, using the
existing immutable measurement cache. Yield the session actor after batches of
eight paragraph indices (tables refine as a unit), cancel on activity, and resume
from retained progress. Hosts start after 200 ms of inactivity. Once ready, publish
only at the same width/content/style and current reading anchor. Preserve the
fast first-screen path and existing image/color behavior.

The resource envelope is at most 1,000 parsed blocks and 250,000 UTF-16 units,
including table cells, with at most 4,000 units per block/cell and 64 cells per
table. Images and diagrams are excluded. Other documents retain viewport
refinement. This policy limits work but is not an absolute memory or latency cap.
Widths invalidate progress; content/style/font/resource changes create a session.

`DocumentReflowSession.prepareForScrolling(width:)` prepares the bounded document
without repeatedly building the semantic map. Once finished, viewport requests
reuse the complete immutable snapshot and its existing layout lock. A later
viewport request must not replace it with partial geometry. Returned snapshots
at other widths remain independent.

## Alternatives and decisions

Increasing a finite overscan window cannot cover arbitrary jumps. Blocking every
scroll callback on a fresh whole-document layout would move the delay onto the
UI thread. Sharing mutable CTLine-bearing snapshots under independent locks
would violate the ownership model. Idle preparation should instead reuse pure
geometry while returned snapshots keep local Core Text objects.

## Validation criteria

- Add a full-document traversal at 480 points every 8 ms after a fixed three-second
  idle period; retain the previous ordinary-scroll check. Record readiness before
  traversal and inspect a rendered viewport when coverage is missing.
- Check cancellation, width invalidation, geometry/text equivalence and retained
  snapshot ownership with focused library tests.
- Measure both cold first-screen and idle-prepared behavior; do not describe a
  warmed result as an immediate cold-jump guarantee.
- Use only Mac runtime checks and generic iOS device-SDK compilation. No simulator.

## Validation and measured outcome

The plan above preceded implementation. Validation uses macOS Release builds;
no simulator or physical-device runtime check was used.

- Focused viewport/reflow/reader-state tests: 33 passed. They cover complete-snapshot
  reuse, retained output, cancellation, in-flight width invalidation, resource
  exclusions, and text/geometry/pixel equivalence with an independent full render.
- Three warm stress runs with the original drawing backend each recorded zero
  uncovered samples: 175 at 50k and 695 at 200k. Complete snapshots were ready
  within the fixed three-second idle interval. Preparation plus first viewport
  paint/install took 321–338 ms at 50k and 1,403–1,414 ms at 200k.
- The paired control, using the same binary with idle preparation disabled,
  recorded 107/173 uncovered samples at 50k and 616/688 at 200k. Counts vary with
  asynchronous scheduling; neither those counts nor requested 8 ms steps prove
  display FPS. The first-miss PNG adds diagnostic work to the first gap.
- A separate 900-point-wide 200k engine probe measured 1,344 ms of preparation,
  0.025 ms to reuse the complete snapshot, and 158 MB peak process footprint
  after rendering a middle viewport. A first-viewport-only process peaked at
  21 MB. These are whole-process peaks including fonts/caches, not steady-state
  incremental allocation. Rebuilding another full snapshot after warming took
  about 45 ms in a separate probe; warmup's final full construction also executes
  synchronously on the actor.
- The rendered 200k middle viewport was inspected: prose, quote, table, formulas,
  inline styling and code were present. This is selected-viewport pixel evidence,
  not a frame-by-frame capture of native scrolling.
- The unchanged headless benchmark recorded mixed first-snapshot construction
  of 23/32 ms and parsing of 8/26 ms at 50k/200k; OS/font caches were not reset.
- Full package validation: `make test SWIFT_CONFIGURATION=release`, 246 tests
  passed across 18 suites. Generic iOS device-SDK Release compilation passed
  without signing; no simulator or physical-device runtime was used. Ordinary
  80-point/16 ms scrolling recorded zero misses in 402 samples, and the offscreen
  native smoke check passed.
- A separate AppKit paint investigation found 714-point dirty/paint regions in
  the tested scroll protocol. Restricting the draw region and replacing direct
  AppKit glyph painting with SDR bitmap painting did not improve total traversal
  time. Both experiments were removed; the harness drawing backend is unchanged.
- Earlier prototype runs failed coverage because a later viewport request could
  replace completed geometry with a partial snapshot. The reuse regression test
  now protects that path. Two test attempts were interrupted while Core Text
  waited in font-registry XPC calls; a subsequent focused run passed unchanged.

## Remaining limits

Complete idle preparation adds substantial retained geometry and CPU work. It is
optional and bounded. Cancellation is checked between batches; a single batch or
final snapshot assembly still occupies the session actor until it finishes. An
immediate cold jump, scrolling before readiness, changing width, or a workload
outside the envelope can still outrun viewport refinement. Large individual
blocks remain a tail-latency risk. Mac metadata checks and selected bitmap renders
do not establish UIKit tile presentation or physical display frame rate.

## Refs

`Sources/KasumiMarkdown/DocumentReflowSession.swift`,
`apps/iOS/Kasumi/ReadingSurface.swift`, `tools/ReflowLab/main.swift`,
`Tests/KasumiMarkdownTests/ViewportLayoutTests.swift`,
`Makefile`, and [harness protocol](../../tools/ReflowLab/README.md).

Implemented and validated locally. No frozen reference fixtures
changed. Physical-device scrolling and display-frame validation remain open.
