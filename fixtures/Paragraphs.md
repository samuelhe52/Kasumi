# Paragraph geometry

中文段落包含 Latin words、全角标点（括号与引号）和 **加粗文字**。读者可以拖选这段文字，复制它，搜索其中的 words，或打开[本地标题链接](#code-and-word-breaks)。所有操作都应跟随文字的实际位置。

「段首的开引号」与句末的标点，需要分别处理字形位置和选择区域。甲乙丙丁，戊己庚辛。还有连续标点？！以及相邻的结束符号。）。窄栏和宽栏会选择不同的换行位置。

This paragraph mixes English words with 汉字 and inline mathematics $\frac{a+b}{c}+\sqrt{x}$. The mathematical object keeps its source for copying and searching. A footnote marker[^layout] uses its own script context without changing the surrounding paragraph's em.

## Code and word breaks

Short inline `code()` has a capsule. Adjacent `first()`**`second()`** spans keep their separate style identities, while `two words` retains its internal space. Leading ` code` and trailing `code ` spaces exercise the capsule edges.

Native dictionary hyphenation handles supercalifragilisticexpialidocious, internationalization and antidisestablishmentarianism. Compound identifiers such as Paragraph_10 and office_10 should remain searchable in PDF output.

A nonbreaking pair joins Alpha Beta, and an emoji family 👩‍👩‍👧‍👦 or accented é stays a whole grapheme during emergency wrapping.

> 这段引用缩小了局部排版宽度。The narrow-measure decision still uses the outer document measure, while line choices use the local quote width.

1. A list item includes `code` and 中文，标点。
2. Another item contains enough text to wrap in a narrow viewport without shifting its marker column.

[^layout]: Authored note for selection, paragraph spacing and PDF pagination checks.
