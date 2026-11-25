# 011.006 — Paper under the header

## Context

The maintainer asked for the window header and tab strip to match the theme's paper.
A first version copied the paper into the window background. It changed before the
page, because the reader installs a new theme only after an asynchronous layout.
A public reader callback fixed the order, but the maintainer rejected adding
library API for it.

## Change

- The reader and source panes ignore the top safe area and scroll beneath the header,
  so one scroll view paints both. No color is passed between them.
- `MarkdownReaderView` excludes the clip view's top content inset from `viewport`.
  Scroll destinations subtract the inset. The source editor does the same for line
  jumps and its top line.
- The Mac app uses the system default scroll edge effect; `.soft` is an iOS rule. A
  soft trial on Mac was reverted at the maintainer's request.
- Rejected: `titlebarAppearsTransparent`. Text showed through the header unblurred.
- The navigator and Outline draw the paper at 50% over the system material. An exact
  match would lose the distinction between page and chrome. Extending the page under
  the sidebars needs the safe-area setup rejected in
  [003](003-window-split-and-panes.md).
- The wash follows the theme choice rather than the installed layout, so it can lead
  the page; a 0.2 s fade softens that.

## Validation

`MarkdownReaderAppKitTests` passed, with no case for a nonzero top inset. The
maintainer reported that the header and the wash work, without naming the checks.
Find bar placement, tab bar changes while scrolled and macOS 26 were not separately
checked.

## Refs

`Sources/KasumiMarkdownUI/AppKit/AppKitMarkdownReaderView.swift`,
`apps/macOS/Kasumi/MacReaderScreen.swift`,
`apps/macOS/Kasumi/MacSourceEditor.swift`,
`apps/macOS/Kasumi/MacNavigatorSplit.swift`, `apps/Common/ToolbarAppearance.swift`.
