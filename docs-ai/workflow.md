# Kasumi decision-record workflow

Use `docs-ai/` to preserve decisions that future implementation depends on.
The project-owned `write-ai-doc` skill defines the plan/action/amendment workflow
and templates; this document adds Kasumi-specific selection, evidence, and
ownership rules.

## Select work deliberately

Create a numbered entry for a substantial feature or a fix with enduring product,
architecture, public-API, rendering, file-format, or native-dependency
implications. Record the reason and rejected alternatives when code alone would
not explain the choice. Skip routine debugging, reviews, test reports, minor UI
polish, dependency bumps, and docs-only edits unless the maintainer requests a
durable record.

Kasumi grew quickly; most work is a slice of a larger entry. Prefer amending the
entry that owns the area (`002-…` and later files) over opening a new topic.

## Plan, implement, and reconcile

1. Read the index and [roadmap](roadmap.md). Amend an existing topic when the
   decision still fits it.
2. For a new topic, choose the next free three-digit number and kebab-case slug.
   Create `000-plan.md` before coding: background, goals, approach, alternatives,
   reasons, validation criteria, and unresolved decisions.
3. Implement within the user's authorization. A plan or skill does not authorize
   publishing or any remote mutation.
4. Write `001-action.md` after implementation: dated outcomes, key source paths,
   actual validation, deviations, and remaining uncertainty. Set the plan status
   to Implemented only when the intended scope is complete. Use In progress for
   partial delivery and Planned for proposals.
5. Add `002-<topic>.md` and later amendments for related follow-ups. Link them from
   the plan and index. For a major redesign, create a new entry and cross-link the
   superseded one. Multi-slice plans record each slice as an amendment and finish
   the aggregate action record when the final slice completes.
6. Keep the living files current in the same commit as the change: the
   [roadmap](roadmap.md) for what comes next and [renderer gaps](002-rendering-engine/renderer-gaps.md)
   for known library limitations. Put a feature's verification recipe and its
   feature-specific simulator or device quirks in its own entry; cross-feature
   setup and tooling gotchas go in `AGENTS.md`.

There is no running status document. What shipped is in action records and
amendments; what comes next is in the roadmap; known limitations are in the gap
lists. Do not reintroduce a catch-all status file.

## Record intent and evidence

- Explain what constraint led to each choice and why a plausible alternative was
  rejected. Do not fabricate an alternatives discussion from code alone.
- Label recovered discussion memory and distinguish it from source documents,
  commit messages, tests, or runtime observations. Mark reasoning inferred from
  implementation as inference.
- A retrospective `000-plan.md` must say it was reconstructed and give both the
  historical anchor date and reconstruction date. Do not imply it preceded coding.
- Separate proposed behavior, implemented source, and actual runtime
  verification. Name the simulator or device and OS version for runtime checks,
  and list what was not verified, as `AGENTS.md` requires.
- Changes that alter frozen measurements in `fixtures/reference/` say so in the
  entry that caused them.
- Existing source paths must exist in the checkout. Proposed new paths may be
  named when explicitly marked proposed.
- Do not cite untracked or ignored paths such as `build/`, `.build/`, or `.local/`
  as evidence; they can be deleted at any time. Write the observed result into the
  record itself and describe screenshots and logs as local and not retained.
- Keep records truthful. When a follow-up invalidates plan or action text, correct
  it in place and note the correction in the dated amendment.

## Documentation ownership

`docs-ai/` holds the product goal, design history, contracts, and the roadmap.
`AGENTS.md` holds agent rules and the setup, layout, and simulator or device
gotchas that span features; keep it to what an agent can't quickly find in
`make help`, the Makefile, or source. The root README holds the public build
requirements. There is no separate development guide ([006.003](006-documentation-workflow/003-retire-development-guide.md)). Package READMEs and license notices stay with their packages under
`packages/`. Authored test documents stay in `fixtures/`; `apps/iOS/Kasumi/Welcome.md`
is app content, not documentation. The root README is public; it is not a home
for design history.

## Source and local adaptation

The skill at `.agents/skills/write-ai-doc/SKILL.md` (linked from
`.claude/skills/write-ai-doc`) was adapted from
[onevcat/Prowl](https://github.com/onevcat/Prowl/blob/main/.claude/skills/write-ai-doc/SKILL.md)
by way of the maintainer's AniShelf project, and is project-owned: it has no
`skills-lock.json` entry, so `npx skills update` does not manage it. Edit it in
place; do not reinstall it from upstream.
