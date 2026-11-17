# Renderer gaps

Living list of known `KasumiMarkdown` limitations. Remove an item in the commit
that fixes it; add one when a limitation is found and not fixed.

- Text: right-to-left paragraphs fall back to Core Text (no bidi painting in
  the paragraph engine); `unicode-linebreak` differs from 59 of 7,654 Unicode 15
  test vectors; characters missing from every installed font have no defined
  fallback. Automatic hyphenation uses a bounded stopword heuristic; weak,
  unsupported and ambiguous/mixed-language samples fall back to US English.
  Choose an explicit language for reliable dictionary selection.
- Fonts: the CJK faces the presets use aren't installed on iOS until a client
  downloads them; without them, Songti falls back to Noto Serif SC/TC when
  registered, then PingFang. The open substitutes have no tuned face table, so
  their heavy, Fangsong and Xihei faces stay generic. See
  [005](../005-cjk-font-availability/000-plan.md).
- Punctuation: opt-in spacing/folding uses local Han context and skips paragraphs
  containing kana/Hangul; Han-only Japanese is ambiguous under this script
  heuristic. Code, math, links, numeric separators and footnote markers stay literal.
- Themes: custom theme files are library/CLI-only; the reader selects built-ins.
  The chrome keys `column_divider`,
  `sidebar_background` and `tab_active_background` are defined in bundled themes,
  but no code reads them. On iOS, the Classic theme's system colors resolve to
  UIKit's semantic colors, so it differs slightly from macOS.
- Code highlighting: explicit supported fence languages only; unlabeled/unknown
  blocks remain plain. Blocks above 256 KiB UTF-8, lines above 16 KiB excluding LF,
  language info above 128 bytes, and parse failures fall back to plain. The
  pure-Rust grammar bundle excludes some Oniguruma-only variants. See
  [002.006](006-syntax-highlighting.md).
- Math: limited LaTeX coverage beyond the tested cases. `\[...\]` display math
  is recognized only when `\[` opens a line and `\]` ends one, so mid-line
  `\[x\]` stays an escaped bracket, while a line wrapped in escaped brackets
  becomes math; `\(...\)` can't span lines.
- Diagrams: no rich HTML labels; syntax outside the tested corpus may be
  rejected; no links or selection inside diagrams.
