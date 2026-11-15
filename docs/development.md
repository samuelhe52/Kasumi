# Development

## Requirements

Xcode 27 (iOS 27 SDK and a simulator runtime), Swift 6.2+, and Rust with
edition 2024 support plus the iOS targets:

```sh
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
```

## Commands

`make help` lists the targets. The common ones:

```sh
make test                     # library tests on macOS; FILTER=<name> narrows the run
make test-ios                 # library tests on the iOS simulator (SIMULATOR=, FILTER=)
make app                      # build the iOS app for the simulator
make run-sim                  # build, install and launch on the booted simulator
make run-device               # build, install and launch on a connected iPhone (DEVICE=<UDID>, DEVELOPMENT_TEAM=<team ID>)
```

Targets that build run `make native` first, which rebuilds the Rust
XCFrameworks under `.build/native/` only when a native package changed. Without
`make`, run `./scripts/build-native` once before the first `swift` or
`xcodebuild` call. `make run-sim` doesn't boot a simulator; start one first.

`make run-device` needs the phone unlocked, trusted and in Developer Mode, and
Xcode signed in to the Apple ID whose team owns the signing identity. The
project sets no `DEVELOPMENT_TEAM`, so pass yours, e.g.
`make run-device DEVELOPMENT_TEAM=<team ID>`.

## Layout

- `Sources/KasumiMarkdown/` — the library. Bundled fonts, themes and presets are
  in `Bundled/`.
- `Sources/KasumiRender/` — a macOS CLI that renders a document to PNG or PDF.
- `packages/Native*` — Rust line breaking, hyphenation and Dagre graph layout,
  exposed through small C interfaces. Licenses are in each `Notices/`.
- `apps/iOS/` — the app. Its folder-synchronized group picks up new files under
  `apps/iOS/Kasumi/` without project edits.
- `fixtures/` — authored test documents; `fixtures/reference/` holds frozen
  measurements the tests compare against. The test target bundles it through
  the `Tests/KasumiMarkdownTests/fixtures` symlink so tests also run on the
  simulator.

## Rendering a document

```sh
swift run KasumiRender fixtures/Rendering.md /tmp/rendering.png 800
swift run KasumiRender fixtures/Profiles.md /tmp/profiles.pdf --preset book --theme solarized-light
```

The output extension picks PNG or paginated A4 PDF; the width applies to PNG.
Other options: `--profile FILE.toml`, `--theme ID`, `--dark`.
