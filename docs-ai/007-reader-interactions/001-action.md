# 007 — Reader selection, find, and links: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-11-16 | Recorded the milestone plan, implemented the UIKit text adapter, find controls, and link confirmation, then exercised the reader on the already booted iPhone simulator. | Local changes; not committed. |

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-11-16 | Implemented reader milestone 2 and reconciled the roadmap and development notes. | This implementation commit. |

## Outcome and current state (as of 2026-11-16)

Reader milestone 2 is implemented:

- `apps/iOS/Kasumi/ReaderTextInput.swift` adapts the immutable rendered snapshot
  to read-only `UITextInput`. UIKit supplies long-press selection, adjustment
  handles, magnification, and the edit menu. Copy and Select All use semantic
  text, including Unicode, code, and formula source. Editing entry points do
  nothing. A tap dismisses an existing selection before following a link.
- `Sources/KasumiMarkdown/RenderedDocument.swift` adds checked semantic UTF-16
  position arithmetic and distance queries, rejecting foreign snapshot positions
  and invalid/overflowing offsets. The precomputed grapheme-boundary index also
  supplies the UTF-16 document length without recounting the string on each
  tokenizer request. Hit testing still snaps to grapheme boundaries.
- `apps/iOS/Kasumi/ReaderFind.swift` owns case- and diacritic-insensitive search,
  the inline find bar, count, clear/done actions, and wrapping previous/next
  navigation. Return and Command-G advance, Shift-Command-G goes backward, and
  Escape closes find. The reader scroll view registers Command-F, so Find is
  available before the actions menu has ever opened.
- `apps/iOS/Kasumi/ReadingSurface.swift` keeps search highlights separate from
  native selection, scrolls the active match below the measured find-bar inset,
  and recomputes matches when the rendered snapshot changes. Selection is
  cleared on page replacement. Search state is passed as explicit representable
  inputs so UIKit receives navigation and presentation updates.
- `apps/iOS/Kasumi/ReaderScreen.swift` adds Find to Reader Actions, confirms an
  external destination before invoking the system opener, and reports opening
  failures. Heading/footnote links retain their in-document animated jumps;
  unresolved same-document fragments do nothing. Scroll edges remain `.soft`.
- `fixtures/ReaderInteractions.md` is the repeatable manual interaction fixture.
  No frozen measurements under `fixtures/reference/` changed. The pre-existing
  renderer shaping edits and gap-list edits were preserved.

## Deviations from plan

None in product scope. SwiftUI menu/scene keyboard shortcuts did not activate
Find on the iPhone simulator, so Command-F uses a native reader key command;
the find bar handles its own navigation keys. Those unsuccessful approaches
were removed.

## Validation

- `make app`: passed with Xcode 27 / iPhone Simulator SDK 27.2. An initial build
  rejected the macOS-only `onExitCommand`; the iOS implementation uses
  `onKeyPress`. Subsequent builds passed.
- `make test FILTER=PublicAPITests`: all 8 tests passed. Extended the existing
  link/anchor test with footnote-marker geometry and added a distinct arithmetic
  test covering Unicode UTF-16 offsets, boundaries, overflow, empty documents,
  and foreign layouts. Existing tiled-pixel, search, geometry, and export checks
  passed in the same focused suite.
- `make test-ios FILTER=PublicAPITests`: all 8 tests passed on iPhone 18 Pro,
  iOS 27.2; Xcode reported `TEST SUCCEEDED`.
- Runtime: iPhone 18 Pro, iOS 27.2, using `sim-use`; portrait and landscape.
  Observed native selection handles and Copy; dragged a handle across wrapped
  lines and checked the copied text. Select All followed by hardware Command-C
  copied 2,060 semantic characters, preserving the family emoji and `x_i+1`
  while excluding Markdown emphasis delimiters.
- Find: inspected active/inactive highlights, first/last wraparound, no results
  with disabled navigation, clear, Done, Escape, Command-F, Command-G and
  Shift-Command-G. Rotation recomputed the results and kept the active match
  visible. Initial runtime checks exposed missing first-responder activation
  and a missing measured inset; both were corrected and checked again.
- Links: confirmed the HTTPS destination, dismissed confirmation without leaving
  the reader, approved opening into Safari, and returned through the system
  breadcrumb. An unsupported scheme displayed the opening-failure alert.
  Heading and footnote links reached their destinations inside the same reader.
  Recorded a heading jump and inspected intermediate frames, confirming movement
  through the document. Recordings/screenshots were local and are not retained
  as repository evidence. Early footnote taps missed the small superscript;
  inspecting its screenshot coordinates located the marker and the tap succeeded.
- `git diff --check`: passed.

## Open questions

- No iPad or physical-device runtime checks were performed; another simulator
  was not booted. The phone used a hardware keyboard, so software-keyboard
  occlusion was not exercised. Reduce Motion was preserved in source but was
  not toggled during this task.
- Mixed-direction selection, very large-document search performance, and
  selection-handle autoscrolling beyond the viewport were not exhaustively
  exercised. The existing renderer limitations remain in the
  [renderer gap list](../002-rendering-engine/renderer-gaps.md).
