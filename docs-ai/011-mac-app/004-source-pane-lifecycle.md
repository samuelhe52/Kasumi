# 011.004 — Source pane lifecycle

## Context

After switching from Source back to Reader, an external Markdown file drop could
reach the hidden `NSTextView`, insert the file path, and trigger in-place autosave.
The document window used opacity and SwiftUI hit testing to switch panes.

## Decision

Retain each pane's native view instance for the document session and attach only
the active pane to the window. Preserve source-line navigation on mode changes,
the Reader's finer scroll position on a round trip without edits or scrolling,
and the handoff of Find. Create Source on first use. Keep the change in the Mac
app, where the native editor's drop handling caused the edit.

`MacWorkspaceController` retains the hosting controllers and attaches one child
view at a time. The reader proxy scope lives inside the Reader host so the session
can still route outline, line, and Find commands to it.

## Validation

On macOS 27.2.1, a native app probe used a disposable Markdown file and an
external AppKit file drag. The Reader and Source view identities survived repeated
switches, and only the active view belonged to the window. A round trip with no
source changes preserved the Reader's 849 pt scroll offset. Moving Source scrolled
the Reader to the mapped position. Source took keyboard focus, the open Find bar
followed the active pane in both directions, and typing undo and redo survived a
round trip. An external file drop over Reader after visiting Source was rejected,
with no modified state, tab, or file change.

`make app-check-mac` and `make test FILTER=MarkdownReaderAppKitTests` passed. The
runtime checks used the local OS version and did not cover macOS 26.
