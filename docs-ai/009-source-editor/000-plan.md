# 009 — Source editor and live preview: Plan

| Field | Value |
| --- | --- |
| Status | Implemented (iPad runtime validation deferred by instruction) |
| Anchor date | 2026-11-17 |
| Origin | Maintainer requested reader milestone 4, permitting iPhone simulator use and prohibiting iPad simulator launches; clarified that editing is rare and its entry point belongs in the ellipsis menu. |
| Related | [Goal](../001-library-and-reader/goal.md), [roadmap](../roadmap.md), [reader](../004-ios-reader/000-plan.md) |

## Background

The document app currently opens Markdown and text through a read-only document
session. Milestone 4 adds plain source editing while retaining the existing
rendered reader as the preview.

## Goals

- Edit the open file in place using the native writable DocumentGroup session,
  autosave, and document undo/redo.
- Keep reading as the initial mode; offer Source/Preview switching. A
  side-by-side layout on wide iPad windows was planned and later deferred; see
  [009.003](003-native-editor-chrome.md).
- Keep typing responsive through debounced, background parsing and the existing
  bounded rendering pipeline. Discard stale preview results.
- Preserve unchanged bytes and the original encoding/BOM after editing. Reject
  unrepresentable saves and keep lossy-decoded files read-only.
- Retain source selection and scroll position when switching between modes.

### Non-goals

Syntax highlighting, synchronized source/preview scrolling, and incremental
parsing/layout are outside this milestone. (Formatting commands were also listed
here until the maintainer added a Markdown keyboard bar; see
[009.004](004-markdown-keyboard-bar.md).)

## Design / approach

- Extend the library's decoding layer with a public, UI-independent
  `DocumentSource` value (proposed) that exposes decoded text and safe re-encoding.
- Convert `apps/iOS/Kasumi/ReaderDocument.swift` to `Document`, with immutable
  read/write snapshots, immediate source state, undo registration, and one
  coalescing background preview parser. Save current text independently of the
  preview debounce.
- Add `apps/iOS/Kasumi/SourceEditor.swift`, a plain monospaced UIKit
  editor with native text entry/selection, composition-aware publication, and
  document undo commands. Compose editor/preview in `ReaderScreen.swift`.
- Skip preview layout in `ReadingSurface.swift` while the preview is hidden;
  stale results are discarded. Source-only replacements do not crossfade on each
  edit. (Corrected by [009.003](003-native-editor-chrome.md): an interim
  single-slot drain loop was reverted.)
- Change the document role to Editor; preserve the document browser and imports.
  Use soft toolbar edge effects throughout.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Writable DocumentGroup | Retains native autosave, coordination and file conflict handling; direct writes from editor callbacks would bypass those services. |
| Edit Source only in the ellipsis menu | The maintainer treats editing as an edge case. Documents open in reading mode; editing controls appear only after explicit entry. |
| Separate source and preview revisions | Saving must capture the latest typing even while parsing/rendering is pending. |
| Preserve encoding; refuse lossy edits | Silent conversion or writing replacement characters would change files beyond the user's edit. |
| Plain native text view | Supports ordinary selection, Unicode composition and keyboard editing without introducing a syntax engine. |
| Independent pane scrolling | Source-to-layout mapping is not currently a public contract; approximate synchronized scrolling would be misleading. |

## Validation and acceptance criteria

- Focused package tests for exact-byte no-op writes, UTF-8/BOM, UTF-16 byte order,
  legacy encoding, supplementary Unicode and refused lossy writes.
- App build for iPhone simulator; runtime source editing, preview, undo/redo,
  mode switching and disk persistence after closing/reopening.
- iPad split composition is implemented and compiled but no iPad simulator may
  be launched. Record that runtime validation limit explicitly.
- Preserve existing uncommitted work and leave changes uncommitted.

## Amendments

- Updated 2026-11-17: implemented; see [action and validation limits](001-action.md).
- Updated 2026-11-17: refined editor controls, spacing and pane continuity — see
  [editor experience](002-editor-experience.md).
- Updated 2026-11-17: native bar editing controls, soft edges restored, iPad split
  deferred, original layout worker, coalesced typing undo; goals and design
  corrected above — see [003-native-editor-chrome.md](003-native-editor-chrome.md)
- Updated 2026-11-17: Markdown keyboard bar (heading, code, quote, link); the
  formatting non-goal is corrected above — see
  [004-markdown-keyboard-bar.md](004-markdown-keyboard-bar.md)
