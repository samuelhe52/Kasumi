# 010 — Binary distribution: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-11-17 | Prepared native release workflow, local manifest selection, toolchain pin and documentation. | Working tree |
| 2026-11-18 | Production run 44328037947 failed at "Publish exact prepared archives": `${flags[@]}` with an empty array is unbound under `set -u` in the runner's bash 3.2. The release tag had already been pushed; no release was created. | Run 44328037947 |
| 2026-11-18 | Fixed the expansion to `${flags[@]+"${flags[@]}"}`, deleted the stray tag and reran. Run 44329950517 published the release. Release notes were then replaced with the release summary. | Commit 29ced2e, run 44329950517 |
| 2026-11-18 | README states the library's platform minimums. | Commit ea371e3 |
| 2026-11-19 | Direct SwiftPM check of the first published release: `swift package add-dependency … --from <release>` resolved and downloaded all four binaries. A macOS consumer built only after declaring its platforms; the iOS 17 simulator build of KasumiMarkdown succeeded. | Scratch package |
| 2026-11-19 | Release run 44515644238 published a patch release with the iOS 15 library minimum. Release notes were replaced with the approved summary. A scratch SwiftPM consumer built for macOS and the arm64 iOS 15 simulator. | Commit 2fc15db, run 44515644238 |

## Outcome and current state (as of 2026-11-17)

The manual workflow in `.github/workflows/native-release.yml` builds the native XCFrameworks, prepares release URLs and checksums, creates a release-only commit and version tag without advancing the source branch, publishes the archives, and checks a clean URL consumer. Test mode requires a separate repository and a `-ci.` prerelease version. `scripts/prepare-native-release` creates the archives and manifest entries; `scripts/native-mode` changes the manifest for local builds of a release tag. Development commits default to local binaries. Rust 1.98.1 is pinned in `rust-toolchain.toml`.

The workflow passed a complete test in a separate public repository. That repository and both test prereleases were deleted at the maintainer's request after success. This checkout has no configured production remote, and no production release was created.

## Production release (2026-11-18)

- The first production release was published from `main` with four XCFramework ZIPs, `notices.tar.gz` and `provenance.json` (run 44329950517).
- The workflow's URL consumer check passed in the production run.
- A macOS SwiftPM consumer needs `platforms: [.macOS(.v13), .iOS(.v17)]` in its manifest. Without it, SwiftPM's default macOS minimum is 12 and the product fails to build. With the line, the consumer built and rendered a PNG.

## Deviations from plan

The local switch edits `Package.swift`, because a marker file did not invalidate SwiftPM's cached manifest in the local test. The release-only commit is not merged to the development branch, so development commits cannot silently use the previous release's binaries. The first test run failed because the generic simulator build requested x86_64; the check now explicitly selects arm64.

## Validation

- `make native-local` rebuilt the four arm64 XCFrameworks successfully with the pinned toolchain.
- `make test FILTER='PublicAPITests|CodeSyntaxTests|dagreNativeGeometryAndDirectionCrossTheCABI'` passed 15 tests before the final native rebuild.
- A separate local SwiftPM consumer built and rendered a PNG using the checkout.
- `make app-check` built the iOS app for a generic device with signing disabled.
- A scratch release preparation produced four ZIPs; all manifest checksums matched and SwiftPM manifest output switched between local and remote targets in both directions.
- `actionlint` passed with its outdated warning for GitHub's `xcode-27` runner label suppressed. Initial unsuppressed run rejected that label; GitHub's runner documentation lists it.
- Two concurrent rustup operations collided during the first scratch preparation; it failed before provenance output. A single subsequent toolchain install completed, and the scratch preparation passed on retry.
- `git diff --check` passed. No simulator was booted or driven.

- GitHub Actions test run 44085888785 published a `-ci.` test prerelease but failed its generic simulator build because Xcode requested x86_64. A separate local SwiftPM consumer downloaded that release and rendered a PNG.
- GitHub Actions test run 44087775961 succeeded in 10m57s: native build, tests, release commit and tag, asset publication, generic iOS device and arm64 simulator builds, and a fresh URL consumer. The temporary repository was deleted after success; the run URLs no longer resolve.
- `make app-check-sim` also passed locally with `ARCHS=arm64`. No simulator was booted.
- GitHub warned that `actions/checkout@v4` targets deprecated Node.js 20 and is forced to run on Node.js 24; the run passed.

## Open questions

- Production publication works with the default workflow token on `main` (run 44329950517). Branch rules beyond that were not separately checked.
- Failure recovery was exercised once. A failed run can leave its tag, which blocks a rerun. Recovery is manual: delete the remote tag with `git push origin --delete <version>`, fix the cause and rerun. The workflow does not clean up after itself.
- Intel macOS and simulator slices are not provided. The library requires arm64.
