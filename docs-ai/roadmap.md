# Roadmap

Living list of what comes next, in order. Update it when work starts, finishes,
or is reordered; record the work itself in a numbered entry.

## Reader milestones

1. Document app shell and reading view —
   [004](004-ios-reader/000-plan.md), completed; closed by maintainer decision
   on 2026-11-16. See [closure](004-ios-reader/001-action.md#milestone-closure-2026-11-16).
2. Selection through UIKit text interaction, find bar with match navigation,
   links — current focus. Remaining UIKit work: text-selection handles, the
   edit menu with Copy, a find bar, and opening external links with confirmation.
   The library APIs already exist: `position(closestTo:)`, `selectionRects`,
   `ranges(matching:)`, and `link(at:)`.
3. Export: PDF, long PNG, print, share sheet.
4. Source editor with live preview; side by side on iPad.
5. Settings: font store and download screen
   ([005](005-cjk-font-availability/000-plan.md)), default preset, theme, and size.

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
