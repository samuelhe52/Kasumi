# 004 — iOS reader: document shell and reading view: Action record

Milestone 1 is in progress; this record covers the slices so far and will be
finished when the milestone closes.

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-11-14 | Universal app shell | `33e4179` |
| 2026-11-14 | Bundled sample document rendered through the library | `6fee2a7` |
| 2026-11-14 | Background layout and tiled drawing | `66713de` |
| 2026-11-14 | Run targets for the simulator | `6302742` |
| 2026-11-15 | Document browser and reading view; memory stayed at 55–70 MB on the Welcome document through scrolling, rotation, dark mode, and style changes (status document) | `8524a12` |
| 2026-11-15 | Paste Markdown through a text sheet | `c38af32` |
| 2026-11-15 | `make run-device`; app category; signing team in the project file | `52ab944`, `a4ea0b3`, `eaa1c57` |
| 2026-11-15 | Outline search, wrapping labels, current-section marker; progress indicator and fade on opening | `6821de1` |
| 2026-11-15 | Paste Markdown reads the clipboard directly again | `7778595` |
| 2026-11-15 | Animated section jumps | `fbb13cb` |

## Outcome and current state (as of 2026-11-15)

The launch scene, system document browser, paste and URL entry, reading view,
appearance controls, outline, and per-file reading position exist as described in
the plan. The outline has heading search, wrapping labels, shallow indentation,
and a rounded current-section marker; search omits the section gap above its
first visible result. Paste Markdown reports a denied read separately from an
empty clipboard.

Key files:

- `apps/iOS/Kasumi/KasumiApp.swift`
- `apps/iOS/Kasumi/LaunchActions.swift`
- `apps/iOS/Kasumi/ReaderDocument.swift`
- `apps/iOS/Kasumi/ReaderState.swift`
- `apps/iOS/Kasumi/ReadingSurface.swift`
- `apps/iOS/Kasumi/ContentView.swift`
- `apps/iOS/Info.plist`

## Deviations from plan

The plan is retrospective. The paste text sheet (`c38af32`) was reverted the same
day (`7778595`).

## Validation

Recorded in the status document at `fbb13cb`; nothing was rerun for this record.

- iPhone 18 Pro, iOS 27.2 simulator: `make run-sim` succeeds; one tap imports
  external Markdown and Japanese text into the reader when paste access is
  allowed. Earlier passes exercised Outline navigation, heading search, wrapping
  labels, selected-heading tracking, URL-entry presentation, and return to the
  native Recents card.
- Physical iPhone: the Paste from Other Apps > Ask prompt appears.
- Not verified: URL fetching, iPad layout, Reduce Motion, in-place file opening,
  reading-position restore, link and footnote taps.

## Open questions

- In the iOS 27.2 simulator the document browser and the Files app show the
  Kasumi folder as empty although it holds `Welcome.md`, also on a freshly
  created simulator and with every file type accepted. Document Manager logs
  `failed to get a cached domain for FILocalAppContainerNode<Kasumi>` before
  enumerating, which points to the simulator's File Provider, not app
  configuration. Needs a check on a physical device; it blocks verifying
  in-place opening on the simulator.
- Launch in the simulator stalls a few seconds while UIKit loads accessibility
  bundles; attributed to simulator automation, not the app.
- Apple's collapsed "Recents" / expanded "Kasumi Recents" titles are unchanged.
