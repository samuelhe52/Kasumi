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
| 002 | 2026-11-14 | [Native rendering engine](002-rendering-engine/000-plan.md) | Implemented (retrospective) | [Action](002-rendering-engine/001-action.md), [shaping integrity](002-rendering-engine/002-shaped-cluster-integrity.md), [link decoration](002-rendering-engine/003-link-decoration.md), [glyph clearance](002-rendering-engine/004-underline-clearance.md), [adaptive tables](002-rendering-engine/005-table-layout.md), [syntax highlighting](002-rendering-engine/006-syntax-highlighting.md), [code panels and Copy](002-rendering-engine/007-code-block-presentation.md), [configurable code styles](002-rendering-engine/008-code-block-style-boundary.md), [PDF code continuations](002-rendering-engine/010-pdf-code-continuations.md), [language and punctuation](002-rendering-engine/012-language-and-punctuation.md), [standard TOML](002-rendering-engine/011-standard-toml-profiles.md), [hyphenation and defaults](002-rendering-engine/009-hyphenation-and-defaults.md), [renderer gaps](002-rendering-engine/renderer-gaps.md) |
| 003 | 2026-11-14 | [Public rendering API](003-public-rendering-api/000-plan.md) | Implemented (retrospective); views planned | [Action](003-public-rendering-api/001-action.md), [custom theme files](003-public-rendering-api/002-theme-files.md) |
| 004 | 2026-11-14 | [iOS reader: document shell and reading view](004-ios-reader/000-plan.md) | Implemented (milestone 1; closed 2026-11-16) | [Action](004-ios-reader/001-action.md), [saved imports](004-ios-reader/002-saved-imports.md), [iPad inspector](004-ios-reader/003-ipad-inspector.md), [import action](004-ios-reader/004-import-action.md), [warm file handoff](004-ios-reader/005-warm-file-handoff.md) |
| 005 | 2026-11-14 | [CJK font availability on iOS](005-cjk-font-availability/000-plan.md) | Implemented | [Action](005-cjk-font-availability/001-action.md), [transitions](005-cjk-font-availability/002-font-management-transitions.md), [font management](005-cjk-font-availability/003-role-first-layout.md), [offer alert](005-cjk-font-availability/004-font-offer-alert.md) |
| 006 | 2026-11-15 | [Curated decision records](006-documentation-workflow/000-plan.md) | Implemented | [Action](006-documentation-workflow/001-action.md) |
| 007 | 2026-11-16 | [Reader selection, find, and links](007-reader-interactions/000-plan.md) | Implemented (milestone 2) | [Action](007-reader-interactions/001-action.md), [system find](007-reader-interactions/002-system-find-navigator.md) |
| 008 | 2026-11-16 | [Reader export](008-reader-export/000-plan.md) | Implemented (milestone 3) | [Action and validation limits](008-reader-export/001-action.md), [export options](008-reader-export/002-export-options.md) |
| 009 | 2026-11-17 | [Source editor and live preview](009-source-editor/000-plan.md) | Implemented (milestone 4) | [Action and validation limits](009-source-editor/001-action.md), [editor experience](009-source-editor/002-editor-experience.md), [native editor chrome](009-source-editor/003-native-editor-chrome.md), [keyboard bar](009-source-editor/004-markdown-keyboard-bar.md); iPad split deferred |
