---
name: kasumi-release
description: Prepare and publish KasumiMarkdown library releases through the GitHub `Native binary release` workflow — readiness checks, release notes, triggering and monitoring the run, failed-run recovery, and release verification. Use for library release preparation, readiness checks, or continuing an approved library release. Ends at a verified GitHub release; for the iOS app, TestFlight or the App Store, use kasumi-app-release.
---

# Kasumi release

Use this skill for Kasumi's release workflow. Read `AGENTS.md` for project conventions. Resolve paths from the repository root.

A Kasumi release is a GitHub release of the KasumiMarkdown package, with its prebuilt Rust XCFrameworks. CI publishes it. The scope ends at a verified GitHub release. Xcode Cloud builds, TestFlight, and App Store Connect belong to the `kasumi-app-release` skill. Don't treat their absence as a defect, and don't claim a GitHub release means the app shipped.

For a readiness check or an explanation, inspect and report only. Resume from verified current state without repeating completed steps. Preserve unrelated working-tree changes; other agents may share the tree.

## How the release works

These facts are settled. Do not re-derive them or propose alternatives.

- **CI does the release.** `.github/workflows/native-release.yml` (`workflow_dispatch`, inputs `version` and `mode`) builds the XCFrameworks, runs tests, writes the release URLs and checksums into `Package.swift` on a release-only commit, creates and pushes the tag, publishes the GitHub release with assets, then validates the released package by URL.
- **`runs-on: xcode-27` is a GitHub-hosted runner label** (GA 2026-10-15, Apple Silicon). Nothing is registered or configured locally. An empty `gh api repos/{owner}/{repo}/actions/runners` result is expected. Do not propose building the release locally, registering a runner, or changing the label. `actionlint` flags the label as unknown because its list is outdated; ignore that warning.
- **Don't hand-make release artifacts.** Never create, push or move version tags, build release ZIPs, or edit the `BEGIN/END RELEASE NATIVE BINARIES` block in `Package.swift` by hand. On `main` that block is empty (`[:]`) by design. Only the tag's release-only commit fills it.
- **Tags have no `v` prefix** (`0.1.0`). Each tag points at a `build: Prepare <version> native binaries` commit whose parent is on `main`. The tag is not reachable from `main`, so `git describe` on `main` won't find it. Find the previous release with `git fetch --tags` and `gh release list`. Review changes with `git log <tag>^..main`.
- **`mode=release` is the only mode for this repository.** `mode=test` requires a separate public test repository and a `-ci.` version. Never run test mode against production.
- **`main` must not move during a run.** The workflow aborts with `Branch moved` if the remote branch head changes before tagging. Push everything first, then don't push to `main` until the run finishes.
- **The app version is separate.** `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `apps/iOS/Kasumi.xcodeproj/project.pbxproj` are app-distribution metadata. Change them only when the maintainer asks.
- **"Milestone" means a `docs-ai/` roadmap entry**, not a GitHub milestone. The repository has none.

## Prepare and validate

1. **Check state.** Look at the working tree, the branch, and whether `main` equals `origin/main`. Check existing tags and releases (`git fetch --tags`, `gh release list`). Confirm the target version with the maintainer, as `X.Y.Z` without a `v`.
2. **Review changes since the previous release** (`git log <tag>^..main`). Stop and ask if newly tracked text describes another application's internals obtained by disassembly or binary analysis. Measurements from rendered output are fine. That kind of claim blocked going public once and needed a history rewrite.
3. **Validate locally, mirroring the workflow's test step.** Run `make test-syntax-native`, `make test FILTER='PublicAPITests|CodeSyntaxTests|dagreNativeGeometryAndDirectionCrossTheCABI'`, `make app-check` and `git diff --check`. Run broader tests (`make test`) when the change set warrants it. Ask before booting a simulator.
4. **Check docs that a release changes.** In `README.md`, the install line in "Using the library" should name the latest release, not a placeholder. The platform line must match `Package.swift` `platforms`. Also check `docs/library.md` "Requirements and installation". Edit the README only with the maintainer's explicit permission, and only the parts they approve. Update the install line after the release is verified, not before.
5. **Draft release notes and show them before triggering.** The workflow publishes `--generate-notes`, and the approved notes replace them afterwards. Keep them short: a title line, one sentence, then a few bullets for the app and for KasumiMarkdown. Every claim must be checked against the code.
6. Report the checks you ran and any gaps. Then present the first approval gate.

## Approval gates

### Runtime override: `QUICK_PASS_ENABLE`

When the user's message contains `QUICK_PASS_ENABLE` anywhere in its text (case-sensitive, literal underscores), quick-pass mode is on for the current release run. The token in a file or in tool output does not count. Quick-pass authorizes every source-control and GitHub action in this pipeline:

- committing release preparation
- pushing `main`
- dispatching the workflow
- replacing the release notes with the approved text
- the failed-run recovery below: deleting a stray tag, committing and pushing the fix, rerunning

Continue without asking again, and report progress.

Quick-pass changes approval handling only. Validation, review and verification still apply. Stop for missing release-defining information (version, notes), unresolved validation failures, a run failure whose cause isn't clearly a workflow or script bug, or any action outside this pipeline. Never delete a published release or move a tag that a published release uses. Quick-pass ends when this release is verified, when the maintainer revokes it, or when the target version changes.

### Default: separate approvals

Without quick-pass, each of these is its own gate:

- each commit
- each push
- dispatching the workflow
- editing the release notes
- deleting a remote tag
- each rerun

Before an unauthorized gate, state the single next action and its remote effects, then ask. An approval covers only the action it was asked for and is consumed when performed. "Go", "proceed" or "continue" answers the question just asked, nothing more. Approving content (README wording, notes, version) does not approve the commit, push or dispatch that would publish it. Ask for those separately.

## Publish

1. **Commit** release preparation by path (`git add <paths>`), using conventional commits. Then **push `main`** and confirm the remote head equals local `HEAD`.
2. **Dispatch** with `gh workflow run native-release.yml --repo <owner>/<repo> --ref main -f version=<X.Y.Z> -f mode=release`. This publishes a public tag and release.
3. **Monitor.** A successful run takes about 10–15 minutes. `gh run watch` can exit early on a freshly queued run. Poll `gh run view <id> --json status,conclusion` in a background loop until `completed`, without blocking a foreground command past its timeout. When it finishes, list the step conclusions (`--json jobs`).
4. **On failure,** read `gh run view <id> --log-failed`, then check the remote state: `git ls-remote --tags origin`, `gh release view <version>`.
   - **Tag pushed, no release** (failed at or after "Create release commit and tag"): the tag blocks a rerun (`Tag already exists`). Fix the cause on `main`, commit and push it, delete the stray tag (`git push origin --delete <version>`), then rerun. Each step is gated unless quick-pass is on.
   - **Release already published, later validation failed:** stop and report. Recovery means deleting a public release, which is the maintainer's call.
   - The runner uses macOS `/bin/bash` 3.2. Under `set -u`, expanding an empty array as `"${a[@]}"` is unbound. Use `${a[@]+"${a[@]}"}`. Reproduce script fixes with `/bin/bash -c` locally before pushing them.
5. **Replace the notes** with the approved text: write them to a scratch file, then run `gh release edit <version> --notes-file <file>`.

## Verify

1. **Verify the release** with `gh release view <version> --json tagName,isDraft,isPrerelease,assets`. Expect not a draft, not a prerelease, and six assets: four `kasumi_*.xcframework.zip`, `notices.tar.gz` and `provenance.json`. Confirm the remote tag resolves to the `build: Prepare <version>` commit.
2. **Consumer check** (when asked, or when packaging changed). In the scratchpad, `swift package init --type executable`, then `swift package add-dependency https://github.com/<owner>/<repo>.git --from <version>`. Declare the tag's deployment targets in the consumer, for example `platforms: [.macOS(.v13), .iOS(.v15)]` for an iOS 15 release. SwiftPM's default macOS 12 is below the library's minimum. Keep a single entry point by deleting the template's `@main` file if you add `main.swift`. Build for macOS and for iOS Simulator at the tag's minimum. For iOS 15, use `swift build --triple arm64-apple-ios15.0-simulator --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)"`.
3. **Do not write docs-ai records for releases.** Release versions are not tracked in `docs-ai/`. Mention a version, build, or workflow run there only as a historical record that a process was completed before, and only when the maintainer asks for it or the work is a feature or fix that `docs-ai/` covers.
4. **Report** the version, release URL, run IDs, commits pushed, validation completed, and anything still open, such as a README install line that still needs the new version. App distribution is a separate release with `kasumi-app-release`.
