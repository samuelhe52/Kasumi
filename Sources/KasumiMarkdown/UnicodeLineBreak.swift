import CLineBreak
import Foundation

/// UAX14 opportunities in original UTF8 byte offsets. The pinned native helper
/// owns no caller memory.
enum UnicodeLineBreak {
    static func boundaries(in text: String) -> [(offset: Int, mandatory: Bool)] {
        let bytes = Array(text.utf8)
        return bytes.withUnsafeBufferPointer { input in
            let required = kasumi_linebreaks(input.baseAddress, input.count, nil, 0)
            guard let count = Int(exactly: required), count > 0, count <= input.count + 1 else { return [] }
            var output = [KasumiLineBreak](repeating: KasumiLineBreak(offset: 0, mandatory: 0), count: count)
            let written = output.withUnsafeMutableBufferPointer {
                kasumi_linebreaks(input.baseAddress, input.count, $0.baseAddress, $0.count)
            }
            guard Int(exactly: written) == count else { return [] }
            return output.map { (Int($0.offset), $0.mandatory != 0) }
        }
    }
}
