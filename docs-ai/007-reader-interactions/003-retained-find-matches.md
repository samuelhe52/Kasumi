# 007.003 — Retain semantic Find matches across reflow

## Context and intended change (2026-11-17)

Selection range indexing removed document-wide geometry scans per Find result.
Native profiling still shows repeated matching of unchanged semantic text on the
main actor after each snapshot installation. Retain semantic UTF-16 match offsets
and word boundaries independently of layout; create fresh snapshot-owned text
positions before publishing results.

- Extract the existing Foundation matching loop into proposed
  `apps/iOS/Kasumi/ReaderSearchState.swift`, a reader-owned single-text/single-query
  cache. Keep comparison flags, fixed search locale, word-match rules, result
  ordering and non-overlapping matching unchanged.
- Invalidate on exact UTF-16 text changes, query changes, comparison flags and
  word-match mode. Swift canonical String equality is insufficient: composed and
  decomposed strings can compare equal while their UTF-16 offsets differ.
- Retain word boundaries lazily for the current exact text so query changes do
  not repeat segmentation. Retain no layout object or `TextRange`; each install
  validates offsets and reconstructs positions in the new snapshot's namespace.
- Cover option/text/query invalidation, canonical-equivalent encodings, CJK and
  emoji, shared semantic text with different attachment rendering, and independent
  snapshot position ownership using package tests linked to the actual app helper.
  Compare native resize installation before/after with Find active. No change to
  highlight culling, navigation or source-edit behavior is intended in this slice.

## Baseline evidence

Release, Apple M1 Pro/macOS 27.2.1, iPhone 18 Pro/iOS 27.2 Simulator. An authored
document has 63,524 UTF-16 units, 100 CJK body paragraphs, a heading and a small
formula/table section. Find for `文` reports 2,800 matches. Five requested widths
(480/540/460/520/500 pt, 874 pt high) repeat five times with 150 ms pauses after
each `devicectl` request. This is paced resizing, not a continuous-drag/frame-rate
test. Existing signposts are captured by Time Profiler with high-frequency
sampling and `os_signpost`; attachment/model startup can affect first intervals.

| Phase | Find inactive, median (20 intervals) | Find active, median (15 intervals) |
| --- | --- | --- |
| Layout | 9.51 ms | 7.94 ms |
| ViewportPaint | 11.71 ms | 8.35 ms |
| Install | 1.48 ms | 8.02 ms |

The captured runs contain different counts of completed pipelines; pending widths
coalesce and recording startup affects coverage. Active/inactive viewport anchors
and keyboard state also differ, so layout/paint differences are not an optimization
claim. Install p95/maximum are 5.66/29.52 ms inactive and 8.67/52.16 ms active.
Sampling attributes 61.4 ms to repeated matching and 28.9 ms to highlight painting
under the active run's 15 installations, versus 123.4 ms sampled installation
weight overall. Snapshot deinitialization accounts for 9.7 ms main-thread sampled
weight in that run; this is attribution, not exact per-release latency.

The simulator template warns that one instrument table has no known input source;
the inspected Time Profiler and application signpost tracks contain data. Traces
and request logs are local and not retained in the repository.

## Implementation

`ReaderSearchState` retains one immutable `NSString`, one query/options result and
lazy word start/end sets for that text. Literal `NSString` equality validates text
and query keys; Swift canonical equality would permit offset-changing cache hits,
while iterating Swift string indices adds avoidable validation work. A text change
discards both matches and tokenization. Query/match-option changes discard results
while reusing valid word boundaries. Empty/no-result searches are supported.

`ReaderFindSession` extracts complete semantic text, requests UTF-16 ranges from
this helper, and maps them to new positions in the installed snapshot. It retains
the existing current-index/reset/scroll policy. No `TextRange`, Core Text object
or geometry enters the cache; an attachment and its expanded literal source can
share semantic matching while keeping different rendered maps and position owners.

The helper's test-target symlink points to the actual app source, following the
existing scheduler/formatting pattern. It introduces no public library API or
external test dependency.

## Validation

- Initial package test compilation needed `KasumiMarkdown.TextRange` qualification
  to disambiguate Foundation's type. The corrected focused Release selection
  passed 15 tests across four suites, covering cache invalidation and word reuse,
  canonical-equivalent text/query encodings, CJK tokenizer agreement, UTF-16 emoji
  ranges, attachment-versus-literal maps and independent snapshot positions, plus
  selection lookup, scheduling and public semantic geometry. The final literal-key
  implementation passed the same selection. The Release app build passed.
- iPhone 18 Pro/iOS 27.2 Simulator: dense Chinese highlights survive repeated
  resizing with `1 of 2,800` retained. Whole Words changes the count to zero;
  toggling it back restores 2,800, and Next advances to `2 of 2,800`. These are
  functional observations, not measured input latency. The final literal-key
  build is exercised separately in the final timing capture.
- Frozen reference data and `docs/development.md` are unchanged by this slice.

## Remaining limits

The first search after content/query changes still runs synchronously, and a first
word-boundary request still segments the complete text. Exact text validation and
position reconstruction still scale with text/match count. Highlight windowing is
now handled by [004](004-viewport-find-highlights.md). Native prepainting remains a
separate measured cost; this change does not virtualize tables/attachments or
establish continuous-drag frame rate.

## Final native measurements

The final literal-key Release build uses the same authored source, theme, query,
five widths and paced request sequence. All 25 captured installations retain
`1 of 2,800`. The recorder's ready notification starts the request driver after
recording is active; the earlier baseline captures have fewer completed pipelines
and first-interval startup outliers. Medians support the matching improvement;
maxima should not be read as a controlled tail-latency comparison.

| Phase | Final median | Final p95 | Final maximum |
| --- | --- | --- | --- |
| Layout | 7.32 ms | 8.99 ms | 9.40 ms |
| ViewportPaint | 7.95 ms | 10.21 ms | 10.60 ms |
| Install | 4.02 ms | 4.34 ms | 4.83 ms |

Active Find's captured installation median changes from 8.02 to 4.02 ms. Layout
and prepainting are unchanged by this implementation; those times provide context,
not a claimed improvement. The remaining highlight/selection path accounted for
about 1.9 ms sampled weight per install in the preceding retained-match capture,
and native prepainting remains near 8 ms. These remain separate targets. Closing
Find and ending Resize Mode returned to the 402 pt main display.
