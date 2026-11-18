# 009.002 — Simpler editor controls

## Context

The maintainer requested a simpler, more usable milestone 4 interface on
2026-11-17. The initial iPhone implementation puts Done in a bottom toolbar
that disappears while typing, separates Source/Preview from editing actions,
and recreates the panes when switching. Editing remains an infrequent action
entered from Reader Actions.

## Change

- Put Done in the navigation bar so returning to reading is available with the
  keyboard open. Keep native document autosave; Done exits editing.
- Consolidate Undo/Redo and Source/Preview into one editor row. The maintainer's
  follow-up removes Actions from editing entirely. Remove the duplicate keyboard
  accessory; retain interactive keyboard dismissal and Escape.
- Retain both panes while editing, including their selection and scroll state.
  Wide layouts label Source and Preview rather than showing a redundant switch.
- Returning to Source restores keyboard focus only if it was active before
  Preview. Leaving editing clears that preference. Find is dismissed when its
  pane is hidden; presenting or dismissing it is deferred beyond SwiftUI's view
  update to avoid a reentrant responder-graph cycle.
- Scale the monospaced editor font with Dynamic Type and give source text a
  little more breathing room: 20 pt top/side insets, no extra text-container
  fragment padding, and 32 pt at the end. Keep source and preview on the same
  paper color. Preserve literal punctuation and document undo.
- Use aligned 44 pt icon targets, observable undo availability, a centered
  compact switch and a stacked fallback when the controls do not fit. Symbols
  scale up to 24 pt to avoid overlapping at accessibility text sizes.
- Use a native 240 ms content crossfade and a 200 ms editing-mode chrome
  transition; disable these custom animations with Reduce Motion. Keep preview
  content below the editor row, with soft scroll edges throughout.

A formatting ribbon, syntax highlighting, resizable pane handles and extra
settings are outside this refinement. A new editing entry point would conflict
with the earlier decision to keep the reader primary.

## Refs

- `apps/iOS/Kasumi/ReaderScreen.swift`
- `apps/iOS/Kasumi/SourceEditor.swift`
- `apps/iOS/Kasumi/ReadingSurface.swift`
- `apps/iOS/Kasumi/ReaderPaneTransition.swift`
- Verification recipes: [003](003-native-editor-chrome.md), [004](004-markdown-keyboard-bar.md)

## Validation

- `make app`: passed for iPhone 18 Pro / iOS 27.2. The existing no-App-Intents
  metadata warning remains.
- `make test FILTER=DocumentSourceTests`: three tests passed on macOS.
- `sim-use` preflight passed on the already booted iPhone 18 Pro / iOS 27.2.
  Verified keyboard-visible Done, source/preview switching, toolbar undo/redo,
  Command-Z/Shift-Command-Z, and insertion at the retained caret after a preview
  round trip. Checked saved source against the fixture plus one inserted marker,
  closed/reopened the file and found that marker in the source accessibility
  value.
- Opening Find from a focused source editor initially hung in a reentrant
  SwiftUI responder-graph update. A main-thread sample identified synchronous
  `presentFindNavigator` inside `updateUIView`. After deferring the responder
  handoff, the same flow opened Find successfully; switching to Source removed
  Find and restored the source keyboard without a hang.
- Visual inspection caught and corrected preview heading occlusion beneath the
  editor row. Inspected screenshots and frames from a simulator recording of
  pane switching and returning to reading. These are local, unretained evidence.
- At the largest accessibility text size, the source font scaled but toolbar
  symbols initially overlapped; verified the 24 pt cap fixes that overlap.
  Restored the original text-size slider value (27%, with Larger Accessibility
  Sizes enabled). Checked pane switching and Done with Reduce Motion enabled,
  inspected recording frames, and restored Reduce Motion to its original off
  state.
- After scrolling source without focusing it, switching to Preview and back
  produced pixel-identical source content in the compared viewport region
  (excluding the toolbar and scroll indicator). Checked the iPhone landscape
  layout and restored portrait orientation.
- `git diff --check`: passed. Amendment links resolve. No frozen reference
  expectations were changed. Changes remain uncommitted.

## Validation limits

No iPad simulator was launched. Wide-layout resizing, the narrow stacked
fallback, physical-device behavior, real IME composition and VoiceOver remain
unverified at runtime. This refinement does not introduce synchronized scrolling
or incremental rendering.

## Follow-up — keyboard seam and visible transitions (2026-11-17)

The maintainer's screenshot showed a dark corner seam above the keyboard. Their
recording also showed a single-frame content switch and a near-black-to-gray
header change. The earlier 180 ms SwiftUI opacity declaration did not establish
an actual native content fade; this corrects that earlier implementation and
validation claim.

- Removed the editing ellipsis control. Reader actions remain available after
  Done. The switch stays centered against the history controls.
- Give the navigation bar and editor row the same explicit paper background.
  Their tint no longer depends on whichever pane is currently underneath them.
- Crossfade the native UIKit pane views with `ReaderPaneTransition`, retaining
  the source view after its first use so Done can crossfade into the reader too.
  Reader-only document opens still avoid creating an editor.
- `SourceEditorView` paints paper through the keyboard safe area, while its
  child text view ends at the keyboard layout guide. An initial full-height text
  view experiment exposed document text through the keyboard's glass; restricting
  the child viewport fixes that while preserving the paper behind the corners.
- `make app` passed. On the already booted iPhone 18 Pro / iOS 27.2, verified
  the missing editor menu, keyboard seam, last-line caret visibility, undo/redo,
  Done, and typing at the retained caret after a Source/Preview round trip.
  Closing directly from the keyboard preserved exactly the original fixture
  bytes plus the inserted test markers. The author's source fixture and the
  maintainer's open document were not modified.
- Inspected a recorded native fade midpoint. A crop of the maintainer's video
  changed content in one frame per switch; the new recording contains gradual
  content changes across multiple frames. Recordings and screenshots are local
  verification artifacts, not retained repository evidence.

The maintainer subsequently excluded further Reduce Motion testing. Its original
off setting was restored. `git diff --check` passed. No iPad or physical-device
checks were performed for this follow-up. Changes remain uncommitted.
