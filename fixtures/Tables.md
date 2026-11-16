# Table layout

Surrounding prose stays inside the reading width while wide tables scroll independently.

| Part | Origin | Evidence |
| --- | --- | --- |
| Classic palette, Mono theme, Chinese duplicate-marker string, preset values, profile schema | **Extracted data** | Audit A1, A2, A5–A7 |
| One and Solarized slot mappings | Extracted from a configuration; base palettes public | Audit A3 |
| Paragraph layout and table widths | Measured typography and adaptive columns | Audit B4 |

## Wider comparison

| Run (full claim panel) | ScienceWorld reward | ALFWorld seen drop | ALFWorld unseen drop | Evidence |
| :--- | :--- | ---: | ---: | :---: |
| A→W→S | old, buggy | 34.3 pp | 20.1 pp | [First result](https://example.com/first) |
| A→S | fixed | 16.4 pp | 14.2 pp | [Final result](https://example.com/final) |

Prose after the comparison stays in the same column.

## Compact and CJK

| ID | Value |
| --- | ---: |
| A | 1 |
| B | 20 |

| 项目 | 说明 | 验证 |
| --- | --- | --- |
| 中文表格 | 连续的中文内容可以自然换行，不应按照一整句的宽度分配空间。 | 可读的列宽 |
| Inline styles | **Bold**, `code()`, and $x_i^2$ share cell geometry. | Final column |
