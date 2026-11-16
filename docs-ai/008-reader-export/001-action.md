# 008 — Reader export: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-11-16 | Recorded the plan before implementation; added file export APIs, JPEG, bounded bitmap rendering, reader options, sharing, and printing. | Uncommitted |
| 2026-11-16 | Ran focused tests, built the app, checked iPhone sharing for all three formats and native print preview, inspected exported artifacts, and measured desktop export memory/time. | Uncommitted |
| 2026-11-16 | After the maintainer reported a severe simulator memory leak and requested a reboot, shut down both simulators, rebooted only the iPhone, and stopped runtime checks. Finished host tests and the iOS build with the app closed. | Uncommitted |

## Outcome and current state (as of 2026-11-16)

Reader Actions > Export presents PDF, Long PNG, and Long JPG. PDF offers A4 or
US Letter and page numbers; images offer layout width and 1x/2x/3x resolution;
JPG also offers quality. All outputs use the current theme/fonts. PDF uses the
preset's print body size; images retain reading size. The native activity sheet
provides sharing and Save to Files. PDF also has a native Print action.

Each sheet owns one detached export worker with cooperative cancellation.
Options and export actions stay in place and dim/disable during work, without a
progress view or per-page UI updates. The toolbar's Done action becomes Cancel
while loading, preserving the form's layout. Cancellation keeps the job busy
until the worker actually exits. A job captures its source/style and builds a
separate layout, avoiding the reader snapshot's drawing lock and semantic index
construction. Temporary files live through sharing/printing and are removed on
dismissal, failure, or cancellation.

Library changes:

- `Sources/KasumiMarkdown/DocumentExport.swift`: public file PDF/image exports,
  resource preload, image format/options/progress, and snapshot JPEG Data export.
- `Sources/KasumiMarkdown/DocumentExporter.swift`: direct file encoding and a
  sibling staging file published only on success. PDF uses a checked file-stream
  consumer rather than complete encoded Data. PNG/JPEG return the source image
  from a separate bitmap-construction scope before encoding, releasing the
  drawing context; text drawing uses 32-paragraph autorelease batches. PDF scopes
  transient objects per page and formats its date once per job.
- `Sources/KasumiMarkdown/DocumentPagination.swift`: a monotonic band cursor
  replaces rescanning earlier bands for every page.
- `Sources/KasumiMarkdown/RenderedDocument.swift`: snapshot image export accepts
  the new JPEG format while retaining the snapshot lock.
- `Sources/KasumiRender/main.swift`: CLI help includes JPG; the existing internal
  file exporter now recognizes `.jpg` and `.jpeg`.
- `apps/iOS/Kasumi/ReaderExport.swift` and `ReaderScreen.swift`: export workflow
  and native controller integration, with soft toolbar edge effects.

The default raw bitmap limit is now 128 MiB, replacing the previous 512 MiB
image guard. File API callers can configure it. Dimensions remain limited to
32,768 pixels per axis. This is not a bound on total process memory: layout,
images, font resources, and encoder workspace also consume memory. Oversized
requests fail before bitmap allocation and explain how to lower width/scale or
choose PDF. PNG preserves alpha; JPG composites translucent paper over white.
Rounded-up edge rows receive full paper coverage.

No frozen reference expectations changed. No commit or push was made.

## Deviations from plan

The maintainer explicitly allowed simulator use after work started. An iPad
simulator was booted for planned presentation checks but was shut down before
those checks when the maintainer requested a reboot due to a severe memory leak.
The iPhone was rebooted and left with the app closed. Long-document UI
cancellation/oversize checks and iPad checks were not completed; cancellation and
budget enforcement were verified by host tests instead.

## Validation

- Final `make test FILTER='Export|Pagination|PublicAPITests'`: 19 tests passed,
  including parameterized PNG/JPEG and PDF/image cancellation cases. Coverage
  includes geometry/encoding, translucent paper and fractional edge coverage,
  successful replacement, bitmap-budget rejection, invalid quality, refusing a
  directory destination, preserving existing files on cancellation/failure,
  staging cleanup, PDF paragraph/footer retention, and existing facade/rendering
  checks. Existing public API tests now include snapshot JPEG decoding/geometry.
- Final `make app`: succeeded for iPhone 18 Pro / iOS 27.2 simulator. The normal
  App Intents metadata warning reports no AppIntents dependency.
- `git diff --check`: passed.
- Earlier app builds were installed/launched through Makefile commands. On the
  already booted iPhone 18 Pro (iOS 27.2), `sim-use` exercised Reader Actions >
  Export, PDF sharing, print preview and cancellation, long PNG sharing, long JPG
  sharing, and returning from share sheets. The exported `Rendering.md` PDF was
  two A4 pages; print preview showed both pages. PNG and JPG were 1200x3078 and
  recognized by the activity sheet with the correct media type. Job folders were
  observed during sharing and removed after dismissal.
- Rendered and visually inspected both PDF pages and the full PNG/JPG, including
  CJK, math, tables, code, diagrams, footnotes, and the final paragraph. PDF text
  extraction retained that final paragraph and selectable text.
- The final checked PDF stream consumer and hidden export back-button adjustment
  passed host tests/build, but runtime checks were not repeated after the reboot.
  No iOS package test run was performed in this task.
- During development, a copied CLI initially failed to locate its resource bundle;
  measurements were rerun with executables beside the built package resources.
  Initial paper-color tests wrongly assumed white, then exposed fractional edge
  coverage; the test now uses explicit translucent paper and the exporter fills
  rounded-up edge pixels. Two intermediate stream-consumer compile errors (the
  `cbks` argument label and a nonoptional buffer pointer) were corrected before
  the final passing checks.

### Desktop performance probe

Debug CLI, macOS, `/usr/bin/time -l`, with the pre-change binary preserved beside
its package resource bundle. Generated input: `# Export performance`, followed
by 100 numbered section headings; each has a paragraph beginning `Paragraph N:`
and seven repetitions of `Native typography with selectable PDF text and bounded
image export.` Image width was 800 points at scale 1, producing 800x24610 pixels;
PDF used default A4 settings and produced 25 pages. These temporary input/output
and measurement files are local, not retained repository evidence.

| Format | Before elapsed / peak RSS | After elapsed / peak RSS |
| --- | --- | --- |
| PNG, first controlled pair | 7.34 s / 233.8 MiB | 8.15 s / 126.1 MiB |
| PNG, repeat in reverse order | 7.57 s / 233.9 MiB | 7.38 s / 126.2 MiB |
| PDF, final stream consumer | 7.31 s / 51.7 MiB | 7.68 s / 50.6 MiB |
| JPG, new format | No baseline | 8.09 s / 125.0 MiB |

PNG peak RSS fell about 46%. CPU time in the PNG pairs was approximately
7.16-7.24 seconds for both implementations; wall-clock variance does not establish
a speedup or slowdown. The last PDF sample overlapped an app build. These are
small desktop probes, not Release/device benchmarks or evidence against a leak.

## Open questions

- The reported simulator memory leak was not diagnosed or fixed by this task;
  rebooting is recovery, not evidence about its cause. iPad presentation,
  physical-device latency/memory, actual printer delivery, long-document UI
  cancellation/oversize flows, and repeated-export leak behavior remain unverified.
- Core Text layout and ImageIO finalization cannot be interrupted midway;
  cancellation takes effect around those calls and between drawing batches/pages.
- Remote resource failures retain the renderer's image placeholder behavior.
  Existing PDF-link/pagination/footnote and HTML/SVG limitations remain in the
  [renderer gaps](../002-rendering-engine/renderer-gaps.md).
