# Link jumps

Use this document to check animated navigation. Follow each link, then use its return link to come back here. Repeat with Reduce Motion enabled: jumps should be immediate instead of animated.

- [Jump to the middle](#middle)
- [Jump near the end](#near-the-end)
- [Jump to the second repeated heading](#repeated-heading-1)
- [Jump to a percent-encoded heading](#caf%C3%A9)
- Follow this footnote.[^navigation]
- Follow the same footnote again.[^navigation]

The outline should use the same animated scrolling as these links. While a jump is moving, try dragging the page to interrupt it, then follow another link.

## Before the middle

The first stretch gives a downward jump enough distance to be visible. Watch the text travel through the viewport rather than disappear and reappear at the destination. The navigation bar and bottom toolbar should remain in place.

A settled screenshot proves only the destination. Record the screen to see intermediate positions during the jump. A normal heading link and a footnote reference should both move smoothly through the document.

A return link exercises upward movement. After reaching a destination, return to the top and follow a different link. Repeated taps should not leave the reader stuck between destinations.

Scrolling can end at the document boundary. A target near the bottom may remain below the top of the viewport because there is no more content to scroll into view. That is expected; the target must still be visible.

## Middle

You reached the middle. [Return to the start](#link-jumps), [continue near the end](#near-the-end), or follow the footnote from here.[^navigation]

The middle target has content before and after it, so it can sit near the top of the reading viewport. Check that the heading is not hidden beneath the navigation bar after the animation settles.

This paragraph separates the middle target from the next heading. Try opening the outline here: its current heading should reflect the position reached by the link jump.

Longer documents make the direction of travel easier to see. The native scrolling animation should finish without a second snap after the first movement. Changing the font size afterward should preserve the current reading position.

## Repeated heading

This is the first occurrence. The link at the start points to the second occurrence, not this one. [Return to the start](#link-jumps).

Heading fragments are based on text. Duplicate headings get a numeric suffix; the second occurrence in this document is `#repeated-heading-1`. The two destinations are separated so an incorrect landing is visible.

Continue reading past this paragraph to reach the next section. Following the duplicate-heading link should move beyond this first occurrence and land on the second one.

## Between repeated headings

This section provides distance between the duplicate targets. Its text should pass through the viewport during a jump to the second occurrence.

When testing interruption, start a long jump from the top and drag before it settles. Then follow a visible return link. The reader should remain responsive to direct scrolling and later link taps.

After navigating, close and reopen the document to check that the reading position follows the settled destination rather than the starting location. This is a manual persistence check, separate from the animation itself.

## Repeated heading

This is the second occurrence, the destination of `#repeated-heading-1`. [Return to the start](#link-jumps).

## Café

The percent-encoded link should land here. Its destination is `#caf%C3%A9`; the visible heading contains an accented character. [Return to the start](#link-jumps).

## Before the end

The final stretch puts the last heading and footnote farther from the beginning. Follow their links from the start to check longer downward movement, then return upward.

The same footnote is referenced more than once. Each reference should reach the same definition. The definition includes an ordinary Markdown return link so upward navigation can be checked without relying on a separate back-link feature.

Neither a footnote nor a heading jump should open another document or an external browser. These destinations are all fragments within this file.

## Near the end

You reached the final heading. [Return to the start](#link-jumps), [return to the middle](#middle), or follow the footnote.[^navigation]

This destination is close to the bottom. Its final position is limited by the scrollable content height, so it may not align with the top of the viewport.

[^navigation]: Footnote destination. All three reference locations should arrive here with animated scrolling, unless Reduce Motion is enabled. [Return to the start](#link-jumps) or [return to the middle](#middle).
