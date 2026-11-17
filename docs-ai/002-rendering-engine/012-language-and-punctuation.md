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

## Punctuation slice and assembled outcome

Implemented `faithful`/`fold`/`spacing` in shared typography, with
`--punct-strategy` as a validated CLI override independent of profile argument
order. Folding happens before font selection and shaping; an original-punctuation
attribute preserves the one-to-one semantic mapping without changing source.
Spacing uses kern advances rather than inserted characters; Han advance
normalization explicitly retains the added padding. Consecutive eligible marks
form one spacing group; matched parentheses transform together, while unmatched
or protected pairs remain literal.

The default `faithful` path avoids context scanning. Opt-in analysis computes
nearest context in linear passes, bounds proximity to sixteen scalars and excludes
protected runs. Paragraphs with kana/Hangul are vetoed, but Han-only Japanese is
ambiguous. No statistical language recognizer is invoked for punctuation. PDF
paint/text extraction follows displayed glyphs; the library/reader semantic APIs
retain original punctuation, like the existing separation for math attachments.

### Validation

On Apple M1 Pro, 16 GiB RAM, macOS 27.2.1:

- Initial focused tests passed all eight language/punctuation tests after correcting
  the authored Markdown fixtures and a PDF extraction assertion affected by an
  existing CJK font's compatibility-radical encoding.
- `make test` passed 210 tests in 17 suites; the opt-in performance test was skipped.
  This covered frozen paragraph/line-break/pagination observations, attachments,
  tables, underlines, selection, exports, themes and existing public APIs. No frozen
  reference files changed.
- `make test FILTER=PunctuationPolicyTests` passed five final tests, including
  matched emoji parentheses and CLI profile-override ordering/error nonmutation.
  The public checks cover original text, copy/search, carets, links, tables, code
  payloads and both image-layout widths plus PDF output.
- `make app-check` passed for an unsigned generic iOS device, with only the existing
  no-AppIntents-dependency metadata warnings. No simulator was used or booted.
- `make render` generated faithful/spacing/fold 700 px PNGs and a captioned fold PDF
  from `fixtures/LanguageAndPunctuation.md`. All three PNGs and the first PDF page
  rendered by Poppler were inspected. Metadata is hidden, French hyphenation is
  active, punctuation policies are visible, protected content remains literal,
  and tables/footnotes remain legible. QA outputs are local and not retained.

### Optimized cost measurements

`make benchmark-typography` passed its opt-in release benchmark. These are warm
synthetic timings, excluding parsing for the language-analysis measurements and
excluding parsing/drawing for the complete-layout measurements. Five to fifteen
repetitions follow one warm-up. They are neither an accuracy study nor iPhone
performance measurements.

| Operation | Median | p95 |
| --- | ---: | ---: |
| Language, 2,048 characters | 0.049 ms | 0.063 ms |
| Language, 32,768 characters (word budget stops earlier) | 0.468 ms | 0.474 ms |
| Language, 1,000,000 characters (same bounded sample) | 0.466 ms | 0.504 ms |
| Language, 1,000 paragraphs of 512 characters (one document sample) | 0.412 ms | 0.441 ms |
| Punctuation plans, 1,000 mixed paragraphs, faithful | 0.034 ms | 0.034 ms |
| Punctuation plans, 1,000 mixed paragraphs, fold | 10.879 ms | 12.285 ms |
| Punctuation plans, 1,000 mixed paragraphs, spacing | 10.818 ms | 10.900 ms |
| Complete layout, 50 mixed paragraphs, faithful | 161.833 ms | 187.828 ms |
| Complete layout, 50 mixed paragraphs, fold | 192.908 ms | 203.095 ms |
| Complete layout, 50 mixed paragraphs, spacing | 197.204 ms | 299.302 ms |

Automatic analysis is cached across reflows and exports; source reparsing creates
new analysis. Whole-document layout is still not incremental. The new script
heuristic and authored stopwords need broader accuracy evaluation before claiming
reliable detection for short, specialist or mixed-language documents.
