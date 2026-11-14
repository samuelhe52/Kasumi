# Selected native hyphenation source and notices

Files are copied unmodified; this README/MANIFEST describe our packaging.
Code dependency: tapeinosyne/hyphenation 0.8.4, MIT OR Apache-2.0. That does not
relicense pattern data; masters/ retains each selected copyright/license.
Complete applicable GPL version 2 and LPPL 1.3c texts are in licenses/. MIT, BSD3 and
permissive pattern terms are printed in full in the masters.

Data terms in the pinned masters:
en-US: Kuiken permissive; extra exceptions separately TUG permissive.
en-GB, de-1996, fr, es, it, da, pl: MIT (choose offered MIT alternative where dual).
pt: BSD 3-Clause. nl: LPPL version 1 or later; sv/ru: LPPL version 1.2 or later (select LPPL 1.3c).
fi: freely-distributable notice. nb/no: permissive notice.
cs: GPL version 2 or later. Preserve GPL source/distribution obligations; these resources
are NOT all MIT. No conclusion about downstream app licensing is made here.

Russian original work: ruhyphen-original/ preserves unmodified KOI8-R
ruhyphal.tex, cyryoal.tex, README.ruhyphal, and hyphen.rules, the four files
named by the converted Russian master's notice, together with README/mkcyryo.
The converted UTF-8 master is also preserved. All 4,787 original default patterns
occur in its 7,037 entries; it also contains additions, so this is not a claim
that the converted master is the exact union of those originals.
Official source archive (ruhyphen 1.6, default source version 2003/03/10):
https://mirrors.ctan.org/language/hyphenation/ruhyphen.zip
SHA-256: 60655d6dce99d11a9fbcf2e59510043276125019463146100387f767557b137e
Per-file hashes and source encoding: ruhyphen-original/PROVENANCE.json.

All selected .pat sources exactly match pinned tex-hyphen commit
4639fca6bd755fa7e981ebee4d887c65de4ce773 (2021-03-22 snapshot):
https://github.com/hyphenation/tex-hyphen/tree/4639fca6bd755fa7e981ebee4d887c65de4ce773
under hyph-utf8/tex/generic/hyph-utf8/patterns/{txt,tex}/.
This establishes matching contents, rather than proving the historical checkout
used to build the original application.
The Bokmal wrapper inputs hyph-no.tex; its complete master is included.
Selected ordinary .hyp sources match that same snapshot except en-US.

EnglishUS .hyp source is the 1,439-line TUG hyphenex list, not merely the 14
exceptions in hyph-en-us.tex. Every line matches archived TL2016 ushyphex.tex
exactly after dropping the TeX wrapper/indentation; no custom words were added.
Original complete ushyphex.tex source and permissive notice are retained in
hyphenex-2016/. The newer 2021 README, article and generation tools are retained
SEPARATELY for project/notice context; do not regenerate native data from that
newer article, which contains different words.
https://ftp.math.utah.edu/pub/tex/historic/systems/texlive/2016/tlnet-final/archive/hyphenex.tar.xz
SHA-256: 638f079615aa3deaad1ffe3f25b0b94823b2dbc684845aaf8b8b2acb2fe51b6f
https://mirrors.ctan.org/info/digests/tugboat/hyphenex.zip
SHA-256: cd5bd227a973b5d4ae316336f3830d445e22b2b23aa8562d0f1cf97f33dcdbe8

Complete Rust dependency/source archives:
https://static.crates.io/crates/hyphenation/hyphenation-0.8.4.crate
SHA-256: bcf4dd4c44ae85155502a52c48739c8a48185d1449fff1963cffee63c28a50f0
https://static.crates.io/crates/hyphenation_commons/hyphenation_commons-0.8.4.crate
SHA-256: 5febe7a2ade5c7d98eb8b75f946c046b335324b06a14ea0998271504134c05bf

upstream-build/ preserves unmodified upstream build.rs and both original Cargo
manifests. Complete source archives are linked and hash-pinned above.

Rebuild: obtain those pinned archives and preserve sources/ under the upstream
crate's patterns/ directory. The upstream build.rs reads patterns/hyph-<tag>.pat.txt and optional .hyp.txt,
uses hyphenation_commons::parse::Parse and Builder, then serializes Standard with
bincode 1.3.3 and fst 0.4.x. Build complete pinned source with feature
build_dictionaries to regenerate OUT_DIR/dictionaries. Preserve the selected
source patterns/masters supplied here, pinned Rust source/build.rs and Cargo.lock.
HashMap serialization ordering may vary, but semantic dictionary contents remain
equivalent; rebuilding is not a claim of byte-identical serialization.
The distributed dictionaries retain the exact published registry bytes: all 15
compiled dictionaries are byte-identical to the pinned official 0.8.4 release.
