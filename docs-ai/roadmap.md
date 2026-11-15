# Roadmap

Living list of what comes next, in order. Update it when work starts, finishes,
or is reordered; record the work itself in a numbered entry.

## Reader milestones

1. Document app shell and reading view —
   [004](004-ios-reader/000-plan.md), in progress. Remaining: the checks listed
   under its Validation and Open questions, and the open questions in
   [004.002](004-ios-reader/002-saved-imports.md), starting with the iPad bar.
2. Selection through UIKit text interaction, find bar with match navigation,
   links.
3. Export: PDF, long PNG, print, share sheet.
4. Source editor with live preview; side by side on iPad.
5. Settings: font store and download screen
   ([005](005-cjk-font-availability/000-plan.md)), default preset, theme, and size.

## Library

- Ready-made UIKit/AppKit views and SwiftUI wrappers, extracted from the reader
  once its views settle ([003](003-public-rendering-api/000-plan.md)).
- Distributable XCFrameworks so clients can depend on the repository by URL.
- Bundle license notices into the app.
- Standard TOML profile files.
- Known limitations: [renderer gaps](002-rendering-engine/renderer-gaps.md).
