# 011.003 — Window split and panes

## Context

The maintainer reported that opening the outline reflowed the text live while the
leading sidebar did not, that navigator rows were not compact, and asked for a fixed
Outline title, no underline on the current heading, a smaller source font and thinner
scrollbars.

## Change

- Inside `NavigationSplitView` the reader's host kept the window's full width and its
  leading safe area changed in one step, so the text never received intermediate
  widths. The window's content is now `MacNavigatorSplit`, an `NSSplitViewController`
  with a native sidebar item and a detail item whose
  `automaticallyAdjustsSafeAreaInsets` is false. The Outline later became its
  inspector item ([005](005-live-resize.md)).
- The toolbar is an AppKit `NSToolbar` with a sidebar tracking separator. SwiftUI's
  bridged toolbar left the sidebar button on the detail side.
- Rejected: an AppKit split nested in the SwiftUI content. It reflowed live but the
  title and tab bar then ran above the sidebar.
- The sidebar list style imposed a 32 pt row pitch, so the navigator uses a plain
  list at 24 pt over the sidebar material.
- The outline has a fixed title and shows no current-heading mark; the accessibility
  selected trait remains. Source uses the reading size minus 3 pt, at least 10.

- The thin scroller is `apps/macOS/Kasumi/MacScroller.swift`. The library keeps the
  standard `NSScroller` and lets a host supply a class
  (`.markdownScroller(_:)`, `MarkdownReaderView.scrollerClass`). Rejected: the style
  inside the library, which forced Kasumi's look on every host, and replacing
  scrollers by searching the view tree, which breaks as tables are replaced.

## Validation

Reported by the Codex session on macOS 27.2.1 (logs under the ignored
`build/mac-native-verification/phase5/` and `phase6/`): toolbar, menu, shortcut and
divider each delivered 12–17 distinct reader widths with the top character unchanged;
tab open, reopen, close and restoration still worked. Claude reviewed two of its
full-resolution window captures. Not run: macOS 26, a physical mouse or keyboard.

## Refs

`apps/macOS/Kasumi/MacNavigatorSplit.swift`,
`apps/macOS/Kasumi/MacDocumentWindowController.swift`,
`apps/macOS/Kasumi/MacNavigator.swift`, `apps/Common/ReaderOutline.swift`.
