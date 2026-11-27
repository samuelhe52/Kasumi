# 008.003 — Mac export and copy

## Context

The Mac app had a PDF save command but not the iOS export controls. The
maintainer requested those controls and whole-document copy commands in the
menu bar, without adding toolbar controls or RTF.

## Change

- **File ▸ Export…** and **File ▸ Print…** require a current preview, no pending
  Source edit, and no other output job. The export form is an AppKit document
  sheet. Its save panel chooses a destination before the worker starts. The
  sheet follows Mac conventions rather than the iOS X button: Cancel and
  Export… sit at the bottom trailing edge, sliders set layout width, font size,
  and JPG quality, a segmented control sets resolution, and the sheet fits its
  content.
- `apps/Common/ReaderExportOptions.swift` owns the options, defaults, format
  guidance, and rendering setup used by both forms. PDF and image font sizes
  remain independent. The Mac and iOS apps own their destination UI separately.
- `apps/macOS/Kasumi/MacExport.swift` owns progress, cancellation, and inline
  errors. Export resolves the parsed document, title, and current appearance at
  render start without resetting the chosen font size. An external save can
  reload the reader while the sheet is open, so Export… stays disabled until
  the reload's parse is current, and a change after the save panel closes ends
  in an inline error instead of writing the old revision. If the parent closes during destination
  selection, the save panel ends before the export sheet. The document's output
  lock lasts until its worker exits, even if the sheet is dismissed. The file
  exporter publishes completed output atomically.
- **Edit ▸ Copy Document As** reads the whole document, not the selection. Markdown uses
  the latest source; plain-text files stay verbatim unless parsed as Markdown.
  Markdown plain-text copy uses the current parse when available. Pending
  Source edits and stale previews use a detached parse and serialization; a
  newer Copy Document As/Copy Path request or a pasteboard change invalidates the result.
  `DocumentExport.plainText` serializes parsed blocks without layout, preserving
  list and quote structure, numbered footnotes, image alt text, and TeX source.
  Empty list items keep their markers. Display math inside a paragraph loses
  its quote and list source prefixes, as a math block does.
- Image alt text expands math placeholders only, so code in alt text keeps a
  literal `==` instead of becoming highlight markup. This applies to the
  reader and outline as well as plain-text copy.

The submenu was first named Copy As and sat between Copy and Paste. On 2026-11-27 it became **Copy Document As** in its own Edit section after Select All, because Edit ▸ Copy acts on the selection and the whole-document scope needed a distinct label and a separate group. Validation entries below that mention "Copy As" refer to the earlier label.

## Original feature validation

- `make test FILTER=PlainTextExportTests`: 7 passed.
- `make app-check-mac` and `make app-check`: both built successfully without
  booting a simulator.
- A macOS accessibility smoke check observed the Copy As entries and Print,
  invoked Export, and opened the attached form and native save panel. It did not
  write a destination file, exercise clipboard output, or cancel active rendering.

## Review follow-up validation

- Initial builds failed on the image alt-text `joined()` overload. After making
  the string join explicit, `make test FILTER=PlainTextExportTests` passed 11
  tests, `make test FILTER=DocumentTests` passed 20, and
  `make test FILTER=ReferenceSemanticsTests` passed 6.
- `make app-check-mac` and `make app-check` both built successfully. No
  simulator was booted.
- On macOS 27.2.1, an accessibility smoke check observed the Copy As entries
  and enabled Print, opened Export and the native save panel, verified that
  the host Cancel button was disabled, then cancelled the panel and closed
  Export. It observed Print enabled again. It did not force the parent window
  closed with the panel open, render or print a file, change theme, or write to
  the pasteboard.

## Second review follow-up validation

- `make test FILTER=PlainTextExportTests` passed 13 tests, including the
  empty-item, alt-text, and paragraph display-math cases.
  `make test FILTER=DocumentTests` passed 20, and
  `make test FILTER=ReferenceSemanticsTests` passed 6.
- `make app-check-mac` built successfully. The maintainer checked the reworked
  sheet in the running Mac app. The external-reload path was not exercised.
