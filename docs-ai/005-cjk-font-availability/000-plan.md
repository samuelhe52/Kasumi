# 005 — CJK font availability on iOS: Plan

| Field | Value |
| --- | --- |
| Status | Planned |
| Anchor date | 2026-11-14 |
| Origin | Found while porting the library to iOS (`ccf0bee`); plan carried over from the status document at `fbb13cb` during the docs-ai migration on 2026-11-15. Not yet started. |
| Related | [003](../003-public-rendering-api/000-plan.md), [renderer gaps](../002-rendering-engine/renderer-gaps.md), [roadmap](../roadmap.md) (reader milestone 5) |

## Background

iOS doesn't ship the CJK faces the presets use (Songti SC, SimSong, Kaiti,
Fangsong, Heiti), so CJK text falls back to PingFang or the system font, and 10
library tests that pin those faces skip on the iOS simulator. The faces are
licensed by Apple and can't be redistributed; on iOS they are only available
through Core Text's on-demand system font download.

## Goals

- Presets render CJK text in their intended faces when the user has them, and in
  a good open face when not.
- The library stays stateless and never downloads.

### Non-goals

- Onboarding downloads; onboarding is out of scope for the first version.

## Design / approach

- Library: each font role resolves through a fallback chain. Today the chain is
  fixed per role (Han: the preset's family, Songti SC, PingFang SC, Songti TC) in
  `Sources/KasumiMarkdown/FontFamilyResolver.swift` and
  `Sources/KasumiMarkdown/CJKFontRole.swift`. Move the chain into presets, for
  example Songti SC, then an open serif CJK face, then the system font.
- App: a font store with a download screen in Settings. It requests Apple's faces
  through the system download and fetches openly licensed fonts (for example
  Source Han, Noto CJK, LXGW WenKai) into its container, registering them for the
  process with `CTFontManagerRegisterFontURLs`. `FontAvailability` reports what's
  missing.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Downloads live in the app, not the library | The library holds no app state ([goal](../001-library-and-reader/goal.md)). |
| Don't bundle Apple's CJK faces | Their license forbids redistribution. |

## Validation and acceptance criteria

Proposed: the skipped CJK tests pass on the simulator once faces are downloaded;
a simulator run shows the download screen and CJK text switching faces after a
download.

## Amendments

None yet.
