# 002.005 — Adaptive table columns and horizontal reader scrolling

## Context and design (2026-11-17, before implementation)

The reader compresses every table to its page measure in proportion to whole-cell
text widths. A verbose column takes most of the width while other columns break
into tiny fragments. The requested behavior is readable, compact tables with
independent horizontal scrolling where the viewport cannot accommodate them.

Measure the actual styled cells, including bold headers. Allocate width between
word-sized minimums and bounded preferred widths, giving short columns their
natural width before assigning space to verbose columns. Use em-relative cell
padding. Reader layouts may overflow; file exports continue to fit every column
to the requested page width. Do not add external build or test dependencies.

Keep the library snapshot immutable. Expose table viewport/content geometry and
separate table drawing so UIKit can host overflowing tables in native horizontal
scroll views. Translate selection, link and Find geometry through the same table
offsets. A table swipe must not move surrounding prose horizontally; Find must
reveal a match in an offscreen column.

Rejected alternatives: proportional whole-cell compression repeats the reported
failure; making the entire document horizontally scrollable also moves prose;
storing UI offsets in the shared layout would mix presentation and immutable
rendering state.

## Planned validation

- Focused package tests: narrow/roomy column allocation, bold headers, CJK,
  alignment, independent table paint clipping, semantic geometry and exports.
- Headless rendered examples at phone and wider widths, visually inspected.
- Simulator app build; interactive swipes, selection, links and Find only if
  simulator boot is authorized. No commit unless requested.

## Outcome

Implemented. Column allocation measures styled headers and
UAX14 word segments; short cells retain natural widths. Prose columns have a
9 em comfortable text minimum, raised to the longest word up to 12 em and bounded
by the cell's natural width. Preferred widths are bounded by 12 em or 60% of the
reading measure, whichever is larger. Spare width is distributed between minimum
and preferred sizes. These are implementation heuristics, not measured optimal
row-height rules. Cell padding is 0.6 em horizontally and 0.3 em vertically.

The reader opts into overflowing tables. `RenderedTable` exposes layout-local
IDs, viewport frames and content widths; `RenderedDocument.drawTable` paints
independent, table-local tiles. Page drawing can omit overflowing tables and
otherwise clips them to their viewport. `ReaderTableScrollView` handles native
horizontal motion; UIKit owns pan admission and nested scrolling. Table and prose
previews are painted off-main before the layout swap, while only visible regions
are seeded.

Text-input hit points add each table's offset; selection/caret/link geometry and
Find highlights subtract it. The initial reader cleared selection at the start
of a table drag; see the iOS selection follow-up below.
Find reveals an active result's first rectangle horizontally before scrolling
vertically. The snapshot itself owns no mutable scroll state. Replacing a reader
layout resets table offsets. Native selection dragging does not implement
horizontal table autoscroll.

Document-based PDF/PNG/JPG exports keep all columns fitted to the requested
measure. Snapshot PNG/JPG capture the initial viewport of an overflow-enabled
layout. No frozen reference measurements were changed: the existing table
fixtures freeze parsed semantics, not the replaced column-sizing heuristic.

Key paths:

- `Sources/KasumiMarkdown/TableLayout.swift`
- `Sources/KasumiMarkdown/DocumentLayout.swift`
- `Sources/KasumiMarkdown/RenderedDocument.swift`
- `apps/iOS/Kasumi/ReaderTableScrollView.swift`
- `apps/iOS/Kasumi/ReadingSurface.swift`
- `apps/iOS/Kasumi/ReaderTextInput.swift`
- `Tests/KasumiMarkdownTests/TableLayoutTests.swift`
- `fixtures/Tables.md`

## Validation

- Focused package command:
  `make test FILTER='TableLayoutTests|Export|Pagination|PublicAPITests|profileListColumnsQuoteBarsAndTableGridRespondToOverrides'`.
  Initially, two new expectations failed: assuming white theme paper and assuming
  PDF text would not hyphenate across a line. Inspection confirmed off-white paper
  and `Final re-` / `sult`; expectations now compare actual paper and normalize
  discretionary PDF line hyphens. Subsequent focused run: 23 tests passed.
