# Reflow benchmark baseline

Run: `2026-11-17T15:33:30.289783+00:00`; renderer revision `8bf141cc4653`. Profile: **full**. Complete: **True**.

Host: Apple M1 Pro; ProductName:		macOS; ProductVersion:		27.2.1; BuildVersion:		26B131. Standard Release, isolated `.build/bench`.

Times are milliseconds; memory uses decimal MB. Cold means a fresh process with OS/font caches intact. Engine measurements exclude UIKit/AppKit installation and physical display presentation. No timing thresholds are asserted. p95 requires n≥100, p99 n≥1000; — means insufficient samples. Pooled paint observations are correlated within sessions, not independent confidence estimates. Maxima are observed maxima.

Latency: 1179×701 pt, font18, 2× sRGB SDR. Resize uses widths1179/1000/900/440 and the same height/font/scale. Memory: 900×714 pt, font18, 1× SDR, reusable traversal context; every memory row has n=1. These geometries are separate comparison keys.

## Opening and preparation

| Case | Cold parse p50 | Cold first viewport p50 | Cold first paint p50 | Warm viewport p50 | Full prep p50 | First width change after prep p50 |
|---|---:|---:|---:|---:|---:|---:|
| chinese-20000 | 1.28 | 32.27 | 21.58 | 16.47 | 98.47 | 4.84 |
| chinese-200000 | 10.56 | 46.14 | 20.33 | 29.52 | 1166.47 | 7.87 |
| chinese-50000 | 2.91 | 35.27 | 21.59 | 18.48 | 272.29 | 4.94 |
| english-20000 | 0.84 | 24.12 | 13.19 | 9.55 | 36.43 | 3.45 |
| english-200000 | 5.55 | 31.10 | 14.76 | 14.87 | 453.88 | 5.58 |
| english-50000 | 1.61 | 24.65 | 13.78 | 10.14 | 98.26 | 3.75 |
| mixed-20000 | 4.62 | 39.49 | 20.52 | 18.46 | 119.88 | 6.15 |
| mixed-200000 | 32.16 | 54.80 | 22.36 | 35.08 | 1493.37 | 12.67 |
| mixed-50000 | 8.75 | 44.89 | 21.90 | 21.04 | 339.36 | 6.54 |
| single-50000 | 2.16 | 309.18 | 24.21 | 270.80 | 0.01 | 91.46 |

Full preparation is measured after the first viewport; it is not first-screen loading. Single50k is outside the preparation envelope; its prepare number is an eligibility check returning nil.

## Paint traversal

| Case | Sessions / n each way | First p50 / p95 / p99 / max | Return p50 / p95 / p99 / max | First session median range | Return session median range |
|---|---:|---:|---:|---:|---:|
| chinese-20000 | 59 / 1003 | 16.89 / 30.54 / 50.52 / 166.03 | 3.15 / 6.64 / 10.27 / 122.81 | 14.94–45.11 | 2.64–6.25 |
| chinese-200000 | 7 / 1162 | 15.41 / 22.33 / 29.28 / 58.84 | 2.69 / 3.82 / 5.63 / 10.30 | 14.38–19.26 | 2.37–3.00 |
| chinese-50000 | 24 / 1008 | 18.94 / 41.86 / 65.68 / 407.87 | 3.32 / 7.09 / 16.52 / 291.37 | 14.82–36.13 | 2.81–7.30 |
| english-20000 | 125 / 1000 | 10.75 / 17.25 / 20.77 / 287.91 | 2.18 / 3.42 / 6.42 / 34.61 | 9.74–18.95 | 1.94–7.35 |
| english-200000 | 13 / 1014 | 11.44 / 15.13 / 27.54 / 57.77 | 2.31 / 3.06 / 3.82 / 4.68 | 10.85–14.70 | 2.07–2.71 |
| english-50000 | 50 / 1000 | 10.93 / 15.19 / 18.25 / 29.02 | 2.10 / 3.24 / 4.49 / 6.22 | 10.10–16.89 | 1.92–2.83 |
| mixed-20000 | 53 / 1007 | 14.05 / 16.20 / 22.76 / 124.58 | 2.54 / 3.18 / 3.95 / 6.84 | 13.59–16.63 | 2.34–3.15 |
| mixed-200000 | 6 / 1116 | 14.95 / 22.81 / 44.85 / 228.67 | 3.12 / 7.23 / 17.55 / 371.39 | 14.27–16.52 | 2.65–4.16 |
| mixed-50000 | 22 / 1034 | 16.00 / 26.20 / 40.09 / 51.83 | 3.06 / 5.56 / 8.40 / 12.17 | 13.92–25.97 | 2.54–5.44 |
| single-50000 | 1 / 36 | 15.77 / — / — / 31.19 | 2.83 / — / — / 3.34 | 15.77–15.77 | 2.83–2.83 |

Complete forward/reverse pairs with a fresh session per pair; parsing, prep and release excluded. Bitmap/context/image creation included. Per-session empirical p95 ranges and tail concentration are in summary.json. Single50k uses a full-layout fallback and only one traversal pair.

## Resize, refinement and Find

