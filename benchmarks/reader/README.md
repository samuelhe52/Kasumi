# Reader performance benchmarks

```sh
make benchmark-corpus        # Export and verify the ten fixed Markdown samples
make benchmark-reader        # Quick sample for integration checks and rough medians
make benchmark-reader-full   # Full latency, memory and native coverage baseline
make benchmark-self-check    # Statistics, manifest and failure-handling tests
```

On an Apple M1 Pro the benchmark run itself takes about 35 seconds for quick and about 13.5 minutes (814 s) for full, excluding the build, which adds time on the first run. All jobs run sequentially, so plan for the full suite to occupy the machine, and avoid other heavy work during it.

No simulator or extra Python packages are needed. The benchmark builds in a separate Release scratch directory (`.build/bench`) so testability builds cannot contaminate it. `benchmark-reflow-lab` is a legacy alias for `benchmark-reader`; the opt-in `macReflowTimings` package test is a different, historical diagnostic.

Each run writes a new directory under `build/benchmarks/` (override with `BENCHMARK_OUTPUT=`; an existing directory is rejected) holding the emitted Markdown, `manifest.json`, `summary.json`, `report.md` and compressed raw child results. Any failed, timed-out or invalid child stops the run with a nonzero exit; partial output is kept.

## Samples

`corpus.json` pins SHA-256, byte and UTF-16 lengths for the `LabSample` generator shared with the Mac harness. A mismatch is an error: inspect it, then update the manifest deliberately.

- English, Chinese and mixed at nominal 20k, 50k and 200k body characters. Nominal length excludes labels, headings and mixed-content markup.
- One 50k-character Chinese paragraph, outside the complete-preparation envelope. Preparation must return nil and painting uses full layout.

Quick runs English/Chinese/mixed50k, mixed200k and the single paragraph; full runs all ten.

## What is measured

"Reflow" means width changes only. The worker fixes font size 18, the default preset and theme, and default insets. Style, theme, inset and revision changes are not covered.

Latency and paint use 1179×701 pt at 2× SDR. Memory uses 900×714 pt at 1× SDR. These are separate comparison keys and are never pooled.

| Phase | Covers |
| --- | --- |
| Cold / warm opening | Fresh processes. File read, parse, session setup, first viewport and first bitmap. Excludes process startup and UI installation. |
| Resize | Layout, paint and snapshot release at 1179/1000/900/440 pt. |
| Refinement | Moving-anchor viewport refinement before complete preparation. Not asynchronous publication or display frames. |
| After preparation | Complete preparation after the first viewport, then the first width change. |
| Paint | Forward and return traversal of every viewport with a fresh bitmap each time; at least 1000 observations per direction. |
| Find | The real reader search and highlight helpers. No UIKit path. |
| Memory | One child per size: first viewport, prepared plus one bitmap, and after full traversal, sampled at 0/5/15 s. |
| Native | The AppKit controller's ordinary, fast and fast-without-idle-preparation scrolling checks. |

Percentiles use nearest rank. p95 needs at least 100 observations and p99 at least 1000; otherwise they are null. Paint observations are correlated within sessions, so per-session ranges and tail concentration are reported alongside pooled values.

Memory reports current and lifetime-peak `phys_footprint` and RSS in decimal MB, every row n=1. "Settled" is the last idle observation, not a proven plateau. Native process memory includes AppKit and must not be compared with engine memory.

Uncovered painting, wrong preparation eligibility, corpus changes and invalid results fail the run. Warmed native fast scrolling must start fully measured with zero sampled misses; the idle-preparation-disabled control may miss, and its misses are recorded. Thermal state above nominal and Low Power Mode flag a result without rejecting it. Host, toolchain, revision, dirty state and executable hashes are retained.

## Comparing runs

Compare only the same sample hash, phase, geometry, style, build configuration and host class, and check n, spread and flags before trusting a median or p99. Cold means a fresh process with OS and font caches intact.

Match the runner profile too. Quick refinement visits 12 anchors; full visits
100 on the same session and reuses geometry prepared by earlier visits. Their
medians describe different cache histories and cannot establish a regression
against each other. The retained baseline uses the full profile.

For a parse-only Time Profiler capture, first run `make benchmark-build` and
`make benchmark-corpus BENCHMARK_OUTPUT=<new directory>`. The executable accepts
`--profile-parse <source.md> <positive repetition count> <output.json>`; pass that
command to `xcrun xctrace record --template 'Time Profiler' --output <new.trace>
--launch -- <executable> ...`. This diagnostic repeatedly constructs a document
and reads its outline in an autorelease pool, excluding layout and painting.
It records every parse-plus-outline duration and a heading-count checksum.
Use untraced worker cold/warm timings to validate user-visible parsing gains;
trace timings include profiling overhead.

Nothing here establishes display FPS, 120 Hz rendering, UIKit tile presentation or iPhone/iPad memory. Native coverage is geometry metadata, not pixels. Use the manual Mac lab or an authorized device run for those.

## Baseline

[2026-11-17 Apple M1 Pro](baselines/2026-11-17-m1-pro/report.md): all 689 children completed. Cold file-to-first-bitmap medians for mixed 20k/50k/200k were 134.16/153.08/187.67 ms. Mixed 200k engine footprint settled at 132.04 MB after full traversal (134.74 MB peak). Warmed native fast scrolling had zero coverage misses.

Paint tails varied widely: mixed 200k first/return p99 were 44.85/17.55 ms, and one session supplied over half the top 1% in each direction. Earlier separate runs were lower. This does not establish a cause or a regression, so repeat under similar host load before concluding anything. The host was shared and load was not measured continuously.
