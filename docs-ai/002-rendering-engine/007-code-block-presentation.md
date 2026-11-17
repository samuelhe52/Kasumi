# 002.007 — Code-block presentation and copying

## Context and plan (2026-11-17, before implementation)

Status: Implemented; style/control ownership revised by [002.008](008-code-block-style-boundary.md). Follow-up to [syntax highlighting](006-syntax-highlighting.md).
The maintainer requested a better reader code-block experience, specifically
rounded corners, a language label, and a copy action. Continue in the existing
worktree and validate without launching or driving a simulator.

Use the existing theme's code background with a 10 pt corner radius and a compact
header. Place the language at the leading edge and a native Copy button at the
trailing edge; reserve enough height for a 44 pt touch target. Keep current code
wrapping/indentation behavior. Unknown and unlabeled code still gets the panel
and copy action; its highlighting fallback remains plain.

Expose immutable code-block geometry and source through `RenderedDocument` so
the reader can overlay native controls without putting buttons or captions into
semantic document text. Preserve the parser's complete code literal for copying,
including indentation, blank lines, and trailing newlines; do not copy fences or
decorations. Show brief copied feedback and provide accessibility actions. Text
selection/link gestures must yield to controls. File exports keep the rounded
panel and caption, with no painted copy-button imitation.

Language captions are decorative Core Text drawing. Keep headers with the first
code line and bottom padding with the final code line in paginated export; allow
long blocks to split between ordinary lines. Use bounded caption geometry at
narrow widths and truncate unusually long labels instead of overlapping controls.

## Planned validation

- Extend focused rendering/API tests for geometry, exact copy source, exclusion
  of captions from search/selection, rounded corner pixels, caption ink, and
  header/first-line pagination. Reuse existing syntax/export regressions.
- Render authored light, dark, and narrow fixtures headlessly and inspect images
  and PDF pages. No frozen expectations change unless a covered behavior changes.
- Compile the iOS app for a generic device with signing disabled; do not launch
  any simulator/device. Native tap, pasteboard, and VoiceOver runtime checks stay
  explicitly unverified in this task.

## Outcome (2026-11-17)

Implemented on `feat/syntect-highlighting`.

- `Sources/KasumiMarkdown/CodeBlockLayout.swift` defines the immutable public
  `RenderedCodeBlock` metadata and internal caption drawing. The reader selects
  a 10 pt radius, 44 pt caption row, 14 pt horizontal code inset, and 12 pt bottom
  padding. [002.008](008-code-block-style-boundary.md) makes these client choices:
  library defaults are square, caption-free rectangles; captions are optional.
  Enabled captions use readable language names, Code for unlabeled blocks, and
  truncation when width is limited.
- `Document.swift` retains the complete parsed code literal in `codeSource`.
  `RenderedDocument.codeBlocks` exposes original source/language plus generic
  block/content/optional-caption geometry. [002.008](008-code-block-style-boundary.md)
  removes the initial button-frame and UI-color fields from the library API. Source is separate from the
  displayed text, which retains the prior terminal-newline trimming behavior.
  Captions are excluded from semantic text, search, and selection.
- `DocumentLayout.swift` paints the existing theme background with rounded corners
  and draws captions separately from body paragraphs. Pagination groups keep the
  header with the first code line and bottom padding with the last; long blocks
  still break between lines. Continued PDF pages do not repeat the caption.
- `apps/iOS/Kasumi/ReaderCodeCopyButton.swift` overlays a native button in each
  header. It writes the complete code literal to the pasteboard, changes to a
  checkmark/Copied state for 1.5 seconds, and announces success. At very narrow
  widths the title is omitted, retaining the icon and accessibility label.
  Empty blocks have a disabled copy action. Repeated taps restart feedback.
- `ReadingSurface.swift` installs the controls, exposes both document text and
  native buttons to accessibility, and supplies code-copy custom actions on the
  document text element. Vertical drags can cancel button touches.
  `ReaderTextInput.swift` excludes controls and their descendants from the
  reader's link/selection gesture admission.
- The reader's document exports explicitly select rounded panels and compact
  captions; Copy remains an interactive UIKit control and is not painted into
  PNG/JPG/PDF. Library exports use the caller's `CodeBlockStyle`. The authored fixture now includes
  the Rust derive/Point example. Frozen reference expectations are unchanged.

## Initial implementation validation

These checks preceded the style-boundary refactor. Current validation is in
[002.008](008-code-block-style-boundary.md).

Performed on macOS 27.2.1 arm64. No simulator or device was launched or driven.

- `make test FILTER='CodeBlockPresentationTests|CodeSyntaxTests'`: all ten tests
  passed. New tests cover exact tabs/Unicode/blank-line/trailing-newline copy data,
  unlabeled/unknown/empty blocks, caption exclusion from semantic text and search,
  header/body/control geometry at 60/180/360 px, light/dark rounded-corner and
  caption pixels, and multi-page code pagination without whole-block scaling.
- Focused renderer/API/export regressions (`make test FILTER=...`, adding the new
  suite to the selection documented in [002.006](006-syntax-highlighting.md)):
  51 tests passed in four suites, with no skips.
- `make app-check`: unsigned generic iOS device build succeeded, including the
  new UIKit button, accessibility container, and gesture changes. Xcode emitted
  its metadata-extraction warning because the app has no AppIntents dependency;
  there were no compilation errors.
- `make render` on `fixtures/SyntaxHighlighting.md`: inspected 800 px One Light
  and One Dark PNGs, a 360 px One Dark PNG, and both pages of a One Light PDF
  rendered headlessly with PDFKit. Panels are rounded, captions remain above the
  code, and narrow lines wrap without entering the header. PDF text extraction
  passed five code-phrase checks. These images/PDF/logs are local, not retained.
- `git diff --check` passed.

## Corrections and limits

The first new tests found that an empty caption rectangle at 60 px could extend
into button geometry; its origin is now clamped before computing its width.
The initial pixel sampler also incorrectly inverted bitmap row coordinates; it
now samples the same top-down coordinates as the renderer. The corrected tests
passed before the visual inspection and broader regression run.

Native tapping, drag cancellation, pasteboard contents, feedback timing, and
VoiceOver behavior were not exercised at runtime under the no-simulator constraint.
Exact copy payloads and public geometry are covered headlessly; the app's control
wiring was compiled. No source-editor behavior was changed.
