# 002.024 — Compact idle preparation and paint retention

## Origin and plan

Planned before implementation, following `9e8633f`. The maintainer requested lower
idle preparation footprint first, then preparation time. A held 200k mixed heap
showed 39.7 MB of break-item arrays, 32.1 MB of expanded fragment arrays, 13.3 MB
of geometry, 8.4 MB of input clusters and 7.7 MB of source-range arrays. The
initial plan was to share pure geometry, project deferred fragment wrappers,
release reusable break items and omit unused text assembly in idle batches.

A full paint traversal then exposed retained paint growth. An initial policy of
one fallback fragment per line plus an 8 MB/8,192-entry session glyph cache reduced
memory, but caused a large return-rendering regression: paint p99 rose from about
3–4 ms to 18–23 ms at 50k/200k. That policy was rejected as the sole paint working
set. Correctness and coverage tests had not detected this performance problem.

Before revising it, the maintainer requested under 200 MB without that regression,
and later accepted the approximately 211 MB peak of the first line-local paint
prototype. The final evaluation therefore prioritizes rendering latency with
roughly 211 MB as an acceptable engine-probe memory target. Native-app memory is
reported separately rather than conflated with the standalone engine.

## Implemented representation and ownership

- `ShapedFragments` projects wrappers from tightly sized immutable geometry.
  Cached geometry shares those value buffers; factories and mutable line stores
  remain snapshot-local. No CTLine/CTRun/CTTypesetter enters shared geometry.
- Optional idle preparation releases break items when exact geometry is reusable,
  retaining shaped clusters/ranges so changed widths can rebuild items. Normal
  sessions that do not request idle preparation retain their previous policy.
- Idle batches omit attributed storage assembly while keeping paragraph-offset
  arithmetic intact. Published full/viewport snapshots retain complete text.
- A first materialization extracts one line as a batch. Line-local arrays retain
  immutable glyph/caret paint values for direct return-paint hits, independently
  of global cache eviction. Only one fallback fragment's native layout is retained
  per line; unsupported paints and long-fragment interaction keep their fallback.
- Single-glyph paint stores captured font, color, glyph and position inline.
  Single-grapheme carets store endpoints without retained boundary/offset arrays.
  Both preserve the actual Core Text output, not substitute font/glyph selection.
- Each snapshot-local paragraph factory shares equal resolved CGColors through a
  palette capped at 16 entries. Different spaces/components/alpha stay distinct;
  no mutable global color state or dynamic platform-color identity is cached.
- The session-wide NSCache still provides cross-snapshot reuse with paragraph UUID
  namespaces and 8 MB/8,192-entry hints. Those hints exclude line-local paint and
  are not a hard process-memory limit. Retained snapshots still consume memory.

## Rejected intermediate choices

The first compact representation reduced preparation-and-one-viewport peak from
about 157 MB to 81 MB, but one forward paint sweep still peaked at 394 MB. Keeping
only one native fragment and depending on the small shared cache lowered the
sweep to about 123 MB, at the cost of repeated paint extraction on return visits.
Line-local paint references restored the 200k return median to 2.66 ms, but used
208 MB settled / 211 MB peak footprint. Its heap contained 202,666 duplicate
CGColors (22.7 MB) plus many one-element glyph/position and two-endpoint arrays.
Inline records, endpoint carets and color sharing remove that overhead without
evicting the useful working set. These plans preceded their implementation.

## Final paint evaluation

Baseline: `9e8633f`. Candidate: current uncommitted implementation. Both final
binaries use standard Release settings. Earlier exploratory candidate runs linked
the testability-enabled Release library and are excluded from the final timing
comparison after that build-setting mismatch was found.

Protocol: complete idle-prepared mixed document, fixed 1179 × 701 points, 18-point
type, new 2× SDR bitmap/context per paint. Step forward by one viewport, then
reverse; create a fresh session after each pair. Paint timing excludes parsing,
preparation and final snapshot disposal. No sample filtering; OS/font caches were
not reset. This is offscreen paint latency, not display FPS or a confidence bound.
20k and 200k have two 1,000-sample runs per phase/version; 50k has one. The repeated
pairs reverse version order. Heights match exactly between versions.

Pooled nearest-rank percentiles, milliseconds:

| Size / phase | Baseline p50 / p95 / p99 | Candidate p50 / p95 / p99 |
| --- | --- | --- |
| 20k first | 12.20 / 13.29 / 13.78 | 13.02 / 14.86 / 15.94 |
| 20k return | 2.36 / 2.79 / 3.05 | 2.36 / 2.91 / 3.11 |
| 50k first | 12.16 / 13.19 / 13.72 | 12.81 / 14.01 / 14.95 |
| 50k return | 2.33 / 2.57 / 2.95 | 2.28 / 2.43 / 2.53 |
| 200k first | 12.40 / 13.78 / 14.47 | 12.72 / 14.22 / 15.12 |
| 200k return | 2.43 / 2.86 / 3.12 | 2.34 / 2.60 / 2.83 |

