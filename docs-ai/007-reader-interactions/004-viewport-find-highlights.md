# 007.004 — Build Find highlights around the viewport

## Context and intended change (2026-11-17)

Retained matching reduces native installation work, but the reader still builds
highlight geometry and paths for every result, including distant estimated text.
The preceding trace attributes about 1.9 ms sampled weight per installation to
this path with 2,800 Chinese matches. Horizontal table pans repeat the same work.

- Add a conservative `RenderedDocument.textRange(intersectingVerticalRange:)`
  query using the existing Y-sorted reading index. It returns a snapshot-owned
  semantic envelope without materializing glyphs. Include every horizontally
  overlapping table cell; expand any touched attachment replacement to its full
  semantic text. Estimates conservatively contribute their whole paragraph.
- Build a reader-owned numeric index of ordered, non-overlapping Find offsets.
  Binary-search results intersecting the envelope and request exact geometry only
  for those candidates. Preserve original result indices for the current match.
  Validate ownership when installing results and querying a new snapshot.
- Keep a viewport window with vertical overscan. Refresh paths when scrolling
  leaves that window, when matches/current index change, or when table offsets
  change. Reflow/navigation/programmatic scrolling must update the window too.
  Ordinary text-selection geometry and Find navigation remain complete.
- Compare bounded highlight rectangles with exhaustive results around tables,
  attachment fallbacks, measured/estimated boundaries, repeated widths and scrolling.
  Verify source ranges and foreign snapshots independently, run narrow Makefile
  checks, and measure native installation with the existing 2,800-match corpus.

One envelope may include extra candidates between disjoint table-cell ranges.
This conservative choice keeps the public query small and avoids a second layout
index or a viewport-specific position namespace. A very long individual match
can still request geometry outside the window; final paths exclude off-window
rectangles, but this slice does not change selection geometry's public contract.

## Implementation

The reading index retains each paragraph's global storage offset and reuses its
existing Y-sorted lines/prefix bottoms to locate a vertical window. A one-point
conservative margin accounts for minimum-height selection rectangles. Touched
source ranges form one envelope; `DocumentTextMap.semanticRange(forRenderedRange:)`
expands partial replacement storage to the complete semantic value, including
wrapped missing-image descriptions. The public query clips the result to the
document's semantic end and does not materialize deferred fragments.

`ReaderHighlightIndex` validates snapshot ownership and ordered, non-overlapping
results once, retaining numeric offsets and a position token, not a layout. Two
binary searches select original result indices intersecting the envelope. The
page computes geometry only for those candidates and excludes rectangles outside
the window after mapping/clipping horizontal table offsets.

The page keeps a window with half a viewport of overscan on each side (at least
128 pt). Ordinary scrolling reuses the paths until it leaves that window. Layout,
explicit/programmatic scrolling and navigation update it; table pans repaint
using their current horizontal offsets. Same-width snapshot refinement clears
the old window/index before replacing geometry, then installs new owned matches.
Find counts/navigation and ordinary text-input selection remain complete.

## Validation

- The focused Release selection passed 33 tests across six suites: new exhaustive
  bounded-versus-all highlight comparisons, reverse semantic-range mapping,
  namespace checks, existing viewport/selection/search/reflow/public API cases.
  The opt-in timing test passed separately. Release app builds passed.
- Full and viewport layouts at 260/520 pt compare exact highlight rectangles and
  original indices across source windows, table columns at both horizontal ends,
  formulas, emoji, RTL and long wrapped unavailable-image descriptions. Metadata
  queries leave fragment materialization unchanged. Empty/nonfinite/outside
  windows, foreign snapshots and unordered match input are checked.
- iPhone 18 Pro/iOS 27.2 Simulator: dense Chinese highlights remain visible after
  three upward flicks into later paragraphs and viewport refinement. Table Find
  highlights stay aligned through panning in both directions; the original
  current-result index remains intact. Resizing retains `1 of 2,800`; Next moves
  to `2 of 2,800`. Closing Find returns to the reader. Native text-selection
  gestures were not rechecked in this slice; their geometry path is unchanged.
- Frozen reference measurements and `docs/development.md` remain unchanged.

## Measurements

### Headless geometry

Apple M1 Pro/macOS 27.2.1, Release. An authored Chinese body contains 1,000
paragraphs of 50 characters and 3,000 matches for `文`. A 1,600 pt middle window
includes overscan. Full/viewport layouts are built once; geometry is warmed before
30 repetitions. Both approaches filter to identical visible rectangles. Times
exclude layout, matching, UIKit path construction, painting and disposal.

Median milliseconds:

| Snapshot | Width | Candidates | Index build | All-result geometry/filtering | Bounded geometry/filtering |
| --- | --- | --- | --- | --- | --- |
| Full | 400 | 51 / 3,000 | 0.037 | 4.807 | 0.091 |
| Viewport | 400 | 51 / 3,000 | 0.028 | 1.146 | 0.077 |
| Full | 500 | 74 / 3,000 | 0.035 | 5.297 | 0.139 |
| Viewport | 500 | 74 / 3,000 | 0.030 | 1.203 | 0.129 |

The actual app helper is linked into the test target. Run the authored corpus with
`KASUMI_HIGHLIGHT_TIMING=1 make test SWIFT_CONFIGURATION=release FILTER=macHighlightTimings`.

### Native paced resize

Baseline `bb6fae1`, using the final retained-match capture described in
[003](003-retained-find-matches.md#final-native-measurements). The same 63,524-unit
authored document, 2,800-match query, five widths, 874 pt height, recorder-ready
notification and 25 paced requests are used here. Each capture contains 25
completed pipelines. Time Profiler/signpost settings and simulator hardware/OS
match the previous slice. Logs/screenshots/traces are local and not retained.

| Phase | Baseline median | Current median | Current p95 | Current maximum |
| --- | --- | --- | --- | --- |
| Layout | 7.32 ms | 8.75 ms | 9.65 ms | 19.97 ms |
| ViewportPaint | 7.95 ms | 8.77 ms | 13.17 ms | 18.27 ms |
| Install | 4.02 ms | 2.35 ms | 2.77 ms | 4.08 ms |

The main-thread installation median improves in this capture. Layout/prepainting
medians are higher, so these separate paced runs do not establish an end-to-end
or continuous-drag frame-rate improvement. This slice changes highlight work;
native prepainting remains a significant separate cost. Sampling attributes
3.7 ms total to highlight painting under the 25 installations, compared with
47.9 ms in the preceding retained-match capture; this is sampled attribution,
not exact per-call latency. Find was closed and Resize Mode ended at the finish,
returning the reader to the 402 pt main display.

## Remaining limits

Conservative envelopes can include extra table candidates or whole estimated
paragraphs. A huge individual match still requests all of its selection geometry
before path filtering. All result positions and the numeric index are rebuilt on
snapshot replacement. Native prepainting, table/attachment virtualization, cold
preparation and final-release tails remain separate optimization targets.
