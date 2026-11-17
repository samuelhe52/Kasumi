# Development

Contributor runbook: toolchain setup, build quirks, verification procedures that
need a fixture or a manual check, and simulator or device notes that are hard to
find in the Makefile or source.

**Edit this file** in the same commit when a setup requirement, build step, or
simulator or device quirk changes, or when a non-obvious verification procedure
is added. Remove an entry when its quirk no longer applies. Each entry should be
a step, its gotcha, and a link to any record that explains why.

**Don't put these here:**

- Design rationale, measurements, rendering geometry, implementation mechanics,
  or feature descriptions. Put them in the relevant `docs-ai/` record and link it.
- Agent rules. Those live in `AGENTS.md`.
- Full command lists. Use `make help` and the Makefile.

## Setup

Needs Xcode 27, Swift 6.2+, and Rust (edition 2024) with the
`aarch64-apple-ios` and `aarch64-apple-ios-sim` targets. The repository pins
the Rust toolchain in `rust-toolchain.toml`. `make check` reports
the local toolchain without changing anything.

## Builds

- `make native` rebuilds the Rust XCFrameworks in `.build/native/` only when a
  `packages/Native*` input changed. Make targets run it; calling `swift` or
  `xcodebuild` directly needs `./scripts/build-native` first.
- `make native-local` selects locally built XCFrameworks; on a tagged release it
  changes the local manifest. `make native-release` restores the released targets.
  Unreleased development commits default to local binaries.
- Run the `Native binary release` GitHub workflow manually on the intended branch.
  CI builds ZIPs, creates a release-only commit and version tag, then publishes
  the same ZIPs. The tag commit does not advance the development branch. A failed
  publication may leave a tag or release that needs explicit recovery.
- Test mode requires a separate public repository, a prerelease version containing
  `-ci.`, and its `KASUMI_PRODUCTION_REPOSITORY` repository variable set to the
  production owner/name. Never use production for test mode. The repository needs
  Actions write access to create tags and releases. A separate-repository test
  passed; no production release has yet been published.
- `make run-sim` and `make test-ios` don't boot a simulator.
- New files under `apps/iOS/Kasumi/`, `ImportExtension/`, and `Shared/` are
  picked up without project edits (folder-synchronized groups). `Shared/` compiles
  into both the app and the "Import into Kasumi" action extension.
- Package resources live in `Sources/KasumiMarkdown/Bundled/`. A top-level
  `Resources` folder breaks iOS resource-bundle signing.
- Tests reach `fixtures/` through the `Tests/KasumiMarkdownTests/fixtures`
  symlink, which lets them run on the simulator.
- `swift run KasumiRender <input> <output.png|jpg|jpeg|pdf> [width]` renders a
  document without launching the app. See its options for preset, theme, profile,
  and dark. `--hyphenation-language TAG` overrides the selected profile: `auto`
  (front-matter `lang`, bounded prose stopword vote, then US English), `en-us`, `en-gb`, `de-1996`, `fr`, `es`, `it`,
  `pt`, `nl`, `sv`, `da`, `nb`, `fi`, `pl`, `cs`, or `ru`. Profiles expose the same
  `hyphenation_language` choice. Automatic selection is cached at parse time,
  examining at most 32,768 scalars or 4,096 words; explicit choices bypass it
  during layout. Front matter is recognized within the first 64 KiB/128 lines.
- Profiles use standard TOML via pinned `TOMLDecoder` 0.4.5; SwiftPM resolves it
  during `make build`/`make test`. No native TOML bridge or external binary is
  required. `--profile fixtures/NativeProfile.toml` exercises the authored profile.
  Only `[profile]` contributes overrides; `[anchor]` stores the profile factory,
  `[meta]` its name. Legacy duplicate-key/recovery behavior is rejected. Imports
  retain source until edited; canonical edits preserve unknown data, not comments.
  Verify with `make test FILTER=profileTOML`.
- Punctuation: `--punct-strategy faithful|spacing|fold` overrides a profile in
  either argument order. Render `fixtures/LanguageAndPunctuation.md` in all three
  modes to inspect protected prose/code/math/links, tables, footnotes and Japanese/
  Korean exclusions. `make test FILTER=PunctuationPolicyTests` checks geometry
  and original-text interactions. `make benchmark-typography` runs opt-in release
  benchmarks for bounded language analysis, punctuation scanning and full layout;
  ordinary test runs skip that performance test. No simulator is needed.
- Custom theme files: `--theme-file fixtures/CustomTheme.json` (add `--dark` for
  its dark palette). It is mutually exclusive with `--theme`. Verify parser,
  sparse inheritance, syntax colors and CLI raster output with
  `make test FILTER=themeFile`; no reader import UI or global registration.
- Launch scene: a `nil` title falls back to the app name, so the scene passes a
  one-space title and `LaunchLogotype` draws the wordmark. `titleViewFrame` spans
  everything above the browser sheet, not just the title.
