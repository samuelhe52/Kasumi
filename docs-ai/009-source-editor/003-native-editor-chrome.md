# 009.003 — Native editor chrome and narrower scope

## Context

On 2026-11-17 the maintainer reported that the navigation bar had become a hard
clip in reading mode, and suspected that the milestone 4 implementation was too
complex while still leaving UX gaps. A review of the uncommitted work confirmed:

- `ReaderScreen` set an opaque paper `toolbarBackground` on the navigation bar
  in every mode. It hid a header colour change during pane switches, but replaced
  the soft scroll edge with a hard clip. The custom editor row under the bar was a
  second opaque strip.
- Every keystroke registered its own document undo step, holding a full copy
  of the source, and undo restored the old caret rather than revealing the
  change.
- The `ReadingSurface` layout worker had been rewritten into a drain loop to stop
  layout workers piling up during typing. On iPhone the hidden preview never lays
  out, so this only served the wide iPad split, which had never been run.

## Change

- **Native bar items, no custom row.** The navigation bar keeps the document
  title. While editing, it carries a Source/Preview toggle button and Done, pinned
  with `.topBarPinnedTrailing` so it never overflows. Undo/Redo sit in the bottom
  bar, where the reader keeps its actions. While the keyboard is up they appear
  in the text view's `inputAccessoryView`, because SwiftUI's `.keyboard` toolbar
  placement does not attach to a UIKit text view. Both panes run edge to edge
  under the bars with soft edges. The source text view also extends under the
  bottom bar when the keyboard is hidden (`usesBottomSafeArea = false`).
  Rejected: a segmented picker in `.principal`. On a 402 pt iPhone it sat beside
  the document title menu and pushed Undo, Redo and Done into the overflow menu.
- **iPad split deferred.** The wide-window side-by-side layout is removed; every
  width uses the Source/Preview toggle. The maintainer subsequently removed the
  side-by-side requirement from the milestone on 2026-11-18.
- **Original layout worker.** `ReaderScrollView` keeps its cancel-and-respawn
  worker. The only changes are a gate that skips layout while the preview is
  hidden and a `setNeedsLayout` on reactivation, so a rotation made in Source is
  laid out when Preview returns. Source-only revisions still skip the crossfade.
- **Typing undo.** `ReaderDocument.setText` registers one undo step per typing
  burst. A burst ends after a one-second pause, a new line, or an edit away from
  the caret; the editor reports the last two. Marked-text replacements count as
  contiguous, so IME composition does not split steps. Undo and redo select the
  changed range and scroll it into view.

## Follow-up — pane flash and keyboard accessory (2026-11-17)

- **Flash on pane switches.** The maintainer still saw a brief flash. Logging
  the preview's scroll offset showed its adjusted top inset flipping between
  116 pt and 0 on every visibility change. The stack showed SwiftUI re-inserting
  the native view into another container when `.allowsHitTesting` and
  `.accessibilityHidden` changed. The new parent reported no safe area, so UIKit
  shifted the offset mid-fade and the tiled page briefly showed blank tiles.
  `ReaderPaneTransition` now sets `isUserInteractionEnabled` and
  `accessibilityElementsHidden` on the UIKit views instead. Do not reintroduce
  those SwiftUI modifiers on the pane representables.
- **Keyboard accessory spacing.** The history capsule sat flush on the
  keyboard. It now has 12 pt of clear space below it. Source text runs under the
  clear accessory to the keyboard's top edge, like under the bottom bar, and a
  matching content inset keeps the caret line above the capsule.

## Refs

- `apps/iOS/Kasumi/ReaderScreen.swift`
- `apps/iOS/Kasumi/SourceEditor.swift`
- `apps/iOS/Kasumi/ReaderDocument.swift`
- `apps/iOS/Kasumi/ReadingSurface.swift`
- `apps/iOS/Kasumi/ReaderPaneTransition.swift`

## Validation

- `make app`: passed for iPhone 18 Pro / iOS 27.2.
- On the already booted iPhone 18 Pro / iOS 27.2, driven with `sim-use`:
  - Reader and editor top edges blur softly; the source runs under the bottom bar.
  - The editor bar keeps Back, title, toggle and Done visible.
  - Typing `Alpha beta`, pausing, then typing ` Gamma` took exactly two undos.
  - The keyboard accessory undo and redo work.
  - The preview showed the edit, and Source restored the keyboard.
  - Done returned to reading; the saved file contained the edit after closing.
  - Rotating to landscape in Source and then showing Preview laid out at
    landscape width.
- Follow-up, same simulator: 60 fps recordings of Source/Preview with and
  without the keyboard, Done and Edit show steady positions and plain
  crossfades with no one-frame luminance spikes; the earlier recording had one
  at each switch back to Source. Checked accessory spacing and caret visibility
  while typing near the bottom.
- Not checked: iPad, physical devices, real IME composition, VoiceOver, Reduce
  Motion and large accessibility text sizes with the new bar.
