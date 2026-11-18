# 006 — Curated decision records: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-11-15 |
| Origin | Maintainer request on 2026-11-15: re-initialize the project's docs with docs-ai, following the maintainer's AniShelf project. |
| Related | [Workflow](../workflow.md), [index](../README.md) |

## Background

Kasumi's docs were `docs/goal.md`, `docs/development.md`, and `docs/status.md`.
`status.md` mixed current state, validation notes, known issues, the roadmap, a
font plan, and renderer gaps, and was edited in almost every commit. Decisions and
their reasons lived only in commit messages.

## Goals

- `docs-ai/` as the single home for the goal, decisions, outcomes, roadmap, and
  runbooks, with a project-owned `write-ai-doc` skill for both agents.
- Retire the running status document without losing any of its content.
- Backfill a few retrospective entries for the decisions the project already
  depends on, rather than every commit.

## Design / approach

| Old content | New home |
| --- | --- |
| `docs/goal.md` | [001-library-and-reader/goal.md](../001-library-and-reader/goal.md) (moved unchanged) |
| `docs/development.md` | Stayed in `docs/` (moved to `docs-ai/` at first, then back), then retired into `AGENTS.md`, the README, and entries; see amendments |
| Status: current state and validation | Action records of [001](../001-library-and-reader/001-action.md), [003](../003-public-rendering-api/001-action.md), [004](../004-ios-reader/001-action.md) |
| Status: known reader issues | [004 open questions](../004-ios-reader/001-action.md#open-questions) |
| Status: "Not yet" items | [Roadmap](../roadmap.md), [renderer gaps](../002-rendering-engine/renderer-gaps.md), [001 open questions](../001-library-and-reader/001-action.md#open-questions) |
| Status: reader milestones | [Roadmap](../roadmap.md) |
| Status: Fonts | [005](../005-cjk-font-availability/000-plan.md) (Planned) |
| Status: Renderer gaps | [renderer-gaps.md](../002-rendering-engine/renderer-gaps.md) |

The skill lives at `.agents/skills/write-ai-doc/SKILL.md`, tracked through a
`.gitignore` exception (the rest of `.agents/` stays local), and Claude Code finds
it through the tracked symlink `.claude/skills/write-ai-doc`. `AGENTS.md` points
to the skill, the workflow, and the runbook.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Remove `docs/` entirely (reversed for `development.md`; see amendment) | AniShelf keeps `docs/` for public tutorials; Kasumi has none (its README was removed until the project matures, `7ddcf1d`), so a second tree would only split the docs. |
| No running status document | The status file was the main source of churn. What shipped belongs in action records, what's next in the roadmap, and known limits in gap lists. |
| Five backfilled entries, not one per commit | Git keeps routine history; entries cover decisions later work depends on. |
| Keep the skill project-owned, not installed with `npx skills` | Same as AniShelf: it's adapted to the project, so no `skills-lock.json` and no upstream updates. |

## Validation and acceptance criteria

Every line of `docs/status.md` at `fbb13cb` has a new home; local links and cited
paths resolve; cited commits exist; `git diff --check` passes. No app code
changes, so no build, test, or simulator run.

## Amendments

- Updated 2026-11-15: `development.md` moved back to `docs/` and trimmed — see [002-development-guide.md](002-development-guide.md)
- Updated 2026-11-19: retired `docs/development.md`; corrected the mapping row above and the action record's current state — see [003-retire-development-guide.md](003-retire-development-guide.md)