- Tables: document-based exports fit every column to the page and may still wrap
  heavily at very narrow widths. Compact tables are centered; overflowing reader
  tables start at the left edge of the reading measure. Snapshot image exports
  of a scrollable `RenderedDocument` capture its initial table viewport. Reader scrolling is
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
  Eligible offscreen text, table cells and formulas use lightweight semantic
  placeholders; nearby tables refine together. Resource-dependent images and
  diagram fallbacks stay exact. A large visible table, giant attachment paragraph
  or diagram can still dominate construction. Placement and semantic-map assembly
  still visit the whole document on viewport requests; there is no persistent
  indexed block-placement tree yet. One screen of overscan buffers scrolling, and
  compatible results may publish after anchor movement only when the latest
  visible region is measured. Optional `prepareForScrolling(width:)` completes
  bounded text/table/math documents during idle time and retains one complete
  snapshot at the current width. Both reader hosts wait 200 ms after activity,
  cancel between batches and resume retained progress. The envelope is at most
  1,000 parsed blocks, 250,000 UTF-16 units, 4,000 units per block/cell and 64
  cells per table, excluding image/diagram resources. It trades memory and idle
  CPU work for complete coverage after readiness. Cold jumps, width changes,
  interrupted warmup and documents outside the envelope can still outrun
  viewport refinement; this does not establish UIKit tile presentation behavior.
  Resize requests are coalesced by the reader. `DocumentReflowSession` retains
  attributed text, measured input and semantic metadata between widths. Normal
  sessions also retain paragraph items; optional idle preparation releases these
  items after exact geometry becomes reusable, rebuilding them after a width
  change when needed. Idle batches skip unused attributed-text assembly. Active
  break candidates accumulate totals rather than rescanning each line. Plain paragraphs
  skip decoration processing after preparation finds no candidates. Image/math
  paragraphs bypass preparation reuse to preserve width-dependent attachments
  and independent Core Text ownership. Session-prepared paragraphs materialize
  fragment CTLines on access under the snapshot lock, keeping only the last
  fallback fragment per line. Line-local immutable paint references survive
  shared-cache eviction, preserving fast revisits. Single-glyph paints and
  endpoint-only carets use compact storage; paragraph factories share equal
  resolved colors in bounded snapshot-local palettes. Deferred fragment wrappers
  are projected from a shared immutable, tightly sized geometry array. Underline
  construction touches genuinely decorated lines while other lines stay lazy.
  Session-prepared measured paragraphs also reuse
  immutable source-range font/color/glyph/position and bounded natural caret
  values through a synchronized cache. Prepared paragraphs share a session-wide
  cache with an 8 MB cost hint and 8,192 entry hint, using separate paragraph
  namespaces; these hints exclude line-local paint and are not absolute process
  bounds. The abandoned shared-cache-only prototype caused substantial return
  latency regressions. [Compact preparation](024-compact-idle-preparation.md) now
  restores return latency in the measured workloads, but first-traversal p99 is
  still 0.6–2.2 ms higher. The standalone 200k engine peaks near 140 MB footprint;
  the whole native Mac fast-check process peaks near 229 MB. iPhone memory and
  frame presentation remain unmeasured. Width-dependent plain/decorated paragraph
  geometry and eligible table widths are also retained; hyphenated and legacy
  paragraphs keep their measurement path. CTLine/CTRun/CTTypesetter ownership
  remains snapshot-local. Cold misses
  and unsupported paint still need extraction/fallback. Warm paint-value hits skip
  snapshot-local fragment CTLines; ordinary interaction also reuses bounded natural
  caret geometry. Long fragments and non-grapheme UTF-16 positions retain their
  existing materialization fallback. Unprepared attachment paragraphs remain eager. Exact line breaking and
  logical CTLines build only for measured paragraphs in viewport mode. First-use
  painting incurs materialization on misses, long fragments or unsupported paint.
  Selection lookup seeks into overlapping semantic
  spans and source intervals rather than scanning the document per match. Reader
  Find reuses semantic matching across unchanged text and builds highlight paths
  around an overscanned viewport. A conservative envelope can include extra table
  candidates, and a giant match still requests broad selection geometry. Direct `ranges(matching:)` calls
  perform full text search. Old snapshot disposal can also add UI-thread cost. See
  [reflow preparation](013-reflow-preparation.md), [metadata reuse](014-reflow-metadata.md),
  [lazy fragments](015-lazy-fragments.md), [viewport layout](016-viewport-layout.md),
  [glyph paint reuse](017-glyph-paint-reuse.md), [paint-only reuse](020-paint-without-caret-materialization.md),
  [incremental reflow](022-incremental-reflow.md), [idle preparation](023-fast-scroll-coverage.md), [compact preparation](024-compact-idle-preparation.md),
  [live reflow](../004-ios-reader/006-live-reflow.md),
  [mixed coverage](018-mixed-viewport-coverage.md), [selection lookup](019-selection-range-indexing.md),
  [retained Find matches](../007-reader-interactions/003-retained-find-matches.md),
  [viewport highlights](../007-reader-interactions/004-viewport-find-highlights.md),
  and [reader anchor lifecycle](../004-ios-reader/007-reflow-anchor-lifecycle.md).
- Live preview still parses the complete document and creates fresh preparation
  after source edits. Visible paragraph layout follows the viewport reflow path
  above. The app coalesces source edits and skips layout while the preview is
  hidden. Source and preview scroll independently. See [009](../009-source-editor/000-plan.md) and
  [editor continuity](../009-source-editor/002-editor-experience.md).

Performance measurements use the [reader benchmark suite](../../benchmarks/reader/README.md). They do not cover physical-device frame delivery or UIKit memory.
