# 004 — iOS reader: document shell and reading view: Plan

| Field | Value |
| --- | --- |
| Status | Implemented (reader milestone 1; closed 2026-11-16) |
| Anchor date | 2026-11-14 |
| Origin | First reader milestone from the [goal](../001-library-and-reader/goal.md). Reconstructed on 2026-11-15 from Git history and the status document during the docs-ai migration; it did not precede the work. |
| Related | [003](../003-public-rendering-api/000-plan.md), [roadmap](../roadmap.md), [development notes](../../docs/development.md#simulator-and-device-notes) |

## Background

The app shell from `33e4179` launched but didn't render documents. Milestone 1
turns it into a document app that opens Markdown and reads it with the
library's typography.

## Goals

- Document app shell with `DocumentGroupLaunchScene` and `DocumentGroup`:
  Files/iCloud, in-place opening, recents, and windows. Pasted text and
  fetched URLs are saved as documents and open the same way (corrected by
  [002](002-saved-imports.md); they first opened as untitled documents).
- Reading view with edge-to-edge paper, system light/dark, searchable outline,
  and per-file reading position.

### Non-goals

Later milestones in the [roadmap](../roadmap.md): selection and find, export,
source editor, settings and font store.

## Design / approach

- `apps/iOS/Kasumi/KasumiApp.swift`: `DocumentGroupLaunchScene` with Paste
  Markdown and Open URL above the system document browser; `DocumentGroup` owns
  file opening. On first launch the app copies `Welcome.md` into its Documents
  folder.
- `apps/iOS/Kasumi/LaunchActions.swift`: paste and URL entry, saved to the
  `Pasted` and `Downloaded` folders ([002](002-saved-imports.md)).
- `apps/iOS/Kasumi/ReaderDocument.swift`, `ReaderState.swift`: the read-only
  document and per-file reading position in milestone 1. The document session
  becomes writable in [009](../009-source-editor/000-plan.md).
- `apps/iOS/Kasumi/ReadingSurface.swift`: lays out on a background task and draws
  with `CATiledLayer`; keeps the toolbar visible while scrolling; animated section jumps.
- `apps/iOS/Kasumi/ContentView.swift`: reader screen, appearance controls (preset,
  size, theme), outline as a full-height sheet on iPhone and a sidebar on iPad (an inspector
  since [004.003](003-ipad-inspector.md)).

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Native `DocumentGroupLaunchScene` / `DocumentGroup`, no custom browser or file-session path | Use the system document browser, recents, and windows rather than reimplementing them (`6821de1` and the status document). |
| Background layout and `CATiledLayer` | Built on the immutable `RenderedDocument` ([003](../003-public-rendering-api/000-plan.md)); `66713de`. |
| Paste Markdown reads the clipboard directly on tap | `c38af32` first replaced the direct read with a text sheet, because pasting into a sheet through the edit menu needs no pasteboard permission and the simulator read returned nothing. `7778595` reverted to the direct read so iOS shows its own consent prompt under Paste from Other Apps > Ask; verified on a physical iPhone. The simulator can't show that prompt ([development notes](../../docs/development.md#simulator-and-device-notes)). |
| Short fade on first reveal and animated section jumps, both off under Reduce Motion | `6821de1`, `fbb13cb`. |

## Evidence and recovered rationale

- Source documents: commit messages and the status document diffs in
  `8524a12`, `c38af32`, `7778595`, `6821de1`, `fbb13cb`.
- Inference: none beyond those.

## Validation and acceptance criteria

Run on the simulator with `make run-sim` and drive it with `sim-use`: open a file
in place, paste, open a URL, outline search and navigation, reading-position
restore, link and footnote taps, iPhone and iPad layouts, Reduce Motion. Check the
paste consent prompt on a device (`make run-device`).

## Amendments

- Updated 2026-11-17: source editing replaces the read-only document session;
  see [009](../009-source-editor/000-plan.md).
- Updated 2026-11-15: removed toolbar auto-hiding to avoid bar-driven viewport
  shifts; see [action record](001-action.md#persistent-reader-toolbar-2026-11-15).
- Updated 2026-11-15: save pasted and fetched documents as files and open every reader through `DocumentGroup`; corrected the Goals and the action record's URL-entry notes — see [002-saved-imports.md](002-saved-imports.md).
- Updated 2026-11-16: "Import into Kasumi" share-sheet Action extension, saved to `Documents/Imported/` — see [004-import-action.md](004-import-action.md).
- Updated 2026-11-16: corrected action-icon packaging and refreshed the stale
  installed icon with build 2; replaced the unconfirmed alpha-flattening theory
  with controlled identity/version evidence — see
  [icon correction](004-import-action.md#icon-correction-2026-11-16).
- Updated 2026-11-16: open files handed to a running app, open "Import into
  Kasumi" files on a cold launch (004.004's activation import corrected in
  place), and wait for a ready browser before every programmatic open — see
  [005-warm-file-handoff.md](005-warm-file-handoff.md).
- Updated 2026-11-16: closed reader milestone 1 by maintainer decision and moved
  directly to milestone 2. Remaining recorded issues are non-blocking follow-ups,
  not claimed fixes — see [milestone closure](001-action.md#milestone-closure-2026-11-16).
- Updated 2026-11-17: bounded background reflow during window resizing, stable
  semantic anchors, and non-scrolling Find remaps — see [006-live-reflow.md](006-live-reflow.md).
- Updated 2026-11-17: Rebase anchors on installed content revisions and track keyboard-driven Find scrolling — see [007-reflow-anchor-lifecycle.md](007-reflow-anchor-lifecycle.md).
- Updated 2026-11-17: Refine viewport snapshots on scrolling and semantic navigation, preserving same-content selection — see [002.016](../002-rendering-engine/016-viewport-layout.md).
- Updated 2026-11-17: Preserve horizontal table scroll ownership and offsets across mixed-content refinement — see [002.018](../002-rendering-engine/018-mixed-viewport-coverage.md).
- Updated 2026-11-18: save spacing per typography preset and keep reader text
  size global. See [008-preset-spacing.md](008-preset-spacing.md).
