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
4. Source editor with live preview; side by side on iPad.

## Non-blocking Reader 1 follow-ups

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
