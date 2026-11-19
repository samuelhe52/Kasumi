# 010 — Binary distribution: Plan

| Field | Value |
| --- | --- |
| Status | Implemented; closed 2026-11-19 |
| Anchor date | 2026-11-17 |
| Origin | Maintainer requested CI-built binaries for tagged releases and local builds for arbitrary checkouts, with a separate test release. |
| Related | [Roadmap](../roadmap.md) |

## Background

The package references ignored, locally built Rust XCFrameworks. A URL consumer cannot build without preparing a checkout.

## Goals

- Tagged versions resolve four published XCFrameworks without Rust.
- A local checkout can build its own native binaries.
- Exercise the release process without creating a production release.

## Design / approach

A manual GitHub Actions release builds and packages native libraries, computes checksums, makes a release-only manifest commit without advancing the source branch, tags it, and publishes the exact archives. Local builds use an explicit local manifest mode. The test release belongs in a separate repository. Build and test with arm64 macOS, iOS and iOS simulator slices initially.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| CI creates the final release commit and tag | Checksums must be present in the tagged SwiftPM manifest; a tag-triggered build cannot add them without moving the tag. |
| Local checkout mode | Allows source work without publishing binaries for every commit. |
| Separate test repository | Exercises publication without creating a production release. |

## Validation and acceptance criteria

Build a clean local consumer. Verify release preparation and artifact hashes locally. Test release publication and a clean URL consumer in a separate GitHub repository. No production release is created during testing.

## Amendments

- Updated 2026-11-19. The library deployment target drops to iOS 15. See [002-ios-15-library.md](002-ios-15-library.md).
