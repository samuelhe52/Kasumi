# 011 — Native Mac app: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-11-24 |
| Origin | Maintainer asked for a Mac version with tab navigation, a trailing outline, a leading navigator, a source mode, proper Find and standard Mac keyboard ergonomics. Decisions were made in an interactive plan review on 2026-11-24. Rewritten the same day, after the first version, built on SwiftUI `DocumentGroup`, proved unable to open files as tabs reliably. The native window design below was written before its implementation; the panes, source mode, Find and keys describe code that already existed. |
| Related | [iOS reader](../004-ios-reader/000-plan.md), [reader interactions](../007-reader-interactions/000-plan.md), [source editor](../009-source-editor/000-plan.md), [native reader views](../003-public-rendering-api/004-native-reader-views.md) |

## Background

The library already ships an AppKit reader (`Sources/KasumiMarkdownUI/AppKit/`)
with native `NSTextFinder` Find, and the SwiftUI `MarkdownReader` wrapper supports
macOS. The iOS app's document model (`apps/iOS/Kasumi/ReaderDocument.swift`) and
`Document` adapter (`apps/iOS/Kasumi/ModernReaderDocument.swift`) are mostly
platform-neutral. There is no Mac app target.

## Goals

- A native macOS app (SwiftUI + AppKit, not Mac Catalyst) that opens Markdown and
  text files, one document per window, with windows grouped as native macOS tabs.
- Opening a file from any route adds a native tab without a visible flash, and
  opening a file that is already open selects its tab.
- A compact leading navigator with Recent and Workspace tabs, and a trailing
  compact outline.
- A per-document source mode with a plain `NSTextView` editor that keeps the
  reading place when switching modes.
- Find that works the same in the reader and the source, from the menu bar,
  regardless of which pane has focus; Replace only in the source.
- A complete menu bar with standard Mac keys (below).

### Non-goals

Mac App Store distribution, sandboxing, an export options sheet (Print and Export
as PDF use the standard panels), Open URL import, a Quick Look extension, and any
change to iOS or iPad behavior.

## Design / approach

### Targets and folders

- New target `KasumiMac` in `apps/iOS/Kasumi.xcodeproj`, deployment target
  macOS 26, sources in the folder-synchronized `apps/macOS/Kasumi/`.
  Not sandboxed; hardened runtime on for later Developer ID notarization.
- `apps/Common/`: platform-neutral app code moved out of
  `apps/iOS/Kasumi/` and compiled into both the iOS app and `KasumiMac`
  (`ReaderDocument`, `ReaderAppearance`,
  `SourceFormatting`, `ReaderOutline`, the platform-neutral part of
  `ReaderState`, and appearance/font files where they compile on both). UIKit
  pieces stay in `apps/iOS/Kasumi/`.
- Makefile targets for building, running and checking the Mac app.

### Documents, windows and tabs

AppKit owns documents and windows; SwiftUI draws their content. Types in
`apps/macOS/Kasumi/`:

| Owner | Responsibility |
| --- | --- |
| `MacDocumentController` | Remembers the source window of an explicit open until it completes. AppKit keeps display, deduplication, Recents and reopening. |
| `MacDocument` | `NSDocument` with synchronous reads and writes; owns the `ReaderDocument`, session, file watch and teardown in `close()`. |
| `MacDocumentWindowController` | Window, hosting controller, one-time tab placement, menu actions and validation. |
| SwiftUI | Reader, panes, toolbar and Settings content. |

- The window joins its tab group in the first `showWindow(_:)`, before `super`.
  AppKit's open, untitled and duplicate routes call it before display, so this is
  the one point that covers them. Windows that are visible, already grouped or
  showing an old version are never moved. AppKit restores restored groups.
- An explicit open (navigator or link) targets its source window. Other opens
  target the frontmost document window at first display, not at request time: a
  cold launch with several files would otherwise see no window for each request.
  If the source has closed, the frontmost window is used, or a new window when there
  is none.
