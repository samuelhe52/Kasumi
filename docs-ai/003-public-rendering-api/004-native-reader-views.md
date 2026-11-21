# 003.004 — Native reader views

Status: Planned. The maintainer approved the implementation on 2026-11-21 after reviewing a local plan and a separate Opus review.

## Public boundary

Add the opt-in `KasumiMarkdownUI` SwiftPM product. `KasumiMarkdown` remains the headless renderer. Native `MarkdownReaderView` and its SwiftUI wrapper own a viewport, immutable snapshots, reflow, clipped painting, wide-table scrolling, and transient interaction state. Host apps own files, outline controls, persisted reading position, appearance choices, external URL opening, and export. Kasumi supplies its own code-block Copy control and preserves Preview suspension, font invalidation, and the current scroll behavior. ReflowLab uses the public AppKit view for its real window and its coverage probes, not a second scheduler.

Native Find uses UIKit on iOS 16+ and AppKit on macOS 13+. The SwiftUI binding mirrors native panel visibility; a toolbar button belongs to the host. Programmatic search, match navigation and highlights work independently of the panel, including on iOS 15. No second panel ships with the library. Native and programmatic Find do not compete for the same viewport. Selection uses renderer geometry and the iOS 15 responder edit menu when the modern menu is unavailable.

The view takes an opt-in remote image provider. Resolution yields dimensions and a bounded size-aware rasterizer; cached encoded data can use the library decoder. The view tracks unresolved occurrences near the viewport, scopes its display cache to the provider and revision, rejects stale completions, and preserves the reading anchor when geometry changes. Drawing never fetches or decodes. No provider, decline, and failure never trigger fallback networking. Local and embedded images keep their existing path. The provider is reader-only; headless export and explicit export preload retain their existing contract.

## Validation

Compile a separate consumer at the iOS 15 floor, including guarded Find. Exercise selection, copy, links, scrolling, and custom search on iOS 15 if a runtime is available; report compile-only coverage otherwise. On a newer iOS runtime exercise the app cutover, native Find, and its binding. Run ReflowLab window and coverage probes, focused renderer and image-policy checks, and exercise both native forms and the SwiftUI wrapper without raising the package deployment floors.
