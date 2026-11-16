# 004 — iOS reader: document shell and reading view: Action record

Milestone 1 was closed on 2026-11-16 by maintainer decision. Remaining recorded
issues are non-blocking follow-ups; reader milestone 2 is the current focus.

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
| 2026-11-15 | Auto-hiding bars follow in-bounds finger travel, not bounce or bar-induced offset changes; drag direction resets for each gesture | — |
| 2026-11-15 | Keep the reader toolbar visible; remove auto-hide state and drag tracking | — |
| 2026-11-16 | Maintainer closed milestone 1 and chose to proceed directly to milestone 2; remaining issues retained as non-blocking follow-ups | — |

## Outcome and current state (as of 2026-11-16)

The launch scene, system document browser, paste and URL entry, reading view,
appearance controls, outline, and per-file reading position exist as described in
the plan. The outline has heading search, wrapping labels, shallow indentation,
and a rounded current-section marker; search omits the section gap above its
first visible result. Paste Markdown reports a denied read separately from an
empty clipboard.

Subsequent slices saved pasted and fetched documents through the single
`DocumentGroup` reader ([002](002-saved-imports.md)), replaced the iPad outline
sidebar with an inspector ([003](003-ipad-inspector.md)), added the share-sheet
import action ([004](004-import-action.md)), and handled files handed to a running
app and cold activation imports ([005](005-warm-file-handoff.md)). Their records
retain the implementation decisions, validation evidence, and limitations.

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

Bottom-scroll jitter fix, verified on 2026-11-15:

- `make run-sim` succeeded on iPhone 18 Pro, iOS 27.2.
- Pasted a multi-screen document with nested lists; fast bottom flings and
  repeated overscroll settled without layout oscillation in the simulator
  recording. Bars stayed hidden through rebound and reappeared on a deliberate
  reverse drag.
- Physical-device behavior was not verified.

Document-end scrolling fix (2026-11-15):

- Scroll extent now matches the rendered document height, including during
  width-change scaling. Outline and internal-link jumps retain the existing
  document-boundary clamp; short final sections need only be visible, not
  aligned to the top.
- `make run-sim` succeeded. Bottom scrolling and outline-jump behavior were
  not runtime-verified; further simulator checks were stopped at the user's
  request.

### URL-entry redesign (2026-11-15)

- URL entry is a single screen: large "Open URL" title, one URL field with a
  clear control, one line of guidance, and a full-width Open button. The Paste
  button, icon tile, field label, and introduction were dropped as noise; the
  system edit menu still pastes into the field.
- The field takes focus on appear. Keyboard Go submits; whitespace-only input
  disables Open.
- Feedback: the field border follows focus and turns red on error; the error
  replaces the guidance line in place; invalid input or a failed fetch shakes
  the field with an error haptic and refocuses it. While loading, Open keeps its
  colour and shows a spinner, and the field dims and locks.
- On success the form cross-fades into the reader, titled with the URL's last
  path component instead of "Untitled".
- URL entry has its own navigation stack, without reader Outline or Appearance
  controls or the iPad outline sidebar.
- Corrected 2026-11-15: URL entry is now a sheet over the launch scene, and the
  fetched document is saved and opened through `DocumentGroup`; see
  [002-saved-imports.md](002-saved-imports.md).
- Verified on the iPhone 18 Pro simulator (iOS 27.2): layout, autofocus with
  typing, clear button, invalid-URL error, a 404 fetch error, the loading
  spinner, and the hand-off to the reader with a `README.md` title. Not
  verified: haptics (the simulator has none), animation smoothness frame by
  frame, iPad layout, dark mode, and physical devices.

### Persistent reader toolbar (2026-11-15)

- The navigation toolbar stays visible while reading. Removed `barsHidden`,
  scroll-direction accumulation, and toolbar-reveal writes from taps, outline
  jumps, and appearance actions. Scrolling still reports reading position.
- This replaces auto-hiding rather than compensating content offsets during
  navigation-bar geometry changes.
- Removed the reader's opaque paper-colour toolbar background override so iOS
  supplies its native translucent scroll-edge treatment. A subsequent
  `make run-sim` succeeded on the same simulator; a scrolled screenshot showed
  blurred document content behind the status/navigation-bar region, with the
  toolbar still visible.
- Explicitly set `ReaderScrollView.topEdgeEffect.style = .soft` for a gradual
  blurred transition beneath the toolbar. `make run-sim` succeeded on iPhone
  18 Pro, iOS 27.2; a `sim-use` scroll and screenshot confirmed the soft fade
  with the toolbar remaining visible. Physical devices and iPad were not checked.
- `make run-sim` succeeded on iPhone 18 Pro, iOS 27.2. Opened
  `fixtures/Rendering.md` through the debug launch argument; `sim-use` forward
  and reverse scroll gestures kept the toolbar controls at the same positions.
  Screenshots confirmed that content scrolled beneath the visible toolbar.
  Outline presentation and a Mathematics section jump also kept it visible.
- An initial coordinate-based swipe unexpectedly returned to the launch screen;
  reopened the fixture and completed the checks with named scroll gestures.
  Physical devices and iPad were not verified.

### Maintainer-confirmed resolution (2026-11-16)

The maintainer confirmed that all seven numbered Reader 1 items from the review
are resolved:

1. External file handoff, including warm opens and duplicate navigation bars on
   cold opens.
2. In-place file opening on a physical device.
3. Per-file reading-position restoration.
4. Link and footnote taps.
5. iPad layout.
6. Reduce Motion.
7. Document-end scrolling and clamping after the fix.

This confirmation supersedes the earlier unverified status for these items.
No new test or runtime checks were run to record it; device and OS details were
not supplied. The separately reported intermittent blank iPad open and cold
share-sheet copies left in `Inbox` are not covered by this seven-item closure.

### Milestone closure (2026-11-16)

The maintainer explicitly closed Reader 1 and chose to proceed directly to
Reader 2: UIKit selection handles, Copy, a find bar with match navigation, and
external-link opening with confirmation. This is an acceptance decision, not
evidence of additional fixes or test runs.

The remaining open questions in [saved imports](002-saved-imports.md#open-questions),
the [iPad inspector](003-ipad-inspector.md#open-questions), and
[file handoff](005-warm-file-handoff.md#open-questions) remain recorded as
non-blocking follow-ups. In particular, the intermittent blank iPad open and cold
share-sheet files remaining in `Inbox` are not asserted resolved.

## Open questions

- In the iOS 27.2 simulator the document browser and the Files app show the
  Kasumi folder as empty although it holds `Welcome.md`, also on a freshly
  created simulator and with every file type accepted. Document Manager logs
  `failed to get a cached domain for FILocalAppContainerNode<Kasumi>` before
  enumerating, which points to the simulator's File Provider, not app
  configuration. Physical-device in-place opening was subsequently confirmed
  resolved by the maintainer on 2026-11-16; this simulator observation is not an
  outstanding physical-device validation requirement.
- Launch in the simulator stalls a few seconds while UIKit loads accessibility
  bundles; attributed to simulator automation, not the app.
- Apple's collapsed "Recents" / expanded "Kasumi Recents" titles are unchanged.
