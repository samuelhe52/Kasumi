# 009.004 — Markdown keyboard bar

## Context

On 2026-11-17 the maintainer asked for a keyboard bar modelled on another
editor's: history, a heading control and keyboard dismissal, plus a trailing
group of Markdown commands. This reverses the milestone's earlier non-goal
("formatting commands"). The reason is practical: on the iPhone keyboard, `>`,
`[`, `]` and `#` sit on the second symbol page, and `` ` `` needs a long press
on the apostrophe.

## Change

- **One glass capsule above the keyboard**: Undo, Redo, Heading ┊ Hide Keyboard
  (centered) ┊ Code, Quote, Link. It is a `UIGlassEffect` capsule of plain
  buttons in `SourceTextView.inputAccessoryView`. Rejected: `UIToolbar`, which
  moved the trailing group into an overflow menu at 402 pt. The SwiftUI
  `.keyboard` toolbar placement (iOS 15) only serves SwiftUI text input. The
  iOS 27.2 SDK has no newer API for a toolbar above the keyboard.
- **Commands act on lines and selections** (`SourceFormatting`, pure Foundation):
  - Heading cycles `#`…`######` → none on the current line; a long press picks
    a level or Body Text.
  - Code wraps the selection in backticks, unwraps an already wrapped
    selection, fences a selection that spans lines, and inserts a pair with
    the caret between them when nothing is selected.
  - Quote toggles `> ` on every selected line. Empty lines become `>` so the
    quote stays one block.
  - Link makes `[selection](|)`, `[|](url)` for a selected URL, or `[|]()`.
- Each command is one undo step, separate from typing undo.
- The Show Source toggle now uses `square.and.pencil` (the same symbol as Reader
  Actions > Edit), so `</>` belongs only to Code.

Not included: list, emphasis, table and indent commands (`-` is on the first
symbol page; the others are lower value on a phone).

## Refs

- `apps/iOS/Kasumi/SourceFormatting.swift`
- `apps/iOS/Kasumi/SourceEditor.swift`
- `apps/iOS/Kasumi/ReaderScreen.swift`
- `Tests/KasumiMarkdownTests/SourceFormattingTests.swift`, which reaches the
  app source through the `Tests/KasumiMarkdownTests/SourceFormatting.swift`
  symlink

## Validation

- `make test FILTER=SourceFormattingTests`: four tests passed on macOS. They
  cover heading cycling with a UTF-16 caret after an emoji, explicit levels,
  `#tag` lines, code wrap/unwrap/fence/pair, multi-line quote toggling with an
  empty line, and the three link forms.
- `make app` passed. On the iPhone 18 Pro / iOS 27.2 simulator, all seven
  buttons fit in the capsule, and Hide Keyboard is centered at 201 pt of
  402 pt. Heading, a single undo of one heading step, Link with typing inside
  the brackets, Quote and Code produced the expected source. The heading
  long-press menu lists Heading 1–6 and Body Text.
- Not checked: selection-based commands on device (the simulator driver
  cannot make a text selection), real IME composition with the bar, VoiceOver.
