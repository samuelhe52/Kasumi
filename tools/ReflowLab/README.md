# Kasumi Reflow Lab

A native macOS test window hosting the public AppKit `MarkdownReaderView` from
`KasumiMarkdownUI`. The window adds sample and file controls; the reader owns
scrolling, background layout and prepaint. Its timings are not iOS measurements.

From the worktree root:

```sh
make run-reflow-lab
```

Or build with `make reflow-lab`, then double-click
`build/KasumiReflowLab.app`. The app includes all pinned renderer resources and
can be launched again without Xcode or a simulator.

Choose English, Chinese, mixed formatting/attachments, or a single long
paragraph; choose the nominal body length (headings/labels and mixed attachments add text); then drag a window edge. The width is
unrestricted so resizing causes reflow. Scroll to check anchor continuity, or
use **Open…** to read your own UTF-8 Markdown/text file without modifying it.
**Reload** resets preparation for a cold run. Local images reserve space during
layout and decode at the display scale as they enter the visible viewport.
The timing label covers layout, prepaint, and installation. Image decoding
runs separately. Wide tables scroll independently. The Edit menu exposes
Find, Copy, and Select All.

`make check-reflow-lab` checks offscreen launch, rendering, scroll refinement,
programmatic Find navigation, and the visible-image refresh after idle
installation. It writes JSON under `build/`. It does not benchmark live
resizing or prove 120 Hz presentation. Native iOS scrolling is checked separately.

For a check that opens a real window and exercises native Find visibility and
its handoff to programmatic Find, run:

```sh
build/KasumiReflowLab.app/Contents/MacOS/KasumiReflowLab --interaction-check build/reflow-lab-interaction.json
```


## Fixed-width scrolling checks

Use the already booted simulator; the command never boots one. It must be the
only booted simulator because the Makefile's install/launch routine selects it.

```sh
make check-reader-scrolling CONFIGURATION=Release DEVICE=<simulator-UDID>
```

The check creates its own uniquely named documents and runs eight downward and
eight return swipes for English, Chinese, mixed, and single-paragraph bodies of
about 50k characters. Find stays closed and the width stays fixed. The first
traversal enters new regions; returning revisits them, but still may build new
snapshots. This is not a guarantee of a completely cold font/OS cache or of zero
work during the return traversal.

Results include screenshots, per-callback geometry/timing, CPU/signpost traces,
and JSON summaries under a timestamped `build/scroll-checks/` directory. The
opt-in `KASUMI_SCROLL_DIAGNOSTICS` launcher variable enables a display link that
requests up to 120 Hz and writes geometry/timing when the reader closes. Ordinary
launches create no diagnostic display link or output file. The packaged Mac app
does not enable this iOS diagnostic hook.

Callback gaps indicate main-thread/display-link scheduling, not actual GPU
presentation. Simulator refresh rate, automation and tracing overhead can affect
them. Coverage comes from conservative viewport-layout metadata, not pixel
inspection. Screenshots need inspection separately; they do not cover every
frame. The iOS Animation Hitches instrument is unavailable on the tested
simulator, so these checks cannot establish a physical-device hitch rate or
stable 120 fps.

The AppKit reader uses an SDR sRGB prepaint bitmap and native AppKit drawing.
The UIKit reader retains automatic image range and tiled layers.

## Mac measurements without a simulator

```sh
make benchmark-reader
make check-reflow-scrolling
make check-fast-reflow-scrolling
# Same-binary control without idle preparation:
make check-fast-reflow-scrolling REFLOW_IDLE_WARMUP=0
```

`make benchmark-reader` replaces the old in-app benchmark; see
[the benchmark protocol](../../benchmarks/reader/README.md).

The scrolling check drives the public AppKit reader through 100 downward and
100 return steps while background work runs, recording viewport coverage,
installations and process peak memory in `build/reflow-lab-scrolling.json`.

Neither check measures physical display frames or reproduces UIKit tile behavior.
The scrolling protocol requests 80-point steps every 16 ms; actual scheduling
can vary. Cold means a fresh document session, with OS/font caches left intact.
The on-screen timing label excludes file reading and parsing.

The fast check waits three seconds after the first screen, then traverses the
whole document down and back at 480-point steps requested every 8 ms. Its
`build/reflow-lab-fast-scrolling.json` records complete-layout readiness,
preparation time, missed coverage samples and the longest observed gap. On the
first coverage miss it also saves a rendered viewport PNG beside that JSON.
Sampling records measured geometry, not presented frames; the diagnostic PNG
can lengthen the first measured gap. Actual scheduling varies.

After 200 ms idle, the native readers prepare bounded text/table/math documents
in cancellable batches. The AppKit reader also prepares bounded documents with
known local or embedded image dimensions. Visible images still decode
separately. The Lab says **Entire document measured** when the complete
snapshot is installed. Width/content/style changes invalidate
that snapshot. This retains more geometry in memory; very large or resource-heavy
documents keep the viewport path. The fast check explicitly records readiness
rather than assuming three seconds always suffice. Its results do not guarantee
coverage for an immediate jump during cold opening or UIKit tile presentation.
