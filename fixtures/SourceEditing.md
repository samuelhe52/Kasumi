# Source editor

Edit this document and switch to Preview. The preview should update without
closing the file. Undo and redo should work after switching panes.

## Unicode and syntax

中文、日本語、한국어 and emoji 😀 stay intact. “Quotes” and -- dashes are literal
source; typing Markdown must not substitute smart punctuation.

- **Bold**, *italic*, and `inline code`
- [Jump to the ending](#ending)

```swift
let greeting = "Hello, Kasumi"
```

## A table

| Source | Preview |
| :--- | ---: |
| Markdown | Rendered |
| 中文 | 😀 |

## More content

Scroll the source, put the caret in this paragraph, switch panes, and return.
The editor should retain its caret and scroll position. The reading pane keeps
its own position; scrolling is intentionally independent.

## Ending

After editing, close the document and reopen it. The file should contain the
latest source even if it was closed before the preview finished updating.
