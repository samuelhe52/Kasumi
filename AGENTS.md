# AGENTS.md

## Workflow

- Use Makefile commands for dev routines; `make help` lists them and `make check` reports the local toolchain.
- Ask before booting a simulator. Drive the simulator with `sim-use`. `make run-sim` and `make launch-sim` need an already booted simulator; `make test-ios` runs `xcodebuild test` on `SIMULATOR` and can boot it.
- If the user asks to perform a change in a new worktree, create that worktree under `.worktrees/` in the repository root.
- Run `make licenses` after a native or Swift dependency version, a bundled font, or a notice file changes, and commit the regenerated `Sources/KasumiMarkdown/Bundled/Notices/` with the change.

## Documentation

- [`docs-ai/README.md`](docs-ai/README.md) indexes the product goal, roadmap, and decision records.
- Use the `write-ai-doc` skill for substantial features and decision-shaping fixes, as defined in [`docs-ai/workflow.md`](docs-ai/workflow.md). There is no status document or development guide; don't add one.
- Use the `kasumi-release` skill for KasumiMarkdown library releases (GitHub release with prebuilt binaries) and the `kasumi-app-release` skill for iOS app releases (Xcode Cloud, TestFlight, App Store).

## Project layout

- New files under `apps/iOS/Kasumi/`, `apps/iOS/ImportExtension/`, and `apps/iOS/Shared/` are picked up without project edits (folder-synchronized groups). `Shared/` compiles into both the app and the "Import into Kasumi" action extension.
- The Mac app (`KasumiMac` target, product `Kasumi.app`) lives in the same project with sources in `apps/macOS/Kasumi/`. `apps/Common/` holds app code compiled into both the iOS and Mac apps; keep UIKit and AppKit out of it. Both folders are folder-synchronized groups. Use `make run-mac` to build and launch it; no simulator is involved.
- Tests reach `fixtures/` through the `Tests/KasumiMarkdownTests/fixtures` symlink, which lets them run on the simulator.

## Simulator and device

- Debug builds accept `-KasumiOpen <path>`, which skips the launch scene, copies the file into the app's `Documents/Debug/` (replacing an earlier copy) and opens it through the document browser, so relative images resolve against that folder. Wait a few seconds before driving the UI; Example: `xcrun simctl launch --terminate-running-process booted com.samuelhe.Kasumi -KasumiOpen "$PWD/fixtures/Rendering.md"`.
- On a device, `NSLog` didn't reach `idevicesyslog`. Write a log file to `Library/Caches` and pull it with `xcrun devicectl device copy from --domain-type appDataContainer`.

## UI

- On iOS, always use the `.soft` style for toolbar edge effects. In UIKit, set `UIScrollView.topEdgeEffect.style = .soft`. In SwiftUI, use `.scrollEdgeEffectStyle(.soft, for: .top)`. Apply this everywhere a toolbar appears. The Mac app keeps the system default style.
- On iOS, sheets are dismissed by an X button (`Button(..., systemImage: "xmark")`) in the leading toolbar slot (`ToolbarItem(placement: .cancellationAction)`). Do not add a Done button. Mac sheets end with a Cancel button and a default action button at the bottom trailing edge.

## Reference materials

- `fixtures/reference/` holds frozen reference measurements that tests compare against. Treat them as regression data: when a deliberate change alters a covered behavior, update the expectation in the same commit and say so.
- No reference application, binary or analysis tooling is part of this project. Builds and tests must not depend on anything outside the repository and its pinned dependencies.

## Testing

- Add the smallest set of tests that protects distinct behavior, and prefer extending existing tests. Run the narrowest relevant command (`make test FILTER=<name>`, or `make test-ios FILTER=<name>` for simulator tests) unless there is a reason to run the full suite. Simple wiring, copy, or layout changes may need no new tests.

## Commits

- Do not commit unless asked. Organize work into coherent commits. Do not amend, rebase, or rewrite commits you did not create in the current task without asking.
- Other agents may be editing the same working tree. Stage only changes within the commit's scope, by path (`git add <paths>`); never use `git add -A`, `git add .`, or `git commit -a`.
- Use conventional commits: `<type>: <subject>`, with imperative, capitalized, concise subjects and no trailing period.
