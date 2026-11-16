# 009 — Source editor and live preview: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-11-17 | Planned milestone 4 before implementation; retained reading as the default and Edit Source in the ellipsis menu. | `000-plan.md`; maintainer clarification during implementation |
| 2026-11-17 | Added safe source serialization, writable document sessions, document undo, debounced parsing and adaptive editor/preview composition. | Working tree; uncommitted |
| 2026-11-17 | Bounded preview layout/viewport painting and verified the iPhone editing and save flows. | Working tree; uncommitted |
| 2026-11-17 | Refined editor spacing, controls, transitions and focus continuity; verified the iPhone flows and accessibility text sizing. | [009.002](002-editor-experience.md); working tree, uncommitted |
| 2026-11-17 | Moved editing controls into native bars, restored soft edges, deferred the iPad split, reverted the layout worker and coalesced typing undo. | [009.003](003-native-editor-chrome.md); working tree, uncommitted |
| 2026-11-17 | Added the Markdown keyboard bar with heading, code, quote and link commands. | [009.004](004-markdown-keyboard-bar.md); working tree, uncommitted |

## Outcome and current state (as of 2026-11-17)

Documents open in reading mode. **Reader Actions > Edit** is the only
source-editing entry point, as requested because editing is an infrequent use.
While editing, the navigation bar shows the title, a Source/Preview toggle and
Done; Undo/Redo sit in the bottom bar. While typing, a bar above the keyboard
carries Undo, Redo, Heading, Hide Keyboard, Code, Quote and Link
([009.004](004-markdown-keyboard-bar.md)). All
widths use the toggle; the iPad side-by-side layout is deferred. Both panes run
under soft bar edges. Native document creation was not added. See
[editor experience](002-editor-experience.md) and
[native editor chrome](003-native-editor-chrome.md).
The editing surface has no ellipsis menu; Done restores reader actions.

The plain monospaced UIKit editor retains selection and scroll position across
pane switches. UIKit owns text entry, selection and marked-text composition;
the source model tracks visible text without replacing marked text storage.
Smart quotes/dashes, capitalization, autocorrection and spelling correction are
turned off. Undo/Redo controls and Command-Z/Shift-Command-Z use the document
undo manager. Typing coalesces into one undo step per burst, and undo reveals the
changed range. UITextView's separate
undo stack is disabled so its lifetime does not control document history.

`ReaderDocument` now conforms to writable `Document`; the app declares the Editor
role. SwiftUI owns coordinated saves and document lifecycle. Undo registration
marks changes for autosave. A write snapshot captures current source directly,
independently of the preview. Background parsing coalesces edits with a 200 ms
cadence and discards obsolete revisions. The hidden preview skips layout and
catches up when shown. Source-only replacements do not crossfade.
Export stays disabled while the parsed snapshot is behind the source, preventing
export of a stale revision.

The public `DocumentSource` value retains original bytes, detected encoding and
BOM. No-op writes preserve exact bytes; edits preserve UTF-8, BOM-marked UTF-16
byte order, or the existing GB18030 fallback. Scalar comparisons distinguish
canonically equivalent spellings. Lossy-decoded sources stay readable but their
Edit Source action is disabled; serialization also refuses edits to such sources.
Conversion must round-trip exactly before writing. Markdown and plain-text
extensions retain their respective parsing behavior and relative resource base.

Key source files:

- `Sources/KasumiMarkdown/DocumentDecoding.swift`
- `apps/iOS/Kasumi/ReaderDocument.swift`
- `apps/iOS/Kasumi/SourceEditor.swift`
- `apps/iOS/Kasumi/ReaderScreen.swift`
- `apps/iOS/Kasumi/ReadingSurface.swift`
- `apps/iOS/Kasumi/KasumiApp.swift`
- `apps/iOS/Info.plist`
- `Tests/KasumiMarkdownTests/TextDocumentTests.swift`
- `fixtures/SourceEditing.md`

Frozen expectations in `fixtures/reference/` were not changed.

## Deviations from plan

- Initial runtime inspection found Done overflowing the iPhone bottom toolbar. Moved the
  compact Source/Preview switch above the content and retained Undo/Redo beside
  Hide Keyboard in the native keyboard accessory.
  The subsequent [experience refinement](002-editor-experience.md) supersedes
  this arrangement with navigation-bar Done and one editor row.
- An interim change drained preview revisions through one layout slot so
  workers would not accumulate during typing. That only mattered for the iPad
  split; it was reverted with the split in
  [009.003](003-native-editor-chrome.md), keeping the original cancel-and-respawn
  worker.
- The iPad side-by-side layout was deferred in
  [009.003](003-native-editor-chrome.md) after it had compiled but never run.
- GB18030 supports supplementary Unicode, so the proposed unrepresentable-scalar
  test was replaced with an actual supplementary-character round trip.

## Validation

- `make app`: passed for iPhone 18 Pro / iOS 27.2, including the final editor
  changes. An initial build failed on optional chaining left over from the
  read-only snapshot; corrected before the successful builds. The build emits
  the existing App Intents metadata warning because this app has no App Intents.
- `make test FILTER='DocumentSourceTests|textDecoder|forcedLegacy|lossyDecoding'`:
  six tests passed on macOS. Covers original bytes, Unicode normalization edits,
  UTF-8 BOM, UTF-16LE/BE, GB18030, supplementary characters and refused lossy
  writes. The initial `DocumentSourceTests` run failed because its test incorrectly
  expected GB18030 to reject a supplementary scalar; the corrected round trip
  passed on both platforms.
- `make test-ios FILTER=DocumentSourceTests`: three Swift Testing tests passed
  on iPhone 18 Pro / iOS 27.2. XCTest's separate zero-test banner is not the
  Swift Testing result.
- Installed/launched with `make launch-sim`; preflight passed. Used `sim-use` for
  device interaction. No iPad simulator was launched.
- On iPhone, opened `fixtures/SourceEditing.md`, entered editing from the ellipsis
  menu, replaced the source with Markdown containing CJK and emoji, and inspected
  the rendered heading and bold text. Verified toolbar undo/redo after switching
  to Preview, keyboard Command-Z/Shift-Command-Z, Source/Preview switching with
  the keyboard visible, Done, and source scroll-position restoration. A marker
  inserted after remounting appeared in the expected paragraph.
- Closed the edited document, inspected its saved bytes, reopened it through the
  file URL, and checked the full source accessibility value for the saved marker.
  An initial file-URL open used a stale simulator container path after reinstall
  and failed; refreshing `simctl get_app_container` resolved it.
- On the final app build, opened a temporary UTF-16LE `.txt` containing CRLF, CJK
  and emoji. Visually verified literal Markdown characters in the plain-text
  preview. Typed an ASCII suffix and closed directly from the keyboard in a
  `sim-use` batch. Disk bytes exactly matched the expected text with the original
  UTF-16LE BOM and CRLF, including the final suffix.
- `git diff --check`: passed. Screenshots and command logs were inspected locally
  and are not retained as repository evidence. Changes remain uncommitted.

## Open questions

- The iPad side-by-side layout is deferred. iPad editing (the toggle, the
  inspector while editing, window resizing) has not been run.
- Real CJK IME composition, external-file conflicts, read-only file providers,
  physical-device saves and iCloud coordination were not exercised.
- Whole-document parsing/layout remains synchronous inside background workers.
  Large-document latency and memory have not been measured. Source/preview
  scrolling is independent, and syntax highlighting is outside this milestone.
