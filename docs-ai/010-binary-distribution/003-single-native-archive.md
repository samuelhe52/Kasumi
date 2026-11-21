# 010.003 — Single native archive

## Context

An Xcode-built macOS consumer failed to link: each of the four Rust static libraries carried its own copy of the Rust standard library, including `EMPTY_PANIC` and `rust_eh_personality`. Dead stripping decides whether the duplicates surface, not the build tool. With a consumer built against the four archives:

| Xcode build | Dead stripping | Result |
| --- | --- | --- |
| macOS Debug, package defaults | off | duplicate symbols |
| macOS, `DEAD_CODE_STRIPPING=YES` | on | linked |
| iOS Simulator, defaults | on | linked |
| iOS Simulator, `DEAD_CODE_STRIPPING=NO` | off | duplicate symbols |

`swift build` and default Xcode app targets strip, which is why the app and the SwiftPM checks linked. Published releases ship the same archives, so URL consumers that link without dead stripping were affected.

## Change

The four existing native bridges compile as modules of one Rust static library, distributed as one XCFramework. This gives the final link one Rust runtime while retaining the existing C interfaces. The individual native crates remain for their tests and tools. Linking several Rust static libraries into one binary is unsupported because each brings its own standard library; dead stripping only hides it. Suppressing the duplicate symbols would hide it too.

`packages/Native/Cargo.lock` is the lockfile the shipped binary is built from. The per-bridge lockfiles still map crates to their notices, and `make licenses` fails if the combined lockfile resolves different registry crates than their union. `scripts/build-native`, `Package.swift`, and `scripts/prepare-native-release` build, consume, and publish the unified artifact. `make check-native-consumer` builds and runs a macOS consumer with Xcode, whose Debug link does not dead-strip, and with SwiftPM; the release workflow runs it.

## Validation

- `make native` built the macOS, iOS device, and iOS simulator slices.
- Focused public API, syntax, hyphenation, and Dagre tests passed: 21 tests.
- `make app-check` and `make app-check-sim` linked the iOS app for generic device and arm64 simulator destinations. No simulator was booted and no physical device was used.
- Scratch release preparation produced one archive with a matching manifest checksum. No release was published.
- The dead-stripping table above was reproduced on macOS 27.2.1 with a scratch copy of the four-archive layout and the consumer from `scripts/check-native-consumer`; the iOS rows used a generic simulator build.
- `make check-native-consumer` built and ran the macOS 13-targeted consumer with Xcode and SwiftPM on macOS 27.2.1 arm64; both rendered a PNG.
