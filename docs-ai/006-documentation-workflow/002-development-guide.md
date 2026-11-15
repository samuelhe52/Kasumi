# 006.002 — Development guide back in docs/

## Context

The migration moved `docs/development.md` into `docs-ai/`. Most of it is
contributor setup rather than decision history, and the public README links to
it under `docs/`.

## Change

Maintainer decision: move it back to `docs/development.md` and strip content an
agent can find in `make help`, the Makefile, or the source tree. Kept: toolchain
requirements, build quirks (`make native`, `scripts/build-native`, no simulator
boot, the `Bundled` folder name, the fixtures symlink), the simulator clipboard
bug, and the debug `-KasumiOpen` launch argument. Links in `AGENTS.md`, the
`Makefile`, the skill, the index, the workflow, and entry 004 now point there.

## Refs

`docs/development.md`, `AGENTS.md`, `docs-ai/workflow.md`.
