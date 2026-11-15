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
- **Action icon.** The extension uses standalone transparent `ActionIcon@2x.png`
  and `ActionIcon@3x.png`, named by `CFBundleIconFiles`, not a normal image set.
  Regenerate them with `swift design/icon/make_action_icon.swift`. On iOS 27.2,
  replacing the icon while keeping build 1 left a cached white tile; increasing
  the app and extension build numbers to 2 refreshed it without an uninstall.
  Rebuilding into fresh DerivedData alone did not refresh that installed icon.
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
