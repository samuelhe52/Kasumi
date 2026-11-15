# 001 — Reusable library and universal iOS reader: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-11-14 | Bootstrap repository and analysis-era docs | `d193cad`, `6baa4a4` |
| 2026-11-14 | Refocus on a reusable library and universal iOS reader | `d7cff70` |
| 2026-11-14 | Extract the library, build Rust bridges as XCFrameworks, remove the macOS app; 149 library tests passed on macOS per the commit message | `55b03b8` |
| 2026-11-14 | Add the universal iOS app shell (not yet linking the library) | `33e4179` |
| 2026-11-14 | Remove the README until the project matures | `7ddcf1d` |
| 2026-11-14 | Rename to Kasumi / KasumiMarkdown; bundle ID `com.samuelhe.Kasumi` | `21e3321` |
| 2026-11-14 | Add the app icon; SVG sources and generator in `design/icon` | `251187d` |
| 2026-11-14 | Remove reference tooling and identifiers; rename native crates and C symbols | `f181339` |
| 2026-11-14 | Rewrite docs without provenance, then cut them to goal, development, and status | `910384a`, `69877d1` |
| 2026-11-14 | Add the Makefile and agent guidance | `d53539c`, `2c78cdb`, `6302742` |
| 2026-11-14 | Port the library off AppKit and test it on iOS | `ccf0bee` |

## Outcome and current state (as of 2026-11-15)

`KasumiMarkdown` is a Swift package library used by the iOS app through its public
API ([003](../003-public-rendering-api/000-plan.md)). The macOS app is gone;
`KasumiRender` renders documents from the command line. Native dependencies build
from `packages/Native*` through `make native` as XCFrameworks for macOS, iOS, and
the iOS simulator (arm64 only). The product goal is the living
[goal.md](goal.md).

Key files:

- `Package.swift`
- `Sources/KasumiMarkdown/`
- `Sources/KasumiRender/`
- `packages/NativeLineBreak/`, `packages/NativeHyphenation/`, `packages/NativeDagre/`
- `scripts/build-native`
- `apps/iOS/`
- `fixtures/reference/`

## Deviations from plan

The plan is retrospective. The six renderer docs and the reference-data note
written in `910384a` were deleted in `69877d1` because they restated code and
tests; their gaps moved into the status document, and now into
[renderer gaps](../002-rendering-engine/renderer-gaps.md).

## Validation

Reconstructed from Git; nothing was rerun for this record. The last recorded
results (status document at `fbb13cb`): all 160 library tests pass on macOS
(`make test`); on the iOS simulator (`make test-ios`) 150 pass and 10 that pin
Apple CJK faces are skipped.

## Open questions

- The XCFrameworks are generated, not committed, so depending on the repository
  by URL doesn't work yet.
- License notices aren't bundled into the app.
- The future README credit wording is not yet written.
