# Kasumi design and decision records

This directory records why Kasumi is built this way, what actually shipped, and
what comes next. Use the [workflow](workflow.md) for substantial new features and
decision-shaping fixes. Ordinary tasks do not need numbered documentation.

## Start here

- [Product goal](001-library-and-reader/goal.md) — what Kasumi and KasumiMarkdown are for.
- [Roadmap](roadmap.md) — what comes next.
- [Development](../docs/development.md) — setup, build quirks, simulator and device notes.
- [Renderer gaps](002-rendering-engine/renderer-gaps.md) — known library limitations.

## Index

Entries 001–004 were backfilled on 2026-11-15: their plans are retrospective, and
their action records were assembled from Git history and the former status
document without rerunning tests or the app.

| ID | Anchor date | Topic / plan | Status | Outcome |
| --- | --- | --- | --- | --- |
| 001 | 2026-11-14 | [Reusable library and universal iOS reader](001-library-and-reader/000-plan.md) | Implemented (retrospective) | [Action](001-library-and-reader/001-action.md), [goal](001-library-and-reader/goal.md) |
| 002 | 2026-11-14 | [Native rendering engine](002-rendering-engine/000-plan.md) | Implemented (retrospective) | [Action](002-rendering-engine/001-action.md), [renderer gaps](002-rendering-engine/renderer-gaps.md) |
| 003 | 2026-11-14 | [Public rendering API](003-public-rendering-api/000-plan.md) | Implemented (retrospective); views planned | [Action](003-public-rendering-api/001-action.md) |
| 004 | 2026-11-14 | [iOS reader: document shell and reading view](004-ios-reader/000-plan.md) | In progress (milestone 1) | [Action so far](004-ios-reader/001-action.md), [saved imports](004-ios-reader/002-saved-imports.md), [iPad inspector](004-ios-reader/003-ipad-inspector.md) |
| 005 | 2026-11-14 | [CJK font availability on iOS](005-cjk-font-availability/000-plan.md) | Planned | — |
| 006 | 2026-11-15 | [Curated decision records](006-documentation-workflow/000-plan.md) | Implemented | [Action](006-documentation-workflow/001-action.md) |
