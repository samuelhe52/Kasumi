# 002.026 — PDF link annotations

## Context

PDF export paginates the vector layout shared with the reader. Markdown
destinations already survive in the attributed paragraphs, but PDF pages have
no clickable annotations.

## Design

Collect link rectangles from the shaped lines during the page's clipped draw
pass. Declare named destinations for resolved heading and footnote anchors.
Use the document base URL for relative external links and the active page
transform for annotations on wrapped or scaled content. Verify the exported
PDF with PDFKit and exercise the reader's existing export entry point.

## Outcome

The streaming and in-memory exporters use the same annotation pass. Each
wrapped line gets its own clickable geometry, including visual runs in bidi
text. Heading and footnote links use named PDF destinations. Other URLs
resolve against the input document base when available. Unresolved fragments
have no annotation. The page clip and transform cover continuation-header
space, margins, and scaling of oversized content.

The PDFKit test checks cross-page wrapping, relative URLs, bidi text, heading
and footnote destinations, and clipping with a page header. Diagram node
annotations reuse this pass. See [002.027](027-diagram-interactions.md).

On the iPhone 18 Pro simulator running iOS 27.2, Preview exposed Markdown
and diagram annotations as links in a PDF created by the reader's Export
and Share action.
