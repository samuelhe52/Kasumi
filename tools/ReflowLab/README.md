# Kasumi Reflow Lab

A native macOS test window for manually inspecting the shared reflow engine.
It uses `DocumentReflowSession`, the reader's actual coalescing/anchor state, a
background layout/prepaint pipeline, and a native AppKit scroll view. Its UI and
bitmap/tile implementation are a harness, not the UIKit reader. Its frame times
must not be presented as iOS performance.

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
**Reload** resets preparation for a cold run. Find and horizontal table scrolling
are not implemented in this Mac harness; table columns fit the window.

`make check-reflow-lab` runs an offscreen launch/render/scroll-refinement smoke
check and writes JSON under `build/`. It does not benchmark live resizing or
prove 120 Hz presentation. Native iOS scrolling is checked separately.


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

The Mac harness uses an SDR sRGB prepaint bitmap and native AppKit drawing,
whereas the UIKit reader retains automatic image range and tiled layers. It is a
shared-engine test window, not a reproduction of the production drawing backend.

## Mac measurements without a simulator

```sh
make benchmark-reflow-lab
make check-reflow-scrolling
```

The benchmark records parsing, first viewport construction, warm width changes,
fixed-width refinement, moving-anchor refinement and SDR viewport painting for
50k/200k Chinese and mixed samples. The scrolling check drives the actual Mac
controller through 100 downward and 100 return steps while background work runs,
recording viewport coverage and installations. Results are written to
`build/reflow-lab-benchmark.json` and `build/reflow-lab-scrolling.json`.

Neither check measures physical display frames or reproduces UIKit tile behavior.
The scrolling protocol requests 80-point steps every 16 ms; actual scheduling
can vary. Cold means a fresh document session, with OS/font caches left intact.
The on-screen timing label excludes file reading and parsing.
