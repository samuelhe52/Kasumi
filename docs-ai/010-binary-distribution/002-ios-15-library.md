# 010.002 — iOS 15 library deployment target

## Context

The maintainer chose to lower the library's iOS minimum first. The iOS 15 probe identified the URL API used to locate bundled notices. The Rust archives also carried an independent iOS 17 deployment target. Published version `0.1.0` retains its iOS 17 minimum.

## Change

`Package.swift` and `scripts/build-native` target iOS 15 for the library and its native slices. `ThirdPartyNotices` appends the bundled notice path with `URL.appendingPathComponent(_:)`. The app targets iOS 27, and the library's macOS minimum is 13.

The first incremental rebuild reused iOS 17 Rust objects after the environment variable changed. The build script now keys the iOS Cargo target directory by deployment target so a change to that target rebuilds both iOS slices.

## Validation

- `make native` rebuilt all four XCFrameworks from a checkout with the old Cargo cache. The device and simulator archives contain no objects with a deployment target above iOS 15.
- A separate SwiftPM consumer compiled and linked the checkout for arm64 iOS device and simulator at 15.0 without linker warnings. Both binaries declare a 15.0 minimum. iOS 15 runtime behavior remains unverified.
- `make test FILTER='ThirdPartyNoticesTests|PublicAPITests'` passed all 10 tests on macOS. `make app-check-sim` built the reader and import extension at iOS 27.

## Refs

[Package.swift](../../Package.swift), [scripts/build-native](../../scripts/build-native), [ThirdPartyNotices.swift](../../Sources/KasumiMarkdown/ThirdPartyNotices.swift), [library guide](../../docs/library.md)
