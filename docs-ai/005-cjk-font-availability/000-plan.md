# 005 — CJK font availability on iOS: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-11-14 |
| Origin | Found while porting the library to iOS (`ccf0bee`); plan carried over from the status document at `fbb13cb` during the docs-ai migration on 2026-11-15. Scope, placement and onboarding decided with the maintainer on 2026-11-16, before implementation; see Amendments. |
| Related | [003](../003-public-rendering-api/000-plan.md), [renderer gaps](../002-rendering-engine/renderer-gaps.md), [roadmap](../roadmap.md) |

## Background

iOS doesn't ship the CJK faces the presets use (Songti SC, Songti TC, SimSong,
Kaiti SC, STFangsong, STXihei, STHeiti), so CJK text falls back to PingFang or
the system font, and 10 library tests that pin those faces skip on the iOS
simulator. The faces are licensed by Apple and can't be redistributed; on iOS
they are only available through Core Text's on-demand system font download. All
of them were listed as downloadable on the iOS 27.2 simulator (2026-11-16).

## Goals

- Presets render CJK text in their intended faces when the user has them, and in
  a good open face when not.
- Users can see which face each role uses, and choose the open face over Apple's.
- New users are offered the faces once, in onboarding, and can skip it.
- The library stays stateless and never downloads.

### Non-goals

- Blocking the app until fonts are downloaded.
- Bundling any CJK font in the app.

## Design / approach

- Library: `FontFamilyResolver.chain(for:role:)` puts each Apple face's open
  substitute directly after it (Songti SC → Noto Serif SC, Songti TC → Noto
  Serif TC), then the generic Han chain. Kai emphasis uses LXGW WenKai Lite when
  Apple's Kaiti is missing, and also over the open Songti substitutes. The
  library only looks fonts up; it never downloads.
- App: a font catalog (`FontPackage`) of Apple packages and open packages. A
  `FontStore` requests Apple's faces through
  `CTFontDescriptorMatchFontDescriptorsWithProgressHandler` and fetches open
  fonts from pinned upstream files into Application Support, checking size,
  SHA-256 and PostScript name before registering them for the process.
- Store screen: reached from the appearance sheet's Fonts button.
- Onboarding: a skippable first-run alert opens font management if a recommended
  Apple face is missing. Users choose individual downloads in the store.
- The reader re-renders when `FontStore.revision` changes.
- User choice: `RenderStyle.preferredOpenFamilies` (public) moves a registered
  open face ahead of the Apple face it replaces. The store groups faces by role
  (`FontChoice`: Simplified, Emphasis, Traditional, plus supporting Apple faces),
  marks the selected face, and lets users tap another downloaded face to select it.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Downloads live in the app, not the library | The library holds no app state ([goal](../001-library-and-reader/goal.md)). |
| Don't bundle Apple's CJK faces | Their license forbids redistribution. |
| Open faces are fallbacks, not downloaded up front | The renderer only uses an open face when the Apple face is missing, so downloading both by default wastes about 38–68 MB. Maintainer chose the fallback approach over downloading both sets. |
| Onboarding offers, never requires | Downloads can fail or be offline, and text still renders in PingFang meanwhile. Maintainer chose "offer, skippable". |
| Store opens from the appearance sheet | There is no Settings screen yet. Maintainer chose this over adding one. |
| Region subset builds (Noto Serif SC/TC SubsetOTF, LXGW WenKai Lite) | About half the size of the full CJK builds (11.6 MB vs 24.5 MB for Noto Regular) and they cover the region's text. |
| Substitute map in the resolver, not per-preset chains | Keeps the profile schema unchanged. The earlier plan to move chains into presets was dropped; it can still happen if a preset needs a different chain. |
| Per-role choice, not one global "prefer open fonts" switch | Maintainer asked for users to decide between replacement and system face; roles are independent (someone may want WenKai emphasis over Songti body). |
| Choice passed through `RenderStyle`, not stored in the library | The library holds no app state; the app persists the choice and passes family names. |
| Re-request Apple faces at every launch | Core Text activates a downloaded Apple face only for the process that requested it; a cached face activates without network. |

## Validation and acceptance criteria

- The resolver chain test in `PublicAPITests` covers substitute order.
- A simulator run shows onboarding, Apple downloads, the store, an open-font
  download, a relaunch keeping the faces, and the fallback flow.
- Original criterion "the skipped CJK tests pass on the simulator once faces are
  downloaded" was not met; see the action record.

## Amendments

- Updated 2026-11-16: scope, onboarding (previously a non-goal), placement, and
  the resolver substitute map decided before implementation; Background, Goals,
  Design and Alternatives rewritten accordingly. Implemented — see
  [001-action.md](001-action.md).
- Updated 2026-11-16: maintainer review asked to show which face is in use and
  to let users choose the open face; added the per-role choice and
  `RenderStyle.preferredOpenFamilies` before commit. Goals, Design and
  Alternatives updated in place.
- Updated 2026-11-16: stable font controls, explicit download management, and
  prepared reader transitions — see
  [002-font-management-transitions.md](002-font-management-transitions.md).
- Updated 2026-11-16: role-first navigation, symmetric choice cards, toolbar
  download management, and removal of section boilerplate — see
  [003-role-first-layout.md](003-role-first-layout.md).
- Updated 2026-11-16: replaced the first-run sheet and automatic downloads with
  a missing-font alert leading to font management — see
  [004-font-offer-alert.md](004-font-offer-alert.md).
