# 004.002 — Saved imports and a single reader presentation

## Context

Pasted text and fetched URLs opened in a standalone reader presented as a
full-screen cover, outside `DocumentGroup`. That gave the reader two
presentation contexts: it had to wrap itself in its own navigation container for
the cover, and the same wrapper nested a second navigation bar inside the system
document presentation. Closing the cover discarded the content.

## Change

- Paste Markdown writes the clipboard text to
  `Documents/Pasted/Pasted Text <yyyy-MM-dd HH.mm.ss>.md`. Open URL writes the
  fetched bytes to `Documents/Downloaded/` under the server's file name, adding
  `.md` when the name has no `md`, `markdown`, or `txt` extension and " 2", " 3",
  … on name clashes. Both then open the saved file through the launch scene's
  system document browser, so every reader is a `DocumentGroup` document and
  imports persist across relaunches.
- The folder is the only record of where a document came from. Deleting a
  folder in the browser removes every import of that kind.
- Every reader leaves through the system Back button, which keeps the file.
  Documents in `Pasted` or `Downloaded` get a Delete (trash) button pinned to
  the trailing edge of the top toolbar. It asks for confirmation ("Delete
  <name>?", "This can't be undone."); confirming closes the reader, deletes the
  file, and drops the saved reading position. Other documents
  have no Delete. The system's document title menu is left as `DocumentGroup`
  provides it.
- Open URL is a sheet over the launch scene. The reader no longer has a URL
  entry state, a standalone mode, a Close button, or its own navigation
  container on iPhone. On iPad it keeps its `NavigationSplitView` for the
  outline sidebar.
- Debug `-KasumiOpen <path>` copies the file into `Documents/Debug/` and opens
  it the same way.
- Fetched documents resolve relative links and images against their local
  folder. No source URL is recorded.

## Decisions

| Choice | Reason and alternative |
| --- | --- |
| Save imports as real documents | One presentation path. Temporary files were rejected: the browser can only open files it can reveal, which means importing them into Documents, and per-file exclusion from Recents isn't available (only per content type). Keeping the cover and letting `ReaderScreen` own navigation everywhere was the other option; the maintainer preferred one path. |
| Folder per import kind, no metadata | Self-describing in the browser and deletable as a unit; no sidecar or index to keep in sync. |
| Open saved files by calling the browser delegate's pick method directly | `revealDocument(at:importIfNeeded: true)` saved a second copy in the root of Documents and opened that, so Recents showed duplicates and the copy landed outside the import folders. Without import, reveal fails with DocumentManager error 1. The saved files already sit in the browser's Documents location. |
| Back is the only exit; Delete is a confirmed toolbar button | The first version replaced Back with a Close (X) button that asked Keep or Delete. On iPhone the bar belongs to `DocumentGroup`, and its Back button stayed: `.navigationBarBackButtonHidden()`, `.toolbar(.hidden, for: .navigationBar)`, and setting `hidesBackButton` in UIKit all failed to remove it (SwiftUI rebuilds the navigation item), so Back bypassed the prompt. The maintainer chose to follow the system bar. Delete first ran without confirmation; the maintainer then asked for one. |
| Delete only for imports, as a toolbar button | Maintainer decision, which also leaves the system title menu untouched. Delete first went into the title menu for imports, then into the title menu for every document. |
| Pin Delete with `.topBarPinnedTrailing` | A plain trailing item moved into the system More menu next to every pasted-text title. `.visibilityPriority(.high)` only orders what overflows first and didn't keep it in the bar. A pinned item stays at the trailing edge, and the other items overflow around it, so Delete sits right of the system `…`. Putting Delete and an app `…` menu into one pinned item placed Delete left of `…`, but hid Outline and Appearance in that menu even when they fit; the maintainer chose the plain pinned item. Shortening pasted-text names was rejected: `Pasted 2026-11-15 20.35.md` still overflowed. The toolbar button uses the default tint and no destructive role, by maintainer decision; only the confirming button is destructive. |
| Keep relative links and images unresolved for fetched documents | Accepted regression by maintainer decision. |

## Validation

iPhone 18 Pro simulator, iOS 27.2, `make run-sim`, driven with `sim-use`:

- Paste Markdown saved one file in `Documents/Pasted/` and opened it; no copy
  appeared in the root of Documents. The simulator clipboard follows the Mac's,
  so the saved text was whatever the Mac clipboard held, not text set with
  `simctl pbcopy`.
- Open URL fetched
  `https://raw.githubusercontent.com/swiftlang/swift/main/README.md` while
  `Downloaded/README.md` existed; it saved `Downloaded/README 2.md` and opened
  it.
- Pasted document (long title): the bar shows Back, the cut-short title, the
  system `…` holding Outline and Appearance, then Delete. Delete opened a
  confirmation popover anchored to the button; tapping outside it kept the
  file, and its red Delete closed the reader and removed the file. Checked with
  an earlier message text, "This removes the file from Kasumi."
- Downloaded `README.md` (with the same pinned placement, before the tint was
  dropped): Outline, Appearance, then Delete; Delete removed the file.
- `Typography-11.md` in the root of Documents shows no Delete, and its title
  menu is the system one (Rename).
- Back from a pasted document reopened from Recents returned to the launch
  scene and kept the file.
- After relaunch, imports were still on disk.

Not verified: iPad; that the saved reading position is removed; physical
devices.

## Open questions

- iPad: the reader no longer hides the system bar, because Back is now the only
  exit. The split view brings its own bar, so iPad probably shows two bars
  (inference; not run).
- A long title moves Outline and Appearance into the system More menu on
  iPhone. `Typography-11.md` and `README.md` fit; every pasted-text name
  overflows, and so did the shorter `Pasted 2026-11-15 20.35.md`.
- Imports opened by the app weren't in Recents after a relaunch; ones later
  opened from the browser were. Recents is maintained by the system browser.

## Refs

- `apps/iOS/Kasumi/LaunchActions.swift`
- `apps/iOS/Kasumi/ContentView.swift`
- `apps/iOS/Kasumi/ReaderDocument.swift`
- `apps/iOS/Kasumi/ReaderState.swift`
