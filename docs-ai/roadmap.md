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
   decision; file-backed export, image size/quality controls and cancellation. See
   [validation limits](008-reader-export/001-action.md#open-questions).
4. Source editor with live preview; side by side on iPad —
   [009](009-source-editor/000-plan.md), implemented 2026-11-17. Writable document sessions,
   encoding-preserving source edits, coalesced document undo/redo and
   Source/Preview switching are implemented. The iPad side-by-side layout is
   deferred until it can be checked on an iPad; see
   [native editor chrome](009-source-editor/003-native-editor-chrome.md).
   Validation uses only the iPhone simulator.
   See [validation limits](009-source-editor/001-action.md#open-questions).

## Non-blocking Reader 1 follow-ups

Live window-resize reflow was implemented on 2026-11-17 with one background
layout/viewport-paint pipeline and coalesced pending widths. See
[004.006](004-ios-reader/006-live-reflow.md) for validation and performance limits.
[Anchor lifecycle corrections](004-ios-reader/007-reflow-anchor-lifecycle.md)
refresh paragraph keys after content revisions and track explicit clamped scrolling.
Mac reproduction confirms that whole-document reflow still stalls on longer
English and especially Chinese text. [Retained preparation and incremental
break totals](002-rendering-engine/006-reflow-preparation.md) now reduce repeated
work in the reader. [Semantic/item preparation and decoration filtering](002-rendering-engine/007-reflow-metadata.md)
remove more repeated width-independent work. [Lazy fragments](002-rendering-engine/008-lazy-fragments.md)
now defer offscreen drawing/caret objects in session-prepared paragraphs; underline
construction materializes the lines that need decoration geometry.
[Viewport-first layout](002-rendering-engine/009-viewport-layout.md) now measures
text paragraphs around the reading anchor with overscan, retaining indexed
offscreen height estimates. Scrolling requests refined immutable snapshots.
[Incremental reflow](002-rendering-engine/015-incremental-reflow.md) now defers
eligible offscreen text, tables and formulas using semantic placeholders. Nearby
tables refine as a unit; resource-dependent images and diagram fallbacks remain
exact. Immutable paragraph geometry and table widths are reused, while Core Text
objects remain snapshot-local. Publication checks current viewport coverage when
the anchor moves, and one screen of overscan buffers scrolling. Cold preparation
also avoids redundant parsing and document-wide grapheme indexing. A very large
visible table, resource-heavy block or individual paragraph can still dominate.
See the earlier [mixed coverage](002-rendering-engine/011-mixed-viewport-coverage.md)
record for the preceding exact-attachment policy.
[Glyph paint reuse](002-rendering-engine/010-glyph-paint-reuse.md) now shares
immutable source-range paint values across widths, reducing repeated extraction
while keeping Core Text objects snapshot-local. [Paint-only cache hits](002-rendering-engine/013-paint-without-caret-materialization.md)
also skip fragment CTLine construction and reuse bounded natural caret geometry
for interaction; cold, long-fragment and unsupported paint retain the existing path. [Selection lookup](002-rendering-engine/012-selection-range-indexing.md)
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
- Cold share-sheet copies remaining in `Inbox` in [004.005](004-ios-reader/005-warm-file-handoff.md#open-questions).

## Library

- Ready-made UIKit/AppKit views and SwiftUI wrappers, extracted from the reader
  once its views settle ([003](003-public-rendering-api/000-plan.md)).
- Distributable XCFrameworks so clients can depend on the repository by URL.
- Bundle license notices into the app.
- Standard TOML profile files.
- Known limitations: [renderer gaps](002-rendering-engine/renderer-gaps.md).
  Ligature-span and Han combining-mark width repairs shipped on 2026-11-16;
  see [002.002](002-rendering-engine/002-shaped-cluster-integrity.md).
  Content-aware table columns and independent horizontal reader scrolling were
  implemented on 2026-11-17. Compact tables are centered within the reading
  measure; overflowing tables remain left-aligned. See [002.005](002-rendering-engine/005-table-layout.md)
  for headless validation and the remaining interactive verification limits.
