# 002.027 — Diagram interactions

## Context

Rendered Mermaid blocks occupy one inline attachment in document layout.
Vector drawing already supplies positions for labels and graph nodes.

## Design

Give rendered labels semantic ranges and use their painted geometry for text
hit testing, selection and Find. A rendered diagram contributes visible labels
to document text in reading order. The editor continues to expose Mermaid
source. Parse native URL actions on flowchart and class nodes and share their
geometry between reader hit testing and PDF annotations. URL actions are data
for the existing link dispatcher. Use tests for scaled attachments and the
reader UI to verify link activation and label selection.

## Outcome

Flowchart nodes support quoted URL targets and explicit `href` syntax. Class
nodes support `click … href` and `link` directives. The reader uses the node
shape for hit testing. PDF viewers use the node's bounding rectangle.
Linked labels are underlined and the reader's confirmation policy applies.
The sequence actor menu syntax remains outside this implementation.

Rendered labels enter the semantic text from top to bottom and left to right
at the same vertical center. Each label has its own shaped caret and selection
geometry after attachment scaling. Find and Copy use this visible-label
representation. The source editor and literal code rendering retain the
Mermaid text. The existing semantic-text test now expects visible labels for
rendered flowcharts. Frozen reference geometry is unchanged.

Tests cover reader hit testing, selection, caret placement and PDF link
geometry at different scales, including an internal link and a blocked
script URL.

On the iPhone 18 Pro simulator running iOS 27.2, tapping a flowchart node
opened the reader's external-link confirmation. Long-pressing an edge label
selected a word with native handles and presented the Copy menu.
