# Roadmap

Living list of what comes next, in order. Update it when work starts, finishes,
or is reordered; record the work itself in a numbered entry.

## Reader milestones

1. Document app shell and reading view —
   [004](004-ios-reader/000-plan.md), completed; closed by maintainer decision
   on 2026-11-16. See [closure](004-ios-reader/001-action.md#milestone-closure-2026-11-16).
2. Selection through UIKit text interaction, find bar with match navigation,
   links — [007](007-reader-interactions/000-plan.md), closed 2026-11-16 by
   maintainer decision; implemented with the validation limits noted below.
   Native selection handles, Copy/Select All, find highlights and wrapping match
   navigation, external-link confirmation, and opening-failure feedback are in
   place. [System Find](007-reader-interactions/002-system-find-navigator.md) now
   floats above the keyboard with page content continuing behind its controls.
   Internal headings and footnotes retain animated jumps unless Reduce
   Motion is enabled. Text-link indicators use muted solid lines for heading/web
   links and dashed lines for file/other links; footnote numbers stay unmarked.
   Ordinary attributed underlines share the same glyph-clearance renderer, with
   gaps around descenders. See [link decoration](002-rendering-engine/003-link-decoration.md)
   and [glyph clearance](002-rendering-engine/004-underline-clearance.md).
   See the [validation limits](007-reader-interactions/001-action.md#open-questions).
3. Export: PDF, long PNG, long JPG, print, share sheet —
   [008](008-reader-export/000-plan.md), closed 2026-11-17 by maintainer
   decision; file-backed export, paper/margin/font and image size/quality controls and cancellation. See
   [validation limits](008-reader-export/001-action.md#open-questions).
4. Source editor with live preview —
   [009](009-source-editor/000-plan.md), implemented 2026-11-17. Writable document sessions,
   encoding-preserving source edits, coalesced document undo/redo and
   Source/Preview switching are implemented. All window sizes use the toggle;
   the iPad side-by-side requirement was removed by maintainer decision on 2026-11-18.
   Validation uses only the iPhone simulator.
   See [validation limits](009-source-editor/001-action.md#open-questions).

## Non-blocking Reader 1 follow-ups

[Preset spacing](004-ios-reader/008-preset-spacing.md) adds live editing in
Appearance and carries the active preset's spacing through export and print.

Live window-resize reflow was implemented on 2026-11-17 with one background
layout/viewport-paint pipeline and coalesced pending widths. See
[004.006](004-ios-reader/006-live-reflow.md) for validation and performance limits.
[Anchor lifecycle corrections](004-ios-reader/007-reflow-anchor-lifecycle.md)
refresh paragraph keys after content revisions and track explicit clamped scrolling.
Mac reproduction confirms that whole-document reflow still stalls on longer
English and especially Chinese text. [Retained preparation and incremental
break totals](002-rendering-engine/013-reflow-preparation.md) now reduce repeated
work in the reader. [Semantic/item preparation and decoration filtering](002-rendering-engine/014-reflow-metadata.md)
remove more repeated width-independent work. [Lazy fragments](002-rendering-engine/015-lazy-fragments.md)
now defer offscreen drawing/caret objects in session-prepared paragraphs; underline
construction materializes the lines that need decoration geometry.
[Viewport-first layout](002-rendering-engine/016-viewport-layout.md) now measures
text paragraphs around the reading anchor with overscan, retaining indexed
offscreen height estimates. Scrolling requests refined immutable snapshots.
[Incremental reflow](002-rendering-engine/022-incremental-reflow.md) now defers
eligible offscreen text, tables and formulas using semantic placeholders. Nearby
tables refine as a unit. Image geometry and diagram fallbacks remain exact. Immutable paragraph geometry and table widths are reused, while Core Text
objects remain snapshot-local. Publication checks current viewport coverage when
the anchor moves, and one screen of overscan buffers scrolling. Cold preparation
also avoids redundant parsing and document-wide grapheme indexing. [Idle preparation](002-rendering-engine/023-fast-scroll-coverage.md) now completes
bounded text/table/math documents after 200 ms of inactivity. Both reader hosts
cancel on activity and retain progress; complete snapshots are reused at the
same width. This covers jumps beyond overscan once preparation finishes, with
additional retained geometry and memory. [Compact preparation](002-rendering-engine/024-compact-idle-preparation.md)
projects fragment wrappers from shared immutable geometry, releases reusable break
items after measurement, and skips unused text assembly in idle batches. A shared
session glyph-cache allowance and one fallback fragment per line also bound paint
retention as more of the document is visited. The shared-cache-only prototype
regressed return painting; line-local immutable paint retention and compact
records now recover it in the measured workloads. First-traversal p99 remains
0.6–2.2 ms higher, and the native Mac process peaks near 229 MB despite a roughly
140 MB engine-only peak. Further work targets those costs and device validation. Measurements use the [reader benchmark suite](../benchmarks/reader/README.md). Shape input remains available for
width changes, but break items may need rebuilding. Documents outside the resource envelope,
and immediate jumps before readiness, still use viewport refinement. A very large
visible table, resource-heavy block or individual paragraph can still dominate.
See the earlier [mixed coverage](002-rendering-engine/018-mixed-viewport-coverage.md)
record for the preceding exact-attachment policy.
[Reader reflow on iOS](004-ios-reader/009-scroll-momentum.md) now preserves
native deceleration when a refined snapshot restores the reading anchor.
[Glyph paint reuse](002-rendering-engine/017-glyph-paint-reuse.md) now shares
immutable source-range paint values across widths, reducing repeated extraction
while keeping Core Text objects snapshot-local. [Paint-only cache hits](002-rendering-engine/020-paint-without-caret-materialization.md)
also skip fragment CTLine construction and reuse bounded natural caret geometry
for interaction; cold, long-fragment and unsupported paint retain the existing path. [Selection lookup](002-rendering-engine/019-selection-range-indexing.md)
now seeks into overlapping source intervals when Find requests highlight geometry.
[Reader Find matching](007-reader-interactions/003-retained-find-matches.md) now
retains semantic offsets and word boundaries across unchanged text, recreating
positions for each snapshot. [Viewport highlights](007-reader-interactions/004-viewport-find-highlights.md)
now use a conservative visible text envelope and numeric match index to skip
distant results, with overscan for scrolling. Remaining work targets native
prepainting, indexed block placement, resource-heavy lazy coverage, UI installation
and snapshot-release tails;
a giant individual match can still request broad selection geometry.

Retained after milestone closure; not prerequisites for starting Reader 2:

- Saved-import open questions in [004.002](004-ios-reader/002-saved-imports.md#open-questions).
- Intermittent blank iPad open in [004.003](004-ios-reader/003-ipad-inspector.md#open-questions).

## Library

- Reader code-block syntax highlighting with Syntect — closed 2026-11-18;
  [002.006](002-rendering-engine/006-syntax-highlighting.md). Rounded panels,
  language captions, and Copy controls are implemented;
  [002.007](002-rendering-engine/007-code-block-presentation.md). Rendering-style
  configuration and reader/control separation are implemented;
  [002.008](002-rendering-engine/008-code-block-style-boundary.md). Enabled PDF
  captions repeat on continuation pages;
  [002.010](002-rendering-engine/010-pdf-code-continuations.md).
  [One-pass span delivery](002-rendering-engine/025-one-pass-syntax-spans.md)
  removes duplicate tokenization. First-use grammar setup remains a cold parsing
  cost.

- Ready-made UIKit/AppKit views and SwiftUI wrappers, extracted from the reader
  once its views settle ([003](003-public-rendering-api/000-plan.md)).
- Distributable XCFrameworks — workflow implemented and tested in a temporary
  repository; [010](010-binary-distribution/001-action.md). A production release
  remains to be published.
- Bundle license notices into the app — closed 2026-11-18. The notices under
  `Sources/KasumiMarkdown/Bundled/Notices/` ship with the app, and the launch
  screen offers Open Source Licenses.
- Explicit profile/CLI hyphenation language selection — closed 2026-11-18;
  [002.009](002-rendering-engine/009-hyphenation-and-defaults.md). Mixed-case words
  retain Liang pattern matching; math subscripts remain font-driven.
- Cached automatic hyphenation-language selection — closed 2026-11-18;
  front-matter `lang`, bounded prose stopword vote, then US English. Opt-in
  punctuation folding and 1/8-em spacing are implemented for library/CLI clients;
  [002.012](002-rendering-engine/012-language-and-punctuation.md).
- Standard TOML profile files — closed 2026-11-18, library/CLI only;
  [002.011](002-rendering-engine/011-standard-toml-profiles.md). No legacy profile
  compatibility or new reader settings.
- Custom JSON theme-pair files — closed 2026-11-18, library/CLI only;
  [003.002](003-public-rendering-api/002-theme-files.md) and
  [003.003](003-public-rendering-api/003-theme-palette-fields.md).
  Reader import UI is deferred.
- PDF link annotations and diagram interactions shipped on 2026-11-18.
  See [002.026](002-rendering-engine/026-pdf-links.md) and
  [002.027](002-rendering-engine/027-diagram-interactions.md).
- The missing-glyph fallback uses a hollow square as of 2026-11-18.
  See [002.028](002-rendering-engine/028-missing-glyphs.md).
- Basic README HTML, inline subscript and superscript, and SVG images share the
  native rendering path for the reader and exports. See [002.029](002-rendering-engine/029-html-and-svg.md).
- Reader layout reserves image geometry from source dimensions. The iOS reader
  decodes fitted raster and SVG pixels as images enter the viewport. See
  [002.030](002-rendering-engine/030-reader-svg-raster-size.md) and
  [002.031](002-rendering-engine/031-viewport-image-decoding.md).
- The Mac harness prepares complete idle geometry for bounded local image
  documents. iOS validation uses a launch switch pending physical-device
  measurements. See [002.032](002-rendering-engine/032-idle-layout-for-local-images.md).
- Known limitations: [renderer gaps](002-rendering-engine/renderer-gaps.md).
  Ligature-span and Han combining-mark width repairs shipped on 2026-11-16;
  see [002.002](002-rendering-engine/002-shaped-cluster-integrity.md).
  Content-aware table columns and independent horizontal reader scrolling were
  implemented on 2026-11-17. Compact tables are centered within the reading
  measure; overflowing tables remain left-aligned. See [002.005](002-rendering-engine/005-table-layout.md)
  for headless validation and the remaining interactive verification limits.
