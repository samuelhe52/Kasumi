# 002.012 — Bounded document language and display punctuation

## Plan and decisions (2026-11-17, before implementation)

Implement automatic hyphenation-language selection, punctuation folding and
punctuation spacing in the shared library, with CLI access and no new reader UI.
The maintainer requested low performance cost and no simulator use. Continue
delivering coherent local commits, as authorized for the renderer-gap work.

### Language selection

An explicit profile/CLI dictionary wins. For `auto`, use a supported single-line
`lang:` scalar in initial Markdown front matter, then a bounded stopword vote over
parsed prose, then US English. Normalize regional tags to the existing dictionary
set; retain explicit British English but do not guess English regional variants.
Store the automatic selection in the parsed document so reflow and exports reuse
it. Exclude code, math, images and link labels from the prose sample. Bound the
sample, token length and repeated-word influence; ambiguous/weak votes fall back.
Front matter is hidden from rendering without shifting subsequent source lines.
No Apple language recognizer, model loading, network access or new dependency.

### Punctuation policy

`faithful` retains the current default and takes a fast path. For opt-in `fold`
and `spacing`, use a linear character-context pass, not paragraph language
recognition. Eligible blocks contain Han and no kana or Hangul. A nearby Han
character must support each mark; Latin-only islands remain unchanged. This
conservative script rule cannot distinguish Han-only Japanese from Chinese.

Protect inline code, math, images, links and footnote markers; never alter code
or diagram blocks. Protect decimal/thousands/time separators between digits.
Fold `, . ; : ! ? ( )` to `， 。 ； ： ！ ？ （ ）` before shaping, retaining
original punctuation for semantic text, copy, search and accessibility.

For `spacing`, retain the original glyph and add 1/8 base-font em before/after
eligible punctuation where the adjacent character is not already whitespace.
Treat consecutive marks as a group rather than doubling internal gaps. Track
padding in shaping so normalized Han advances retain it. Preserve source length,
style and interactions; no synthetic spaces in semantic text.

These are explicit Kasumi policies informed by prior discussion, not a claim of
exact matching to another application's unknown context/spacing rules.

## Validation plan

Focused tests for language precedence, supported languages, ambiguous input,
sample bounds, excluded content and cached reflow; punctuation contexts,
protected runs, styled boundaries, measured geometry, copy/search/caret mappings
and raster/PDF paint. Preserve frozen measurements unless a deliberate automatic
language change affects a covered case, and document any expectation updates.
Measure detection and opt-in punctuation overhead with optimized headless code,
including many paragraphs and large/adversarial inputs. Report measured cost and
limits, not just asymptotic claims. Use Makefile routines, unsigned generic iOS
compilation and headless artifact inspection; do not use a simulator.

## Language slice outcome

Implemented immutable parse-time language analysis and the public
`MarkdownDocument.automaticHyphenationLanguage` query. All document layout paths,
including table cells and exports, resolve `auto` from that cached result while
retaining explicit profile/CLI precedence and printed font sizes.

The authored vote uses fourteen language families (English defaults to US;
British patterns remain explicit). It examines at most 32,768 scalars or 4,096
word tokens, ignores tokens over 48 scalars and caps each matched word at four
votes. A selection requires three distinct matched words, score 24, an eight-point
lead and a 1.25x lead over the runner-up. These conservative guards are authored
policy, not thresholds calibrated against a language-detection accuracy corpus.

`make test FILTER=DocumentLanguageTests` passed four tests on macOS. They cover
front-matter precedence/UTF-8/source lines, fourteen authored prose samples,
weak/mixed input, protected content, budget enforcement, explicit overrides and
cached reflow. Early fixtures used invalid whitespace-delimited math and a
punctuation-only emphasis span that CommonMark did not recognize; those fixtures
were corrected. A single-width dictionary comparison was expanded across widths
because different dictionaries can legitimately choose the same line boundary.
No frozen reference files changed. Punctuation and assembled-work validation are
recorded in the following slice.
