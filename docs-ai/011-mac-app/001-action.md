# 011 — Native Mac app: Action record

## Timeline

| Date | Change |
| --- | --- |
| 2026-11-24 | Reader source-line mapping, `KasumiMac` target, shared `apps/Common/` code, panes, source mode, Find, menus, PDF export, print and Settings, on SwiftUI `DocumentGroup`. |
| 2026-11-24 | The `Document` API bridge deadlocked AppKit's conflict recovery; the app moved to `ReferenceFileDocument`. Opening files as tabs still flashed or left standalone windows. |
| 2026-11-24 | Maintainer dropped `DocumentGroup`. The shell was rewritten on `NSDocument` with AppKit windows and menus, and the unpushed history was collapsed so the earlier shell is not in it. |

A Codex session implemented the rewrite and ran the runtime checks. Claude set the
design, reviewed each diff, fixed one bug (below), and made the docs and commits.

## Outcome and current state (as of 2026-11-24)

- `KasumiMac` in `apps/iOS/Kasumi.xcodeproj` builds `Kasumi.app` (macOS 26 minimum,
  not sandboxed, hardened runtime). Makefile targets: `app-mac`, `app-check-mac`,
  `run-mac`.
- `MacDocument` owns the model, session, file watch and teardown. It tracks the text
  saved in the original file separately from the text in a recovery copy, and derives
  its edited state by comparing text with those baselines rather than from AppKit's
  change count, which missed edits whose undo group was still open.
- Pending editor text is finished before explicit saves, close and quit.
  `MacApplication.terminate` does it because AppKit reviews documents before asking
  the delegate. Autosaves never end an input method's composition: they write the
  last committed text and the document stays edited.
- `MacDocumentWindowController` places a window once, in its first `showWindow(_:)`.
  `MacDocumentController` keeps the source of an explicit open and resolves symlinks
  before opening, because AppKit rejected a symlink URL. Saves go to the target file.
- `MacMenu` builds the AppKit main menu. Settings is a SwiftUI `Settings` scene
  hosted by `NSHostingSceneRepresentation`.
- The toolbar comes from `NSHostingController.sceneBridgingOptions = [.toolbars]`.
- ⇧⌘[ / ⇧⌘], ⌥⌘← / ⌥⌘→ and ⌃⇥ / ⌃⇧⇥ are handled by a local key monitor.

Key files: `apps/macOS/Kasumi/MacDocument.swift`,
`apps/macOS/Kasumi/MacDocumentController.swift`,
`apps/macOS/Kasumi/MacDocumentWindowController.swift`,
`apps/macOS/Kasumi/KasumiMacApp.swift`, `apps/macOS/Kasumi/MacCommands.swift`,
`apps/macOS/Kasumi/MacSourceEditor.swift`, `apps/macOS/Kasumi/MacFileEvents.swift`,
`apps/iOS/Kasumi/ReferenceReaderDocument.swift` (iOS only).

## Deviations from plan

- The plan relied on the undo manager alone for the edited state. Baseline comparison
  replaced it after an immediate quit or close lost text in the first native build.
- The key monitor also covers ⌃⇥ / ⌃⇧⇥.

## Validation

Run by Claude on macOS 27.2.1 with the final source: `make test` (306 tests),
`make app-check-mac` and `make app-check`.

Reported by the Codex session on macOS 27.2.1 with isolated bundle IDs (logs under the
ignored `build/mac-native-verification/`). Keyboard input was synthesized natively.

- Navigator, Open, Recent, Finder-style, link, symlink, concurrent and closed-source
  opens reached the right group; measured opens in the running app showed no
  standalone window. Five files at a cold launch shared one group.
- Text survived immediate close and quit after typing, paste, accessibility insertion
  and marked text (all eight cases). Autosave during a simulated composition, undo to
  clean across a save, and typing through an external write lost nothing.
- Save Anyway and Revert after in-place and atomic external writes; Save As with the
  destination supplied to the save call. Versions browser and Restore, Revert To, Save
  As to `.txt`, Duplicate, rename, move, deletion, locked and lossy files, PDF export.
- ⌘W closed one tab; ⌘Q kept or reviewed drafts as AppKit does under both Close Windows
  settings. Restoration of groups, a detached window and an untitled draft.
- A closed tab released its document, window, session and file watch.
- Median key-down time in a 5 MB file: 0.72 ms at the start and 701 ms at the end,
  against 1.64 ms and 698 ms in the `DocumentGroup` build.

Claude's review found that the byte comparison could read past a buffer when two texts
had equal UTF-16 but different UTF-8 lengths; it now compares byte counts first. The
close, quit and latency checks were rerun after that fix.

## Open questions

- Not run: macOS 26, a physical keyboard, a live input method, minimized sources
  (Stage Manager blocked the check), literal tab dragging, printing, the conflict Save
  As panel to completion, every menu effect in every focus context, Reader-mode place
  and Find across an external reload, iOS at runtime, Developer ID signing.
- AppKit does not complete several opens in request order, so tab order at a cold
  launch with several files is unspecified.
- Navigator rows measure 32 pt apart although the list requests 22 pt, and no outline
  heading is current at the very top of a document. Both predate the rewrite.
- Typing at the end of a 5 MB file takes about 0.7 s per key. Also predates it.
- With the system setting that asks before keeping changes on close, ⌘W prompts for
  named files. That is AppKit's behavior.