| Case | Layout p50 @1179 / 1000 / 900 / 440 | Paint p50 @1179 / 1000 / 900 / 440 | Release max | Moving-anchor p50 / p95 | Find search miss / hit p50 | Find viewport geometry p50 / max |
|---|---:|---:|---:|---:|---:|---:|
| chinese-20000 | 8.74 / 8.17 / 7.02 / 2.09 | 3.32 / 2.73 / 2.53 / 1.10 | 9.58 | 0.88 / 8.49 | 0.99 / 0.00 | 0.11 / 0.15 |
| chinese-200000 | 10.69 / 11.05 / 7.65 / 3.99 | 3.24 / 2.69 / 2.39 / 1.20 | 0.30 | 12.57 / 26.49 | 11.54 / 0.00 | 0.15 / 1.79 |
| chinese-50000 | 8.93 / 8.20 / 7.27 / 2.47 | 3.14 / 2.61 / 2.32 / 1.19 | 0.30 | 1.31 / 22.48 | 2.55 / 0.00 | 0.12 / 0.16 |
| english-20000 | 5.13 / 4.30 / 3.51 / 1.77 | 2.69 / 2.00 / 1.81 / 0.89 | 0.22 | 9.07 / 12.97 | 0.26 / 0.00 | 0.05 / 0.09 |
| english-200000 | 7.67 / 5.93 / 5.18 / 3.28 | 2.92 / 2.13 / 1.96 / 0.97 | 0.20 | 12.56 / 35.74 | 3.49 / 0.00 | 0.07 / 1.21 |
| english-50000 | 5.10 / 4.00 / 3.44 / 1.73 | 2.56 / 1.91 / 1.70 / 0.86 | 0.28 | 8.52 / 13.05 | 0.62 / 0.00 | 0.05 / 0.09 |
| mixed-20000 | 10.43 / 10.18 / 8.79 / 4.43 | 3.10 / 2.57 / 2.42 / 1.24 | 0.43 | 2.61 / 13.68 | 1.02 / 0.00 | 0.11 / 0.17 |
| mixed-200000 | 14.44 / 16.21 / 11.51 / 10.58 | 3.47 / 2.70 / 2.58 / 1.45 | 1.15 | 22.45 / 42.95 | 10.20 / 0.00 | 0.13 / 0.19 |
| mixed-50000 | 10.78 / 10.77 / 9.37 / 5.22 | 3.03 / 2.60 / 2.28 / 1.25 | 0.77 | 3.99 / 28.16 | 2.62 / 0.00 | 0.12 / 0.21 |
| single-50000 | 108.44 / 93.46 / 85.67 / 45.82 | 4.07 / 3.14 / 2.82 / 1.36 | 3.35 | 2.05 / 2.45 | 2.46 / 0.00 | 0.15 / 1.92 |

Find measures the real reader search/cache and highlight-index helpers; match remapping and whole-document selection are also retained in summary.json. Snapshot release excludes session/cache destruction. No UI installation cost is inferred.

## Retained engine memory

| Case (n=1) | First viewport footprint / RSS | Prepared + one viewport, settled footprint / RSS | After full traversal, settled footprint / RSS | Lifetime peak footprint / RSS |
|---|---:|---:|---:|---:|
| chinese-200000 | 18.40 / 37.31 | 53.38 / 74.25 | 111.46 / 120.82 | 116.33 / 137.23 |
| chinese-50000 | 11.58 / 30.65 | 23.95 / 25.13 | 41.32 / 50.69 | 44.04 / 53.38 |
| english-200000 | 14.39 / 32.59 | 52.68 / 68.57 | 77.02 / 43.40 | 82.77 / 99.39 |
| english-50000 | 10.06 / 28.28 | 20.19 / 39.04 | 29.43 / 38.47 | 32.11 / 50.97 |
| mixed-200000 | 22.18 / 43.63 | 69.70 / 99.79 | 132.04 / 162.12 | 134.74 / 164.82 |
| mixed-50000 | 12.94 / 34.41 | 28.41 / 33.47 | 46.83 / 39.63 | 49.66 / 63.32 |

Settled means the last explicitly timed idle observation, not proof of an eventual plateau. Both current footprint/RSS and lifetime peaks are recorded independently. Native app memory below includes additional AppKit/buffer costs.

## Native AppKit coverage

| Scenario | Nominal size | Ready before traversal | Missed / sampled | Maximum sampled gap ms | Process peak footprint / RSS MB |
|---|---:|---|---:|---:|---:|
| nativeOrdinary | 50000 | False | 0 / 201 | 0.00 | 151.59 / 249.18 |
| nativeOrdinary | 200000 | False | 0 / 201 | 0.00 | 151.59 / 249.18 |
| nativeFast | 50000 | True | 0 / 177 | 0.00 | 232.34 / 264.72 |
| nativeFast | 200000 | True | 0 / 697 | 0.00 | 232.34 / 264.72 |
| nativeFastControl | 50000 | False | 153 / 173 | 1335.41 | 222.43 / 305.09 |
| nativeFastControl | 200000 | False | 655 / 687 | 2150.68 | 222.43 / 305.09 |

Native coverage is conservative layout metadata sampled around controller scrolling, not frame presentation or pixel evidence for every frame. Fast-control disables idle preparation; its misses are diagnostic, not a passing target. Native scenarios each hold both sizes in one process. Physical-device FPS, UIKit tiles and iPhone memory remain unmeasured.

## Validity and host flags

Children: 689 planned; 689 finished. Failed: 0; missing: 0.

Host warnings: none observed in worker snapshots.

More than half of pooled top-1% observations came from one session in: chinese-20000: firstMs; chinese-50000: firstMs; chinese-50000: returnMs; english-20000: returnMs; english-200000: firstMs; english-50000: firstMs; mixed-200000: firstMs; mixed-200000: returnMs; mixed-50000: firstMs.
