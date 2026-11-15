# 004.004 — "Import into Kasumi" share-sheet action

## Context

Kasumi opens Markdown and plain text from the Files app because `Info.plist`
declares them as Viewer document types, but it never appears in a share sheet.
The share sheet's bottom row lists Action extensions, and other apps (for
example Qwen's "导入到千问") use one to take a file in. Kasumi had no extension
target, so the only ways in were Paste Markdown, Open URL, and the document
browser.

## Change

- A new `ImportExtension` target is an Action extension
  (`com.apple.ui-services`) named "Import into Kasumi". Its activation rule
  matches exactly one attachment that conforms to `public.plain-text`, which
  covers Markdown (Kasumi's imported `net.daringfireball.markdown` type conforms
  to it), `.txt`, and shared text selections.
- The extension copies the shared file into an App Group container
  (`group.com.samuelhe.Kasumi`), in `Inbox/<uuid>/<name>`, and shows a short
  confirmation sheet ("Added to Kasumi"). It then asks the system to open
  `kasumi://import` through its hosting `UIScene`; if that succeeds the sheet
  dismisses and Kasumi comes forward, and if not the sheet stays and tells the
  user to open Kasumi. The app registers the `kasumi` scheme in `Info.plist` and
  has no URL handler: becoming active is what triggers the import.
- When the app becomes active, `LaunchStore.importSharedFiles()` moves every
  pending inbox file into `Documents/Imported/` through the same naming rules as
  the other imports (" 2", " 3", `.md` added to names without a Markdown or text
  extension), clears the inbox entry, and opens the newest file through the
  document browser, as Paste and Open URL do.
- `Imported` is a third `ImportFolder`, so imported documents get the same Delete
  button and folder-level deletion as pasted and downloaded ones.
- `apps/iOS/Shared/ImportInbox.swift` holds the group identifier, the inbox
  location, and the size limit (5 MB, as for Open URL). Both targets compile it.

## Decisions

| Choice | Reason and alternative |
| --- | --- |
| Action extension, not Share extension | Share extensions land in the app row; "Import" belongs in the action row with Save to Files. Both can share the inbox plumbing if a Share extension is wanted later (maintainer decision, from the planning thread). |
| Copy into the App Group, then into Documents | The extension's file URL is temporary and its sandbox can't write to the app's Documents. The group container is the only shared storage. Copying into Documents rather than keeping the original matches 004.002: imports persist and show in the browser. |
| Open Kasumi from the extension with `UIScene.open`, keep the sheet as a fallback | The first version only saved and told the user to open Kasumi; the maintainer wanted the app to open by itself. `UIApplication.open` and `NSExtensionContext.open` aren't usable here, so the extension opens a `kasumi://import` URL through its own window scene. An earlier attempt found a responder that answered `openURL:options:completionHandler:` and called it through the Objective-C runtime with an options dictionary; the responder was a `UIScene`, which expects an options object, and the extension aborted with an unrecognized selector (`universalLinksOnly`). The maintainer confirmed on 2026-11-16 that the open works; the fallback sheet covers a refusal on other configurations. |
| Exactly one attachment in the activation rule | The document browser delegate's multi-pick behavior is unverified, and multi-file import is not needed yet. |
| Unique inbox folder per import | Two imports of `notes.md` before the app runs can't overwrite each other; the app does the user-visible naming. |
| Plain-text predicate, not a file-only rule | Dictionary activation rules can't filter by type, and a type-filtering predicate is the only way to avoid showing the action for images and PDFs. Selected text therefore also qualifies; it imports as a `.md` file. |
| English display name only | The project has no localization yet (`knownRegions` is `en, Base`), so a localized `InfoPlist.strings` for 导入到 Kasumi is left for when the app is localized. |

## Validation

Built with `make app` and run with `make run-sim` on the iPhone 18 Pro simulator,
iOS 27.2, driven with `sim-use` (2026-11-16):

- The built app embeds `PlugIns/ImportExtension.appex` with display name "Import
  into Kasumi", the `com.apple.ui-services` point, and the activation predicate.
- Long-pressing `Mathematics-1.md` in the launch scene's Recents and choosing
  Share lists "Import into Kasumi" under View More, in the action list. It is not
  in the first row of actions, which is the usual state of a newly installed
  extension (the user can promote it with Edit Actions).
- Running it showed the "Added to Kasumi" sheet and wrote
  `Inbox/<uuid>/Mathematics-1.md` in the App Group container.
- Sharing from inside Kasumi leaves the app in the foreground, so nothing
  imported until the app was sent Home and launched again. Then the file moved
  to `Documents/Imported/Mathematics-1.md`, the inbox emptied, and the file
  opened in the reader with the Delete button. That run predates the
  open-Kasumi step.
- Open Kasumi from the extension: the first implementation crashed the
  extension (see the decision above) after the copy had already succeeded. The
  `UIScene.open` replacement compiles and was installed, but I did not see the
  result. The maintainer then tested it themselves and reported that it works
  (2026-11-16; device or simulator and OS version not recorded).

Not verified by me: a name clash (" 2" naming reuses `ImportFolder.save`, which the
other imports already exercise); a shared text selection; a file over 5 MB; a
cold launch (the app was backgrounded, not terminated); the failure sheet;
iPad; a physical device, where the App Group must be registered by automatic
signing with the maintainer's team (`make run-device` passes
`-allowProvisioningUpdates`).

## Open questions

- Localized display name.
- The action's icon renders as a solid white tile in the share sheet. On the
  simulator none of these changed it: no extension icon; an `AppIcon` set in the
  extension with a transparent black glyph (compiled with alpha, and
  `CFBundleIcons` generated); and `CFBundleSymbolName` = `text.document` at the
  top level of the extension's `Info.plist`, after an app reinstall and a restart
  of the icon and sharing services. Apple's Tech Talk 210 says an SF Symbol name
  goes in `CFBundleSymbolName`; the placement and whether iOS 27 reads it are
  unconfirmed. The top-level key is left in place as the documented form.

## Refs

- `apps/iOS/Shared/ImportInbox.swift`
- `apps/iOS/ImportExtension/ImportViewController.swift`
- `apps/iOS/ImportExtension-Info.plist`, `apps/iOS/ImportExtension.entitlements`,
  `apps/iOS/Kasumi.entitlements`
- `apps/iOS/Kasumi.xcodeproj/project.pbxproj` (new target, embed phase)
- `apps/iOS/Kasumi/LaunchActions.swift`
- `apps/iOS/Kasumi/KasumiApp.swift`