- Link fragments go to the opened document's session from the open completion.
- The editor receives the document's undo manager explicitly. Edited state compares
  text with the saved baseline (changed during implementation; see
  [001](001-action.md)). Typing groups end before a save snapshot, and the watcher
  reverts only an unedited document.
- A failed read leaves the model unchanged. A revert or rename keeps the session.
- Menus are AppKit actions routed through the responder chain.

### Panes

- Navigator: leading native sidebar ([003](003-window-split-and-panes.md)) with compact
  Recent and Workspace tabs: the newest eight documents, and the files in the
  active file's folder (`.md`, `.markdown`, `.mdown`, `.mkd`, `.txt`, `.text`, name order). Clicking opens or
  activates the file's tab.
- Outline: trailing inspector reusing `ReaderOutline` with compact, single-line
  secondary-text headings under a fixed title.
- Pane visibility is shared across tabs so switching tabs does not flip panes.

### Source mode

`NSTextView` editor (monospaced, plain text, reader paper color). Edits go
through `ReaderDocument.setText(_:undoManager: nil)`; the text view owns typing
undo. Formatting commands reuse `SourceFormatting` and add bold/italic toggles.
Switching modes keeps the reading place through two reader APIs on
`MarkdownReaderProxy`: the first source line of the block at the top of the
viewport, and scrolling to the block containing a source line, built on
`DocumentBlock.sourceLines`.

### Find

Edit ▸ Find items route through the active window controller to the
document's current pane: the reader's `performTextFinderAction(_:)`, or the
source `NSTextView` with `usesFindBar` and incremental search. The shared find
pasteboard carries the query across tabs and modes; an open find bar follows a
mode switch.

### Keys

