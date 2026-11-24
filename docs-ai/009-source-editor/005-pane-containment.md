# 009.005 — iOS pane containment and shared position

## Decision

- Keep the Reader and Source instances for the document session under one UIKit
  container and attach only the active pane to the window, as the Mac app does
  ([011.004](../011-mac-app/004-source-pane-lifecycle.md)). Source is created on
  first use. Rebuilding a pane on each switch would rerun reader layout.
- The panes share one reading place, by source line, as on the Mac. A switch moves
  the destination only if the pane being left moved or the text changed, so an
  unchanged round trip keeps each pane's exact offset and the Source caret. When
  Source does move, its caret goes to the mapped line; the keyboard returns only if
  it was up before Preview.
- `topSourceLine` on iOS keeps a navigated line until the reader moves, because a
  line near the end may never reach the top of the viewport.
- While Source is showing, the Outline scrolls Source and highlights its current
  heading, as on the Mac. A jump waits for the outline of the current text. Unlike
  the Mac it doesn't take focus, which would raise the software keyboard.

This corrects the plan's independent pane positions: the maintainer requires iOS
to match the Mac.

## Refs

- `apps/iOS/Kasumi/ReaderSession.swift`
- `apps/iOS/Kasumi/ReaderWorkspace.swift`
- `apps/iOS/Kasumi/SourceEditor.swift`
- `Sources/KasumiMarkdownUI/UIKit/MarkdownReaderView.swift`

## Validation

- Runtime on iPhone 18 Pro / iOS 27.2: the place carried over in both directions,
  mid-document and from the end of the document. Unchanged round trips matched in
  the text area. Typing resumed at the caret after Preview; undo in Preview kept
  the place; saved files had only the intended edits; Find opened after Done.
- `MarkdownReaderUIKitTests` passed, including navigation while detached and
  retained navigated lines.
- Not verified: iPad (including Outline jumps while Source shows), iOS 18, physical
  devices, large documents, and the software keyboard.
