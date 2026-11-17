# 007 — Reader selection, find, and links: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-11-16 | Recorded the milestone plan, implemented the UIKit text adapter, find controls, and link confirmation, then exercised the reader on the already booted iPhone simulator. | `f247bfd` |
| 2026-11-16 | Replaced the top bar with system Find and corrected keyboard underlap and scrolling. | This follow-up commit; [002](002-system-find-navigator.md). |

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
- `apps/iOS/Kasumi/ReaderFind.swift` implements a read-only `UIFindSession`,
  honoring the system match options and wrapping navigation. This replaces the
  custom top bar from `f247bfd`; see [002](002-system-find-navigator.md).
- `apps/iOS/Kasumi/ReadingSurface.swift` installs `UIFindInteraction`, lets the
  page paint behind the native floating controls, and uses `UIKeyboardLayoutGuide`
  for unobscured scrolling. Search highlights remain separate from selection;
  positions and highlight geometry refresh for each snapshot. Width-only reflows
  now reuse semantic match offsets when exact text and options agree; see
  [retained matches](003-retained-find-matches.md).
- `apps/iOS/Kasumi/ReaderScreen.swift` adds Find to Reader Actions, confirms an
  external destination before invoking the system opener, and reports opening
  failures. Heading/footnote links retain their in-document animated jumps;
  unresolved same-document fragments do nothing. Scroll edges remain `.soft`.
- `fixtures/ReaderInteractions.md` is the repeatable manual interaction fixture.
  No frozen measurements under `fixtures/reference/` changed. The pre-existing
  renderer shaping edits and gap-list edits were preserved.

## Deviations from plan

The first implementation used a custom top bar and separate keyboard handlers.
Maintainer feedback replaced these with the keyboard-attached UIKit find
navigator; [002](002-system-find-navigator.md) records the change and its fresh
validation. The initial validation below remains evidence for `f247bfd`.

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
  was not booted. The original milestone pass used a hardware keyboard;
  [002](002-system-find-navigator.md) adds portrait software-keyboard coverage
  and records the remaining landscape check. Reduce Motion was preserved in
  source but was not toggled during these checks.
- Mixed-direction selection, very large-document search performance, and
  selection-handle autoscrolling beyond the viewport were not exhaustively
  exercised. The existing renderer limitations remain in the
  [renderer gap list](../002-rendering-engine/renderer-gaps.md).

## System find follow-up

See [007.002](002-system-find-navigator.md) for the native panel, the keyboard
safe-area correction, and the follow-up validation. The original software-keyboard
coverage limit above was addressed in that follow-up; iPad/device coverage remains
unverified.