| Menu | Commands |
| --- | --- |
| File | New Window ⌘N, New Tab ⌘T, Open ⌘O, Open Recent, Close Tab ⌘W, Save ⌘S, Revert, Show in Finder ⌥⌘R, Copy Path ⌥⇧⌘C, Paste as New Document ⇧⌘V, Export as PDF, Print ⌘P |
| Edit ▸ Find | Find ⌘F, Find and Replace ⌥⌘F (source only), Next ⌘G, Previous ⇧⌘G, Use Selection ⌘E, Jump to Selection ⌘J |
| Format (source) | Bold ⌘B, Italic ⌘I, Link ⌘K, Heading 1–6 ⌥⌘1–⌥⌘6, Code, Quote |
| View | Navigator ⌃⌘S, Outline ⌥⌘0, Source ⌘/, Actual Size ⌘0, Zoom In ⌘+, Zoom Out ⌘−, Full Screen ⌃⌘F |
| Window | Tab 1–8 ⌘1–⌘8, last tab ⌘9, next/previous tab ⇧⌘] / ⇧⌘[, ⌥⌘→ / ⌥⌘←, ⌃⇥ / ⌃⇧⇥ |
| Go | Next Heading ⌥⌘↓, Previous Heading ⌥⌘↑ |
| Kasumi | Settings ⌘, (appearance, spacing, fonts), Quit ⌘Q |

External links open in the default browser without a prompt; links to local
Markdown files open as documents.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Native window tabs | Maintainer choice over a custom in-window tab strip, which required reimplementing tab and window behavior. |
| `NSDocument` with an AppKit shell, not `DocumentGroup` | Maintainer dropped the wrapper. `DocumentGroup` shows a window before app code can place it: moving it afterwards flashed, and placing it only before display left standalone windows. |
| No `Document` or `ReferenceFileDocument` bridge on the Mac | In the first version the `Document` bridge deadlocked AppKit's synchronous conflict-recovery writes: `write` waited on a semaphore for a main-actor snapshot (reproduced standalone on macOS 27.2.1). `ReferenceFileDocument` avoided that but kept `DocumentGroup`'s display order. A native synchronous write needs no bridge. |
| Keep AppKit's default display, not `display: false` | AppKit's bookkeeping and coalesced opens stay intact. A missed source only picks another tab group; a missed presentation would leave a document without a window. |
| AppKit menus, not SwiftUI `Commands` | Without `DocumentGroup` a SwiftUI shell supplies no document commands, and focused values in hand-made windows are not a documented contract. |
| Closed source window uses the frontmost document window, or a new window when there is none | Maintainer choice. |
| New Window ⌘N and New Tab ⌘T | Reverses the original maintainer choice of no New Window command and no ⌘N; see [007](007-new-windows-and-file-types.md). |
| ⌘W closes the tab; ⌘Q quits normally | Maintainer choice. Closing the last tab closes its window and leaves the app running. |
| Native AppKit target, not Catalyst | Catalyst would use the UIKit reader and drop the existing AppKit reader, its `NSTextFinder` Find and Mac scrolling. |
| macOS 26 minimum | Maintainer choice, once no macOS 27-only API was needed. |
| Not sandboxed, Developer ID only | Maintainer choice. Relative images and the folder navigator read sibling files without folder grants or security-scoped bookmarks. Mac App Store distribution is out of scope. |
| Navigator: recents plus the active file's folder | Maintainer kept the proposed default over a folder tree with Open Folder, or recents only. |
| Mode switch keeps the reading place | Maintainer kept the proposed default; it adds two public reader APIs that iOS can adopt later. |
| ⌘1–⌘9 select tabs; panes on ⌃⌘S and ⌥⌘0, source on ⌘/ | Maintainer kept browser-style number keys for tabs and asked for other pane and source keys. ⌃⌘S is the system sidebar key, ⌥⌘0 matches the iPad outline key, and ⌘/ was chosen for source mode. The initial proposal used ⌘1/⌘2/⌘3. |

## Validation and acceptance criteria

- `KasumiMac` builds from the command line; the iOS app still builds
  (`make app-check`), and package tests for any new reader API pass.
- Focused tests for the source-line mapping and for any non-UI logic added
  (navigator folder listing, formatting toggles).
- Before the full migration, a small build shows that first display, restoration,
  toolbar and inspector hosting, and Settings work.
- No flash and the right tab group from: navigator, link, Open, Recent, Finder,
  the tab bar's plus button, Paste as New Document and Duplicate; also with a source
  closed mid-open, repeated and symlinked opens, several files at a cold launch, and
  minimized, dragged-out and full-screen windows.
- Undo to clean across a save; continuous typing through an autosave followed by an
  external write loses no text. Save Anyway, Revert and Save As each after in-place
  and atomic external writes, checked by disk bytes. Versions, Duplicate, rename and
  move, restoration and drafts.
- ⌘W closes only the selected tab; ⌘Q quits with edited documents and drafts kept
  or reviewed as AppKit does.
- Every key in the table with its enabled state in Reader, Source, Find and Settings;
  pane visibility across tabs; mode switch keeps the place.
- Closing a tab ends its file watch and frees its document.

## Amendments

- Updated 2026-11-24: Mac icon built with Icon Composer — see [002-native-app-icon.md](002-native-app-icon.md).
- Updated 2026-11-24: AppKit window split, live sidebar reflow and pane changes; the Panes and goals text was corrected in place — see [003-window-split-and-panes.md](003-window-split-and-panes.md).
- Updated 2026-11-24: Mode switching detaches the inactive pane from the window — see [004-source-pane-lifecycle.md](004-source-pane-lifecycle.md).
- Updated 2026-11-25: Reflow within the resize layout pass and move the Outline into the native split — see [005-live-resize.md](005-live-resize.md).
- Updated 2026-11-25: Scroll the panes beneath the header and tint the sidebars — see [006-paper-chrome.md](006-paper-chrome.md).
- Updated 2026-11-25: New Window and New Tab commands, and one list of file types; the Panes, Keys and decision text was corrected in place — see [007-new-windows-and-file-types.md](007-new-windows-and-file-types.md).
- Updated 2026-11-25: Keep pane preferences shared but defer changes to an unselected tab's split until selection — see [009-selected-tab-panes.md](009-selected-tab-panes.md).
