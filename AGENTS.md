# AGENTS.md

## Workflow

- Use Makefile commands for dev routines.
- Ask before booting a simulator. Drive the simulator with `sim-use`.
- If the user asks to perform a change in a new worktree, create that worktree under `.worktrees/` in the repository root.

## Documentation

- [`docs/development.md`](docs/development.md) covers setup, build quirks, and simulator and device notes.
- [`docs-ai/README.md`](docs-ai/README.md) indexes the product goal, roadmap, and decision records.
- Use the `write-ai-doc` skill for substantial features and decision-shaping fixes, as defined in [`docs-ai/workflow.md`](docs-ai/workflow.md). Keep the roadmap, renderer gaps, and `docs/development.md` current in the same commit as the change. There is no status document; don't add one.
- Use the `kasumi-release` skill for release preparation and publication.

## UI

- Always use the `.soft` style for toolbar edge effects. In UIKit, set `UIScrollView.topEdgeEffect.style = .soft`. In SwiftUI, use `.scrollEdgeEffectStyle(.soft, for: .top)`. Apply this everywhere a toolbar appears.
- Sheets are dismissed by an X button (`Button(..., systemImage: "xmark")`) in the leading toolbar slot (`ToolbarItem(placement: .cancellationAction)`). Do not add a Done button.

## Reference materials

- `fixtures/reference/` holds frozen reference measurements that tests compare against. Treat them as regression data: when a deliberate change alters a covered behavior, update the expectation in the same commit and say so.
- No reference application, binary or analysis tooling is part of this project. Builds and tests must not depend on anything outside the repository and its pinned dependencies.

## Testing

- Add the smallest set of tests that protects distinct behavior, and prefer extending existing tests. Run the narrowest relevant command (`swift test --filter <name>`) unless there is a reason to run the full suite. Simple wiring, copy, or layout changes may need no new tests.

## Commits

- Do not commit unless asked. Organize work into coherent commits. Do not amend, rebase, or rewrite commits you did not create in the current task without asking.
- Other agents may be editing the same working tree. Stage only changes within the commit's scope, by path (`git add <paths>`); never use `git add -A`, `git add .`, or `git commit -a`.
- Use conventional commits: `<type>: <subject>`, with imperative, capitalized, concise subjects and no trailing period.
