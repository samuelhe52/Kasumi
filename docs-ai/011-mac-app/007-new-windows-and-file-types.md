# 011.007 — New windows and file types

## Context

The plan recorded no New Window command and no ⌘N as a maintainer choice. `7986785`
later added New Window and New Tab without updating it. The reason for the reversal
was not recorded.

The bundle also declared `.mdown` and `.mkd`, and the reader treats `.text` as plain
text, but the navigator listed only `.md`, `.markdown` and `.txt`.

## Change

- New Window (⌘N) opens an untitled document in its own window, outside any tab
  group. New Tab (⌘T) and the tab bar's plus button add one to the requesting window.
  With no document window in the responder chain, New Tab opens a separate window.
  All open in source mode. Version browser windows don't accept new tabs.
- The navigator's extensions are `md`, `markdown`, `mdown`, `mkd`, `txt` and `text`.
  Links and drops share this list, then fall back to the file's content type.
- The plan's Panes, Keys and decision rows were corrected in place.

## Validation

Not built, run or tested for this record, at the maintainer's request. One
`make app-check-mac` attempt failed while unrelated edits were in progress in the
same working tree; the errors were not examined. The commands above were described
from source.

## Refs

`7986785`; `apps/macOS/Kasumi/MacCommands.swift`,
`apps/macOS/Kasumi/MacDocumentController.swift`,
`apps/macOS/Kasumi/MacDocumentWindowController.swift`,
`apps/macOS/Kasumi/MacFolderListing.swift`.
