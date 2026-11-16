# Development

Needs Xcode 27, Swift 6.2+, and Rust (edition 2024) with the
`aarch64-apple-ios` and `aarch64-apple-ios-sim` targets. `make help` lists the
targets.

## Builds

- Building targets run `make native`, which rebuilds the Rust XCFrameworks in
  `.build/native/` only when a `packages/Native*` input changed. Calling `swift`
  or `xcodebuild` directly needs `./scripts/build-native` once first.
- `make run-sim` and `make test-ios` don't boot a simulator.
- New files under `apps/iOS/Kasumi/`, `ImportExtension/`, and `Shared/` are
  picked up without project edits (folder-synchronized groups). `Shared/` is
  compiled into both the app and the "Import into Kasumi" action extension.
- Package resources live in `Sources/KasumiMarkdown/Bundled/`. A top-level
  `Resources` folder breaks iOS resource-bundle signing.
- Tests reach `fixtures/` through the `Tests/KasumiMarkdownTests/fixtures`
  symlink, which is what lets them run on the simulator.
- `swift run KasumiRender <input> <output.png|pdf> [width]` renders a document
  from the command line; see its options for preset, theme, profile, and dark.
- `DocumentGroupLaunchScene` draws the title and action buttons from plain
  strings and drops fonts and colors. A `nil` title falls back to the app name,
  so the scene gets a one-space title and `LaunchLogotype` draws the wordmark.
  `titleViewFrame` spans everything above the browser sheet, not the title, so
  the wordmark sits at a fixed offset from its top. `scenePhase` reads
  `background` inside the accessory views.
- Reader actions live in a single trailing ellipsis menu in the native bottom
  toolbar: Outline, Appearance, and Delete for imports. Present the appearance
  popover and delete confirmation from the persistent menu control, not its
  transient menu items. Attach the toolbar outside the iPad inspector so the
  `DocumentGroup` receives it. Back and the title remain in the navigation bar.

## Simulator and device notes

- **Clipboard prompt.** The iOS 27.2 simulator can't show the Paste from Other
  Apps > Ask prompt for any app (SpringBoard rejects the `pasted` daemon for
  lacking `com.apple.springboard.CFUserNotification`), and the read returns nil.
  Set the permission to Allow on the simulator; test the prompt with
  `make run-device`.
- **Share-sheet import.** The action extension and the app share the App Group
  `group.com.samuelhe.Kasumi` (`Kasumi.entitlements`, `ImportExtension.entitlements`),
  so a device build needs automatic signing to register it for your team. In a
  share sheet the action sits under View More until promoted with Edit Actions.
  The extension then opens `kasumi://import`, and the app imports when it becomes
  active. If the open is refused the extension's sheet stays, and sharing from
  inside Kasumi alone doesn't trigger an import: send Kasumi Home and launch it
  again.
- **Files handed to the app.** SwiftUI's `DocumentGroup` doesn't open a file
  shared to a scene that is already running (iOS 27.2), so
  `DocumentHandoff.swift` opens it through the document browser instead. To
  test, share from another app with the system share sheet both while Kasumi
  runs and after terminating it; Files didn't list folder contents on the iOS
  27.2 simulator. A share within a second or two of launch exercises the wait
  for the browser's presentation. Any launch URL, including the Import action's
  `kasumi://import`, makes SwiftUI skip `DocumentGroupLaunchScene` and show its
  plain browser, so nothing that must run at launch may live in the launch
  scene's views. On a device, `NSLog` didn't reach `idevicesyslog`; a log file in
  `Library/Caches`, pulled with `xcrun devicectl device copy from --domain-type
  appDataContainer`, worked. See
  [004.005](../docs-ai/004-ios-reader/005-warm-file-handoff.md).
- **Action icon.** The extension uses standalone transparent `ActionIcon@2x.png`
  and `ActionIcon@3x.png`, named by `CFBundleIconFiles`, not a normal image set.
  Regenerate them with `swift design/icon/make_action_icon.swift`. On iOS 27.2,
  replacing the icon while keeping build 1 left a cached white tile; increasing
  the app and extension build numbers to 2 refreshed it without an uninstall.
  Rebuilding into fresh DerivedData alone did not refresh that installed icon.
- **CJK fonts.** Apple's downloadable faces are activated per process: the app
  re-requests them at launch, and `make test-ios` still skips the 10 tests that
  need them even after the app downloaded them. iOS caches them for the whole
  simulator, so to see onboarding's open fallbacks again, launch with
  `-KasumiFailAppleFonts YES -onboarding.fonts-offered NO` (debug builds). The
  appearance sheet's toolbar buttons are missing from `sim-use ui`; tap the Fonts
  button by coordinates. See [005](../docs-ai/005-cjk-font-availability/001-action.md).
  To see the first-run font offer again on a device, run `make run-device
  ONBOARDING=reset`. It passes `-onboarding.fonts-offered NO` for that launch only.
  The offer also needs at least one recommended Apple face still missing, and
  iOS keeps downloaded faces system-wide, so it won't appear once they're installed.
- **Open a file at launch (debug builds only).** Pass `-KasumiOpen <path>` to skip
  the launch scene. The file is copied into the app's `Documents/Debug/`
  (replacing an earlier copy) and opened through the document browser, so
  relative images resolve against that folder:

  ```sh
  xcrun simctl launch --terminate-running-process booted com.samuelhe.Kasumi \
    -KasumiOpen "$PWD/fixtures/Rendering.md"
  ```

  Give it a few seconds before driving the UI. An unreadable path stays on the
  launch scene and logs `KasumiOpen: cannot read <path>`.