- Reader toolbar: Actions is a persistent ellipsis control in the bottom toolbar.
  Present popovers and confirmations from that control, not from its transient
  menu items. Attach the toolbar outside the iPad inspector so the `DocumentGroup`
  receives it.

## Verification

Run the narrowest filter: `make test FILTER=<name>` for package tests and
`make test-ios FILTER=<name>` for simulator tests.

- **Code highlighting and panels:** `make test-syntax-native` and
  `make test FILTER='CodeSyntaxTests|CodeBlockPresentationTests'`. Render `fixtures/SyntaxHighlighting.md` with
  `make render INPUT=fixtures/SyntaxHighlighting.md OUTPUT=<file.png|pdf>` and
  `RENDER_ARGS='800 --theme one-light --code-caption --code-radius 10'` or
  `'360 --theme one-dark --code-caption --code-radius 10'` for wrapping. Omitting
  the code options verifies the library's caption-free, square defaults.
  Enabled captions repeat on PDF continuation pages with space reserved before
  packing code lines. These checks need no simulator. Use `make syntax-notices` to regenerate grammar
  notices from the pinned crate; registry/grammar provenance lives in
  `packages/NativeSyntax/Notices/`. See
  [002.006](../docs-ai/002-rendering-engine/006-syntax-highlighting.md).
  The native tests compare the synchronous span visitor with the count/fill
  bridge and check that the visitor runs one parser pass. See
  [002.025](../docs-ai/002-rendering-engine/025-one-pass-syntax-spans.md).
  `make app-check` compiles the reader's native Copy controls for a generic iOS
  device with signing disabled, without launching a simulator or device. Control
  identifier: `reader-code-copy-<block ID>`. See
  [002.008](../docs-ai/002-rendering-engine/008-code-block-style-boundary.md) for
  the style boundary, headless checks and interaction-validation limits.
- **Export:** `make test FILTER='Export|Pagination|PublicAPITests'`. Run it after
  any export change. Memory guard and measurements:
  [008](../docs-ai/008-reader-export/001-action.md).
- **Tables:** `make test FILTER='TableLayoutTests|Export|Pagination|PublicAPITests'`,
  plus `make test FILTER=ReaderTableEdgeTests` for the edge masks. Visual check:
  `fixtures/Tables.md`. See [002.005](../docs-ai/002-rendering-engine/005-table-layout.md).
- **Link styling:** render `fixtures/LinkIndicators.md` with `KasumiRender` in
  `--theme mono-light` and `--theme mono-dark`. See
  [002.003](../docs-ai/002-rendering-engine/003-link-decoration.md) and
  [002.004](../docs-ai/002-rendering-engine/004-underline-clearance.md).
- **Source editing:** `make test FILTER=DocumentSourceTests` and
  `make test-ios FILTER=DocumentSourceTests` (encoding round trips). In the app,
  edit `fixtures/SourceEditing.md`, close and reopen it, and check the saved bytes.
  See [009](../docs-ai/009-source-editor/000-plan.md).
  Check switching panes while typing: Preview dismisses the keyboard; Source
  resumes the previous caret and keyboard only if editing was active. The toggle
  and Done must stay in the bar (not the overflow menu), and both panes must blur
  softly under the bars, never clip. Type, pause, type again: undo takes two
  steps and reveals the change. Check Undo/Redo above the keyboard and in the
  bottom bar, rotating in Source then showing Preview, independent scroll
  positions, larger text sizes, and Reduce Motion. See
  [009.003](../docs-ai/009-source-editor/003-native-editor-chrome.md).
  Keyboard bar commands: `make test FILTER=SourceFormattingTests`. In the app,
  all seven buttons must fit with Hide Keyboard centered; check the heading
  long-press menu, and that each command takes one undo step. See
  [009.004](../docs-ai/009-source-editor/004-markdown-keyboard-bar.md).
- **Find:** open `fixtures/ReaderInteractions.md` with the keyboard visible. Check
  first and last results, wrapping, Match Case and Whole Words, clear, dismiss and
  reopen, rotation, and selection afterward. Identifiers: `find.searchField`,
  `find.previousButton`, `find.nextButton`, `find.doneButton`. `sim-use` 0.16 sees
  keyboard visibility but can't toggle the software keyboard; use Device Hub >
  Device > Keyboard > Toggle Software Keyboard for setup, then continue with
  `sim-use`. See [007.002](../docs-ai/007-reader-interactions/002-system-find-navigator.md).
- **Internal links:** open `fixtures/LinkJumps.md` and verify with a screen
  recording, not settled screenshots: heading fragments, returning upward,
  footnote taps, duplicate headings, percent-encoded fragments. Repeat with
  Reduce Motion on; jumps should be immediate.
- **Font transitions:** verify with a screen recording: card selection in both
  directions, Remove Download from the role toolbar, re-download completion, and
  reader size or preset changes at a scrolled position. Cards must not move during
  selection. See [005.002](../docs-ai/005-cjk-font-availability/002-font-management-transitions.md).

