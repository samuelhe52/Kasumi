# Reader interactions

Select this sentence and copy it. Selection stays read-only.

Repeated needle one. Café, 中文, é, and 👩‍👩‍👧‍👦 test Unicode selection.

Copy **bold text**, `inline code`, and the formula $x_i+1$ as semantic text.

[Open example.com](https://example.com) should ask before leaving Kasumi.
[Email link](mailto:reader@example.com) should also ask.
[Unsupported link](kasumi-reader-test://unavailable) should ask, then report failure.
[Jump to destination](#destination) and this footnote[^reader] stay in the document.
[Missing heading](#not-a-heading) does nothing; it must not open another app.

## Find checks

Find the repeated search term above: the three results should highlight and wrap in both directions.
Find “CAFE”: the accented word above should match. Find “absent-query”: no matches.
Clear the query and close find; no search highlights should remain.

Changing appearance or rotating while find is open must recompute the results.
Changing appearance after selection must clear the old selection and its handles.

```swift
let copied = "Code remains selectable"
```

| Column | Value |
| --- | --- |
| Selection | Table text is semantic text |
| Search | Repeated needle two |

## Reading distance

The next paragraphs separate the search results and link destination so navigation
requires scrolling. Search must keep the active match visible above the keyboard.

A selected word can be extended across wrapped lines with the native handles.
Dragging a handle toward the viewport edge should allow extending the selection
while the document scrolls. Copy must follow the semantic text, without Markdown
emphasis delimiters, inline-code padding, or formula attachment characters.

The reader has its own layout. UIKit supplies the selection gestures and handles,
but must use the same geometry as the painted text. Select a word after scrolling
and repeat after a size change. Handles must stay next to the selected characters.

## Destination

Repeated needle three. [Return to the start](#reader-interactions).

The heading link and footnote should animate unless Reduce Motion is enabled.
The external link should show its destination before it opens, and Cancel must
leave the reading position unchanged.

[^reader]: Reader footnote destination. [Return to the start](#reader-interactions).
