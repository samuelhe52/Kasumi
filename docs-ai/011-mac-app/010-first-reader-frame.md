# 011.010 — Present documents after their first reader layout

## Context

A frame-by-frame screen recording showed AppKit selecting the new document before
its asynchronous parse and viewport layout completed. The new window briefly
showed a progress indicator, then a blank page, then the rendered document.

## Change

For a new document opening in Reader mode, `MacDocumentWindowController` lays out
the attached content before ordering its window or inserting it into a native tab
group, using the prospective tab target's frame. It waits at most 500 ms. A slower
document then appears with its progress indicator, and a layout that never
reports cannot leave the document open without a window. Source-first windows and
AppKit restoration keep their existing paths.

The target is looked up in `showWindow(_:)`, before AppKit's open completion
releases the request and its source, and held weakly. It is looked up again at
display if it is gone or there was none: files opened together at a cold launch
see no window until the first one is shown.

`MarkdownReader` reports the first installed viewport through app-only SPI. A
reading-position callback is not sufficient: an empty document still installs a
viewport but has no reading position. The readiness signal avoids a fixed delay
or a synchronous parse/layout on the main thread.

## Validation

On macOS 27.2.1, an earlier version without the limit was screen-captured: a cold
open and a new native tab both showed rendered text on their first captured frame.
The current Release build was checked through window bounds only: three files
opened together at a cold launch left one window on screen, an empty file opened
as a tab, and a file with 250,000 sections replaced the current tab about 0.8 s
after the open request. Whether that file reached the 500 ms limit was not
recorded. macOS 26 and restored windows were not checked.