## Third-party notices

Run `make licenses` after a native or Swift dependency version, a bundled font, or
a notice file changes. It reads `notices/manifest.json`, checks the native
`Cargo.lock` files and `Package.resolved`, and rewrites
`Sources/KasumiMarkdown/Bundled/Notices/`. Commit the result with the change.

## Simulator and device notes

- **Clipboard prompt.** The iOS 27.2 simulator can't show the Paste from Other
  Apps > Ask prompt, and the read returns nil. Set the permission to Allow on the
  simulator. Test the prompt with `make run-device`.
- **Share-sheet import.** The action extension and the app share the App Group
  `group.com.samuelhe.Kasumi`, so a device build needs automatic signing to
  register it. In a share sheet the action sits under View More until promoted
  with Edit Actions. The extension opens `kasumi://import`. If the open is refused,
  the extension sheet stays; sharing from inside Kasumi alone doesn't trigger an
  import, so send Kasumi Home and launch it again.
- **Files handed to the app.** `DocumentGroup` doesn't open a file shared to an
  already-running scene (iOS 27.2), so `DocumentHandoff.swift` opens it through
  the document browser. Test by sharing from another app both while Kasumi runs
  and after terminating it. A share within a second or two of launch exercises the
  wait for the browser. Files didn't list folder contents on the 27.2 simulator.
  Any launch URL, including `kasumi://import`, skips `DocumentGroupLaunchScene`,
  so nothing that must run at launch belongs in that scene's views. On a device,
  `NSLog` didn't reach `idevicesyslog`; write a log file to `Library/Caches` and
  pull it with `xcrun devicectl device copy from --domain-type appDataContainer`.
  See [004.005](../docs-ai/004-ios-reader/005-warm-file-handoff.md).
- **Action icon.** The extension uses standalone transparent `ActionIcon@2x.png`
  and `ActionIcon@3x.png`, named by `CFBundleIconFiles`. Regenerate them with
  `swift design/icon/make_action_icon.swift`. On iOS 27.2, a replaced icon stayed a
  cached white tile while the build number stayed 1; raising the app and extension
  build numbers to 2 refreshed it. A fresh DerivedData alone didn't.
- **CJK fonts.** Apple's downloadable faces activate per process and stay cached
  for the whole simulator, so `make test-ios` still skips the 10 tests that need
  them after the app has downloaded them. To exercise failed downloads, launch a
  debug build with `-KasumiFailAppleFonts YES -onboarding.fonts-offered NO`. To
  preview the first-run font offer again, run `make run-device ONBOARDING=reset`
  on a device, or pass `-onboarding.fonts-offered NO` to `simctl launch` on the
  simulator. The first-run alert opens font management and doesn't start
  downloads. In the appearance sheet, `sim-use ui` omits the toolbar buttons; tap
  Fonts by coordinates. See [005](../docs-ai/005-cjk-font-availability/001-action.md).
- **Open a file at launch (debug builds only).** `-KasumiOpen <path>` skips the
  launch scene. The file is copied to the app's `Documents/Debug/` (replacing an
  earlier copy) and opened through the document browser, so relative images
  resolve against that folder:

  ```sh
  xcrun simctl launch --terminate-running-process booted com.samuelhe.Kasumi \
    -KasumiOpen "$PWD/fixtures/Rendering.md"
  ```

  Wait a few seconds before driving the UI. An unreadable path stays on the launch
  scene and logs `KasumiOpen: cannot read <path>`.

## Native reflow measurements

`make run-reflow-lab` opens the standalone Mac harness. `make check-reflow-lab`
runs its offscreen smoke check; `make benchmark-reader` (about 35 s) and
`make benchmark-reader-full` (about 13.5 min) run the fixed benchmark suite
on an M1 Pro, excluding the build, and
`make check-reflow-scrolling` samples
coverage during asynchronous native scrolling. `make check-fast-reflow-scrolling`
traverses the full 50k/200k mixed samples at 480 points every 8 ms after three
seconds idle, recording readiness and coverage. Add `REFLOW_IDLE_WARMUP=0` for a
same-binary control with idle preparation disabled. These commands require no
simulator. The Mac harness shares renderer and scheduling code but uses AppKit
and SDR bitmap painting; its results do not establish UIKit behavior or FPS.
See `tools/ReflowLab/README.md` for the native harness and
`benchmarks/reader/README.md` for the benchmark protocol.

For memory comparisons, use fresh Release processes with identical document,
width and viewport-paint lifetimes; record `/usr/bin/time -l` peak footprint and
inspect a held `heap -s --sumObjectFields <pid>` separately. Also paint a full
traversal: first-screen or preparation-only peaks miss retained paint growth.
OS/font caches are not reset. Debug signing may be needed to attach Instruments
to an ad hoc standalone probe; tracing overhead is excluded from timing results.
