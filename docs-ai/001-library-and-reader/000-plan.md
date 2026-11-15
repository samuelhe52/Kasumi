# 001 — Reusable library and universal iOS reader: Plan

| Field | Value |
| --- | --- |
| Status | Implemented (retrospective) |
| Anchor date | 2026-11-14 |
| Origin | Maintainer decision on 2026-11-14 to refocus the project (`d7cff70`). Reconstructed on 2026-11-15 from Git history and earlier docs during the docs-ai migration ([006](../006-documentation-workflow/000-plan.md)); it did not precede the work. |
| Related | [Product goal](goal.md) (living), [002](../002-rendering-engine/000-plan.md), [003](../003-public-rendering-api/000-plan.md), [004](../004-ios-reader/000-plan.md) |

## Background

The project began as a native macOS Markdown reader whose typography and parts of
its rendering behavior were modeled on an existing application. By `3914150` it
had a working macOS app with its own paragraph engine, math, Mermaid diagrams,
profiles, themes, and export ([002](../002-rendering-engine/000-plan.md)).
Analysis tooling and provenance data lived alongside the code.

## Goals

- Make the rendering core a reusable Swift package that any iOS or macOS app can
  adopt, holding no app state.
- Make the product a universal iPhone/iPad reader built only on that package's
  public API.
- Keep builds and tests self-contained: nothing outside the repository and its
  pinned dependencies.

### Non-goals

- Full parity with the original macOS app (`d7cff70`).
- Keeping the macOS app; it was removed in `55b03b8`. `KasumiRender` remains as a
  macOS CLI for rendering documents.

## Design / approach

1. Extract the core into `Sources/KasumiMarkdown` as a library product, with the
   Rust dependencies built as static XCFrameworks for macOS, iOS, and the iOS
   simulator and consumed as binary targets (`55b03b8`).
2. Add a hand-written universal iOS project with a folder-synchronized source
   group under `apps/iOS/` (`33e4179`).
3. Rename the project to Kasumi / KasumiMarkdown (`21e3321`).
4. Remove the analysis tooling, reference identifiers, and provenance data from
   the tracked tree; keep only frozen measurements in `fixtures/reference/`
   (`f181339`, `910384a`).
5. Port the library off AppKit to Core Graphics and Core Text so it runs on iOS
   (`ccf0bee`), then expose a deliberate public API
   ([003](../003-public-rendering-api/000-plan.md)).

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Library plus iOS reader instead of a macOS app | Maintainer decision (`d7cff70`). The macOS app was dropped rather than kept as a second client. |
| Rename the `Resources` folder to `Bundled` | A top-level `Resources` folder breaks iOS resource-bundle signing (`55b03b8` message). |
| Ship Rust dependencies as prebuilt XCFrameworks | So adding the package is the only setup step for clients ([goal](goal.md)). The frameworks are generated, not committed; see Open questions in the action record. |
| Remove reference tooling from the repository | Maintainer decision recorded in `AGENTS.md`: builds and tests must not depend on anything outside the repository. Provenance records are kept outside the tracked tree. |
| Keep frozen reference measurements as regression data | The measurements still protect layout behavior; identifiers tying them to the analysis were stripped (`f181339`). |

## Evidence and recovered rationale

- Source documents: commit messages `d7cff70`, `55b03b8`, `33e4179`, `21e3321`,
  `f181339`, `910384a`, `ccf0bee`; `docs/goal.md` as of `fbb13cb` (now [goal.md](goal.md)).
- Recalled discussion (agent memory, 2026-11-14): the maintainer prefers the best
  product behavior over avoiding inherited solutions, wants copied expressive
  assets (a theme palette, one theme, one string) replaced with Kasumi's own when
  those areas are touched, and wants a future README to credit the project's
  origin honestly.
- Inference: none beyond what the commit messages state.

## Validation and acceptance criteria

From the goal: the library builds and its tests pass on macOS and the iOS
simulator, and the app runs end to end on the simulator.

## Amendments

None yet.