- `make app` initially passed. A later rebuild encountered another concurrent
  build's locked Xcode database;
  `make app DERIVED_DATA=build/TablesDerivedData` passed with the iPhone 18 Pro
  simulator destination and the iPhoneSimulator 27.2 SDK, without booting it.
- Headless Core Graphics previews at 360 pt (light/dark and both table ends) and
  820 pt (light) were visually inspected. The verbose example stays in readable
  multiword columns; compact tables retain intrinsic width; offscreen last
  columns paint. Local screenshots and a PDF are not retained as source evidence.
  The temporary preview probe was removed after inspection.

## Remaining verification limits

The maintainer requested builds and headless rendering only. No simulator was
booted. Native gesture arbitration, selection handles, Copy and live Find in a
scrolled table have source-level wiring and geometry tests but no interactive
iOS verification in this task. The tests exercise unscrolled semantic geometry,
table paint and clipping, fitted exports, and tiled output; they do not execute
UIKit's gestures or text interaction.

## Follow-up: interruptible swipes and edge fades (2026-11-17)

The maintainer reported that an opposite swipe could not take over a table's
deceleration, and requested subtle fades like the supplied screenshot. The custom
pan-admission override rejected pans without predominantly horizontal velocity.
UIKit can ask to begin a pan on the touch that stops deceleration, before usable
velocity exists. That is the source-based explanation for the report; it has not
been reproduced interactively here. The override is removed, leaving pan admission
and interruption to `UIScrollView`.

`apps/iOS/Kasumi/ReaderTableEdgeMask.swift` supplies an 18 pt alpha gradient at
each edge with hidden content. Its frame tracks the scroll view's bounds origin,
so the mask stays fixed to the viewport during scrolling and bouncing. Fade
strength ramps down over the final 18 pt before reaching either content end;
the reached edge is opaque. Mask updates disable implicit animation. The mask
adds no touch-handling view and uses the current paper behind the table rather
than painting a hard-coded color.

Headless tests link the app's actual mask implementation into the package test
target. Pixel assertions use nested layers with moving bounds at the start,
middle, end, near both ends, and during bounce, plus a table that fits its width.
The maintainer subsequently verified the behavior and confirmed it works before
requesting a commit. Device/OS details and individual selection/Find checks were
not supplied; this is maintainer-reported validation, not an agent simulator run.

Follow-up validation: `make test FILTER='ReaderTableEdgeTests|TableLayoutTests'`
passed all four tests. `make app DERIVED_DATA=build/TablesDerivedData` passed for
the iPhone 18 Pro simulator destination, without booting it. Dark headless table
previews at the start, middle and end were visually inspected; the temporary
preview probe was removed. No frozen reference data changed.

Before committing, `make app` also passed in an isolated export of the staged
table changes, excluding the concurrent reader-reflow edits in the working tree.

## Follow-up: iOS selection in horizontally scrollable tables (2026-11-22)

Long-press worked in a fitted table but not in an overflowing one. On iOS
27.2, a press inside the nested scroll view did not reach the page's native
selection recognizers. Adding a second `UITextInteraction` to the table canvas
but keeping the page as its text input did not fix it.

The table canvas is now its own native text input. It uses table-content
coordinates and the document's semantic range for that table, so Select All
within an overflowing table selects only that table. The selection follows the
cell text during a horizontal swipe of the same table; UIKit still owns the
scroll and selection gestures. Fitted tables continue to use page selection.

On the iPhone 18 Pro simulator (iOS 27.2), `fixtures/Tables.md` showed the native
menu before and after a horizontal swipe. Copy from a revealed column put
`Audit` on the pasteboard. Select All highlighted only the active table, a
fitted cell remained selectable, and tapping the revealed `Final result` link
opened the expected confirmation. The focused table semantics test also passed.
