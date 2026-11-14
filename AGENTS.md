# AGENTS.md

## Workflow

- Use Makefile commands for dev routines.
- Validate UI and runtime behavior by running the app in the simulator, not only by building or running `swift test`. Drive the simulator with `sim-use`. Report what you did not verify.
- If the user asks to perform a change in a new worktree, create that worktree under `.worktrees/` in the repository root.

## Reference materials

- `fixtures/reference/` holds frozen reference measurements that tests compare against. Treat them as regression data: when a deliberate change alters a covered behavior, update the expectation in the same commit and say so.
- No reference application, binary or analysis tooling is part of this project. Builds and tests must not depend on anything outside the repository and its pinned dependencies.

## Testing

- Add the smallest set of tests that protects distinct behavior, and prefer extending existing tests. Run the narrowest relevant command (`swift test --filter <name>`) unless there is a reason to run the full suite. Simple wiring, copy, or layout changes may need no new tests.

## Commits

- Organize work into coherent commits. Fold small review corrections into the unpushed commit they fix. Do not amend, rebase, or rewrite commits you did not create in the current task without asking.
- Other agents may be editing the same working tree. Stage only changes within the commit's scope, by path (`git add <paths>`); never use `git add -A`, `git add .`, or `git commit -a`.
- Use conventional commits: `<type>: <subject>`, with imperative, capitalized, concise subjects and no trailing period.