The large return-rendering regression is resolved in these measurements. First
painting remains modestly slower: p99 increases 2.16/1.23/0.65 ms at 20k/50k/200k.
Do not describe this as zero rendering regression. Maximum observed first/return
paint times were 29.17/7.67 ms at 20k, 20.17/2.93 ms at 50k and 18.47/3.56 ms at
200k in the candidate; maxima are observations, not worst-case bounds. Raw p90,
per-run statistics and individual paint samples remain local.

## Memory and preparation evaluation

Held 200k engine process, 900 × 714 points, one 1× SDR middle viewport followed by
one full forward traversal. `task_vm_info` sampled at 0/5/10/15 seconds idle:

| State | Baseline footprint / RSS | Final footprint / RSS |
| --- | --- | --- |
| Prepared plus one viewport, after 15 s | 149 / 133 MB | 75 / 100 MB |
| Full traversal, after 15 s | 460 / 405 MB | 137 / 162 MB |

The final standard Release process peaked at 139.7 MB charged footprint and
164.9 MB RSS. The prior ~157 MB figure was peak physical footprint, not peak RSS.
RSS and footprint differ with shared/file-backed pages and compression. These
are standalone engine numbers. The whole native Mac fast-check process, including
AppKit/drawing buffers and both 50k/200k cases, peaked at **229.0 MB footprint /
385.5 MB RSS**. It is above 211 MB; the whole-app target is not established by the
lower engine measurements. Production iPhone memory remains unmeasured.

Fresh 900-point-wide preparation probes measured 316 → 293 ms at 50k and
1,336 → 1,275 ms at 200k in the final paired run. This is a single preparation
pair, not a latency distribution. Native idle preparation plus prepaint/install
measured 301/1,247 ms. The headless 1179-point benchmark measured first snapshots
at 20/29 ms and median warm width changes at 6/11 ms for 50k/200k. Parsing measured
8/25 ms separately. Cold means a new session with OS/font caches left intact.

## Validation and remaining limits

- Full Release suite: 248 tests passed in 18 suites. Tests cover independent
  snapshots, width invalidation, exact geometry/text, concurrent rendering,
  cache namespace isolation, deterministic cache eviction with line-local paint
  retention, inline single-glyph representation, equal-color reuse and alpha
  preservation. No frozen reference fixtures changed.
- Fresh baseline/candidate middle-viewport bitmaps match exactly at 50k and 200k.
- Native fast scrolling: zero missed coverage in 177/697 samples at 50k/200k after
  three seconds idle; both documents were fully measured before traversal.
  Ordinary scrolling: zero misses in 402 samples. Native smoke check passed.
- Generic iOS device-SDK Release compilation passed without signing. No simulator
  or physical-device runtime was used. Mac metadata/pixels do not establish
  UIKit tile presentation, physical-display frame rate or iPhone footprint.
- Early Allocations recording needed debug signing; this Xcode version could not
  elaborate its Allocations UI detail through the CLI. Held heap reports supplied
  allocation categories; Time Profiler supplied CPU attribution. Instrumented
  timings were not used for the final latency comparison. External probes remain
  local and are not project build/test dependencies.

The eligibility envelope, first/cold-jump and single-large-block limits from
[023](023-fast-scroll-coverage.md) remain. Width changes may rebuild released
items. The implementation is complete. Remaining performance work is
first-traversal paint overhead and native-app peak memory, rather than restoring
the abandoned cache-eviction policy.

## Key files

`Sources/KasumiMarkdown/ShapedLine.swift`,
`Sources/KasumiMarkdown/FragmentMaterialization.swift`,
`Sources/KasumiMarkdown/FragmentGlyphPaint.swift`,
`Sources/KasumiMarkdown/ParagraphGlyphDrawing.swift`,
`Sources/KasumiMarkdown/ParagraphLayoutGeometry.swift`,
`Sources/KasumiMarkdown/MeasuredParagraphTypesetter.swift`,
`Sources/KasumiMarkdown/DocumentLayout.swift`,
`Sources/KasumiMarkdown/DocumentReflowSession.swift`,
`Tests/KasumiMarkdownTests/DocumentReflowTests.swift`, and
`Tests/KasumiMarkdownTests/ParagraphDrawingTests.swift`.
