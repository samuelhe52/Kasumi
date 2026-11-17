import Foundation

enum LabSample: String, CaseIterable, Sendable {
    case chinese = "Chinese"
    case english = "English"
    case mixed = "Mixed"
    case single = "Single paragraph"

    func markdown(characters: Int) -> String {
        let sentence = self == .english
            ? "The reader should reflow text smoothly while the window changes size. Words and punctuation remain clear, and the reading position stays stable. "
            : "窗口大小改变时，阅读器应当流畅地重新排列文字。中文标点、字体和段落之间的距离都应保持准确；拖动窗口边缘，不应出现明显延迟。阅读位置需要保持稳定。"
        if self == .single {
            return String(String(repeating: sentence, count: characters / sentence.count + 1).prefix(characters))
        }
        let paragraph = String(String(repeating: sentence, count: 500 / sentence.count + 1).prefix(500))
        var blocks = ["# \(rawValue) · \(characters.formatted(.number.locale(Locale(identifier: "en_US")))) characters"]
        for index in 0..<max(1, characters / 500) {
            blocks.append("Paragraph \(index). " + paragraph)
            if self == .mixed, index.isMultiple(of: 10) {
                blocks.append("""
                > Quoted text with **bold**, *emphasis*, `inline code`, and a [link](https://example.invalid).

                | Feature | Value | Details |
                | --- | --- | --- |
                | Formula | $x_i + 1$ | Inline attachment |
                | Text | 中文 English 🙂 | Mixed scripts |

                $$
                \\frac{1}{3} + x^2
                $$

                ```swift
                let message = "Reflow and scroll"
                print(message)
                ```
                """)
            }
        }
        return blocks.joined(separator: "\n\n")
    }
}
