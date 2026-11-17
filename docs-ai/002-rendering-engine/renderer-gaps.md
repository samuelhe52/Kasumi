# Renderer gaps

Living list of known `KasumiMarkdown` limitations. Remove an item in the commit
that fixes it; add one when a limitation is found and not fixed.

- Text: right-to-left paragraphs fall back to Core Text (no bidi painting in
  the paragraph engine); `unicode-linebreak` differs from 59 of 7,654 Unicode 15
  test vectors; characters missing from every installed font have no defined
  fallback; hyphenation language is automatic only (US English for ASCII);
  hyphenation splits camelCase and brand names ("Kasum-iMarkdown", "ma-cOS").
- Fonts: the CJK faces the presets use aren't installed on iOS until a client
  downloads them; without them, Songti falls back to Noto Serif SC/TC when
  registered, then PingFang. The open substitutes have no tuned face table, so
  their heavy, Fangsong and Xihei faces stay generic. See
  [005](../005-cjk-font-availability/000-plan.md).
- Profiles: punctuation strategy and subscript shift are stored but not
  applied. The profile file format is a nonstandard line format; moving to
  standard TOML is planned.
- Themes: no syntax highlighting, no custom theme files; chrome colors are kept
  but not fully applied. On iOS, the Classic theme's system colors resolve to
  UIKit's semantic colors, so it differs slightly from macOS.
- Math: limited LaTeX coverage beyond the tested cases. `\[...\]` display math
  is recognized only when `\[` opens a line and `\]` ends one, so mid-line
  `\[x\]` stays an escaped bracket, while a line wrapped in escaped brackets
  becomes math; `\(...\)` can't span lines.
- Diagrams: no rich HTML labels; syntax outside the tested corpus may be
  rejected; no links or selection inside diagrams.
- Tables: document-based exports fit every column to the page and may still wrap
  heavily at very narrow widths. Snapshot image exports of a scrollable
  `RenderedDocument` capture its initial table viewport. Reader scrolling is
  presentation state, separate from the immutable snapshot. See
  [adaptive tables](005-table-layout.md) for behavior and validation limits.
- Export: pagination details, PDF links, footnote edge cases, HTML/SVG images.
  Long PNG/JPG require a complete bitmap, bounded by a configurable 128 MiB raw
  pixel default and 32,768 pixels per axis. This does not cap total process memory.
  Layout and ImageIO finalization are synchronous cancellation boundaries. See
  [008](../008-reader-export/001-action.md).
- Drawing: tile drawing is serialized by a lock in `RenderedDocument`, because
  Core Text line objects are shared between tiles and Apple limits each to one
  thread at a time.
- Reflow: default/full snapshots typeset the complete document. The opt-in
  viewport mode measures nearby text paragraphs with overscan, leaving indexed
  height estimates for offscreen paragraphs. Scroll/navigation requests refine
  immutable snapshots while preserving a semantic anchor. Text metadata still
  scales with document length, and one huge paragraph still breaks in full.
  Documents with tables or attachments currently fall back to exact full layout.
  Resize requests are coalesced by the reader. `DocumentReflowSession` retains
  attributed text and measured input, paragraph items, and semantic metadata
  between widths; active break candidates accumulate totals rather than
  rescanning each line. Plain paragraphs
  skip decoration processing after preparation finds no candidates. Image/math
  paragraphs bypass preparation reuse to preserve width-dependent attachments
  and independent Core Text ownership. Session-prepared undecorated paragraphs
  materialize fragment drawing/caret data per accessed line under the snapshot
  lock. Decorated/unprepared paragraphs remain eager. Exact line breaking and
  logical CTLines build only for measured paragraphs in viewport mode. First-use
  painting incurs materialization, and old snapshot disposal and active Find can
  add UI-thread cost. See
  [reflow preparation](006-reflow-preparation.md), [metadata reuse](007-reflow-metadata.md),
  [lazy fragments](008-lazy-fragments.md), [viewport layout](009-viewport-layout.md), [live reflow](../004-ios-reader/006-live-reflow.md)
  and [reader anchor lifecycle](../004-ios-reader/007-reflow-anchor-lifecycle.md).
