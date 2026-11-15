# 004.003 — iPad outline as an inspector

## Context

On iPad the reader wrapped itself in a `NavigationSplitView` with the outline as
a leading sidebar. Inside the `DocumentGroup` presentation that brought a second
navigation bar ([004.002](002-saved-imports.md) open question), and a leading
sidebar is the wrong side for a panel that supports the content. The maintainer
asked for the iPad convention: a trailing inspector.

## Change

- iPad: the outline is a trailing `.inspector` (width 260–420, ideal 320) next
  to the text. It stays open while jumping between headings. The toolbar shows
  Delete (imports only) and a fixed gap, then Appearance and the inspector
  toggle (`sidebar.trailing`, ⌥⌘0) at the trailing edge. Delete isn't pinned:
  the iPad bar has room for every item.
- iPad outline has no heading search.
- iPhone is unchanged: outline sheet with search, Delete pinned trailing.

## Decisions

| Choice | Reason and alternative |
| --- | --- |
| Attach `.toolbar` outside `.inspector` | Declared on the reader inside the inspector, the items reached neither the iPad nor the iPhone `DocumentGroup` bar. |
| Build inspector content only in regular width | Even with the inspector closed, the outline's `.searchable` put a search field in the iPhone reader's bottom bar. The iPhone keeps its own sheet rather than the inspector's compact sheet, which has no Done button or paper background. |
| No search in the iPad outline | Maintainer decision. `.searchable` draws nothing in the inspector with default, `.toolbar`, or `.navigationBarDrawer` placement, yet reserves an empty row above the list. A `NavigationStack` inside the inspector shows search but inherits the document's Back button and title menu, and the reader's bar loses its items. A custom field at the top of the list needed safe-area measuring to avoid that reserved row; rejected as fragile. |

## Validation

iPad Pro 13-inch (M5) simulator, iOS 27.2, `make run-sim` with
`-KasumiOpen fixtures/Rendering.md`, driven with `sim-use` in landscape:
the bar shows Back, title, Appearance, and the toggle; the toggle opens the
inspector with the heading list directly under the floating toolbar items and
the main bar keeps Back and title. The maintainer confirmed on iPhone that
Outline and Appearance are in the bar and no search bar appears in the reader.

Not verified: Delete on iPad, ⌥⌘0, portrait and Split View widths, heading
jumps from the inspector, physical iPad.

## Open questions

- About one in three `-KasumiOpen` launches on the iPad simulator showed a blank
  page that never recovered; the app was idle and the reader's view was detached
  from the window. Relaunching fixed it. Seen before this change; not
  investigated. Paste Markdown and Open URL use the same open path.

## Refs

- `apps/iOS/Kasumi/ContentView.swift`
