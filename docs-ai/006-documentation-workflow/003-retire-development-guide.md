# 006.003 — Retire the development guide

## Context

[006.002](002-development-guide.md) kept `docs/development.md` as a trimmed
contributor runbook. By 2026-11-19 it had grown to about 250 lines and broke its
own scope rules. It carried feature descriptions, rendering geometry, measurements
and per-feature acceptance checklists, and a release status line. A review on
2026-11-19 found that most of it duplicated the entries it linked, `make help`,
the CLI usage string, the release skill, or the benchmark and Reflow Lab READMEs.
About a dozen gotchas were found nowhere else.

## Change

Maintainer decision: delete `docs/development.md`, move the few cross-feature
gotchas to `AGENTS.md`, and drop the rest. The ownership rule is now: a feature's
verification recipe and feature-specific simulator or device quirks live in its
entry; gotchas that span features live in `AGENTS.md`; public build requirements
live in the README.

| Moved content | New home |
| --- | --- |
| `make check`; simulator boot behavior of `run-sim`, `launch-sim`, `test-ios`; `make licenses` | `AGENTS.md` Workflow |
| Folder-synchronized groups, the fixtures symlink | `AGENTS.md` Project layout |
| `-KasumiOpen`, device logging | `AGENTS.md` Simulator and device |
| Narrow test commands through `make test FILTER=` / `make test-ios FILTER=` | `AGENTS.md` Testing (replaces `swift test --filter`, which skips `make native`) |
| Image idle-preparation launch environment | [002.032](../002-rendering-engine/032-idle-layout-for-local-images.md) |

Removed as out of scope, by maintainer decision: the ad hoc memory-comparison
method, the release test-mode repository variable and permissions (the workflow
enforces them), the `make format` tool list, the direct `swift`/`xcodebuild`
note (the Makefile header covers it), the `Bundled` resource folder, the
`sim-use` keyboard limit, screen recordings for animations, and the
feature-specific device notes (simulator clipboard prompt, App Group signing, the
appearance sheet's `sim-use` gap).

Dropped as duplicates: per-feature verification recipes (already in 002.003–
002.006, 002.008, 002.026–028, 003.002, 004.004, 004.005, 004.008, 005.001,
005.002, 007.002, 008, 009.003, 009.004), the action-icon cache (004.004's icon
correction), the hyphenation, TOML profile and punctuation details (002.009,
002.011, 002.012, the `KasumiRender` usage string), the launch-scene title and
reader-toolbar gotchas (code comments in `LaunchLogotype.swift` and
`ReaderScreen.swift`), the link-jump checks (in `fixtures/LinkJumps.md`), the
release recovery steps (the release skill and
[010](../010-binary-distribution/001-action.md)), the Reflow Lab and benchmark
commands (their READMEs), and the `make clean` description (`make help`).

Links that pointed at the guide were updated in `AGENTS.md`, the `Makefile` header,
`docs/library.md`, `docs-ai/README.md`, `docs-ai/workflow.md`, both skills,
[004](../004-ios-reader/000-plan.md), and [009.002](../009-source-editor/002-editor-experience.md).
Entries that mention the guide only as history ("`docs/development.md` unchanged")
were left as written.

The guide had said `make test-ios` doesn't boot a simulator. It runs
`xcodebuild test` against a named simulator destination, which boots a shut-down
simulator. `AGENTS.md` now says it can boot one. This is inferred from
`xcodebuild` behavior, not rerun.

Rejected: trimming the guide to its unique items. It would have been about 60
lines that overlap `AGENTS.md`'s audience and rules, and the same drift would
return.

## Refs

`AGENTS.md`, `docs-ai/workflow.md`, `docs-ai/README.md`,
`.agents/skills/kasumi-release/SKILL.md`, `.agents/skills/write-ai-doc/SKILL.md`. No code changed; no build, test, or
simulator run.
