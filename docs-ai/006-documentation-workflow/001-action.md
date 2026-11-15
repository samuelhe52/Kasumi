# 006 — Curated decision records: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-11-15 | Read the AniShelf skill, workflow, and index; inventoried `docs/` at `fbb13cb` and the commit history | Maintainer request |
| 2026-11-15 | Added the project-owned skill, its Claude Code symlink, and the `.gitignore` exception | `.agents/skills/write-ai-doc/SKILL.md`, `.claude/skills/write-ai-doc` |
| 2026-11-15 | Moved goal and development docs; split the status document into entries 001–005, the roadmap, and renderer gaps; removed `docs/` | [Plan mapping](000-plan.md#design--approach) |
| 2026-11-15 | Pointed `AGENTS.md` and the `Makefile` header at `docs-ai/` | `AGENTS.md`, `Makefile` |

## Outcome and current state (as of 2026-11-15)

`docs-ai/` holds the index, workflow, roadmap, development runbook, and entries
001–006. `docs/` no longer exists. Both agents find the skill: Codex through
`.agents/skills/`, Claude Code through `.claude/skills/`.

## Deviations from plan

None known.

## Validation

- A link check over `docs-ai/`, `AGENTS.md`, and the skill found no broken local
  links outside the skill's templates; every cited commit hash resolves; cited
  repository paths exist.
- `git check-ignore` confirms the skill is trackable while the rest of
  `.agents/skills/` stays ignored.
- `git diff --check` passed.
- No app code changed; no build, test, or simulator run.

## Open questions

None.
