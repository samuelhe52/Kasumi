# 011.005 — Live resize

## Context

While a window, divider or pane moved, the text trailed the reader's width and its
right edge flashed. Table-heavy documents and open panes made it worse.

The AppKit reader laid out and painted each width asynchronously and installed the
result in a later display pass. AppKit had already displayed the new width with the
old text, so faster layout shortened the flash but could not remove it.

## Design

- A width change starts a background layout and viewport paint
  (`ReaderLayoutJob`), and the reader's layout pass waits for it, up to 10 ms. A
  result in time installs before the new width displays. The wait can't deadlock
  because the job never needs the main actor.
- A job over budget installs later through the existing asynchronous pipeline.
  Until a job finishes within the budget again, resizes don't wait. The canvas
  still follows the viewport, so the paper reaches the edge.
- The viewport bitmap uses the window's color space. Drawing an sRGB bitmap
  converted it on the main thread on every pass.
- Rejected: sizing only the canvas from the viewport, the first version of this
  change. Old text still drew into the new margin.
- Rejected: waiting for layout alone and painting in the display pass. It cost
  more main-thread time than drawing a prepared bitmap.
- Table column measurements don't depend on width and stay in the reflow session;
  only their allocation is recomputed. Columns with images are measured each time.
  Nearby widths start from the last measured region, and coverage is still checked.
- A height change reuses a layout that covers the viewport and scroll buffer, and
  returns a displaced viewport to its anchored line.
- The Outline is an inspector item in the native window split beside the navigator.
  Its effect on performance was not measured separately.
- The Outline is full height with a toolbar tracking separator, like the navigator,
  so the tab bar ends at its edge. Rejected: `allowsFullHeightLayout = false`, which
  ran the tab bar across the Outline while its background still reached the top.

## Validation

On an Apple M1 Pro with macOS 27.2.1, scripted 4-second corner resizes of a
table-heavy document at 60 steps per second compared the Release builds with the
wait at 10 ms against an asynchronous baseline. The baseline also used the earlier
sRGB, separately painted bitmap. "Stale" counts distinct widths whose text layout
still had another width after the run loop committed. Two runs each.

| Configuration | Distinct widths | Stale widths | Median main-thread CPU per width |
| --- | --- | --- | --- |
| Reflow Lab | 224–225 → 223 | 223–224 → 1 | 12 → 9 ms |
| App, panes closed | 149–155 → 197 | 148–154 → 1 | 18–22 → 12 ms |
| App, both panes open | 115–122 → 157 | 114–121 → 1–2 | 28–32 → 16 ms |

A dense 27 KB document of code, math and images exceeded the budget and stayed
asynchronous, with nearly every width stale and little change in lag.

The app ran in the background with the display off, so these numbers support the
comparison only. The maintainer then
reported that the app works, without naming the checks. Displayed frames and macOS 26 were not checked.
The AppKit reader, reflow, table and viewport suites passed with the display on.

A Debug build on macOS 27.2.1, captured with the display on, kept the tab bar within
the document column with the Outline open, closed and reopening, with both panes
closed, and at widths from 460 to 1300 points. At 460 with both panes open the
column is only 84 points wide and its tabs are unreadable.

## Refs

`Sources/KasumiMarkdownUI/AppKit/ReaderLayoutJob.swift`,
`Sources/KasumiMarkdownUI/AppKit/AppKitMarkdownReaderView.swift`,
`Sources/KasumiMarkdown/DocumentReflowSession.swift`,
`Sources/KasumiMarkdown/TableLayout.swift`,
`apps/macOS/Kasumi/MacNavigatorSplit.swift`.
