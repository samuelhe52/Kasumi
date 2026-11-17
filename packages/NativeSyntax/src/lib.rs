use std::{
    panic::{AssertUnwindSafe, catch_unwind},
    slice, str,
    sync::OnceLock,
};
use syntect::{
    highlighting::ScopeSelectors,
    parsing::{ParseState, ScopeStack, SyntaxSet},
    util::LinesWithEndings,
};

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SyntaxSpan {
    pub location: usize,
    pub length: usize,
    pub role: u32,
}

const MAX_BYTES: usize = 256 * 1024;
const MAX_LINE_BYTES: usize = 16 * 1024;
static SYNTAXES: OnceLock<SyntaxSet> = OnceLock::new();

// Numeric roles are the C ABI: keyword, string, comment, literal, type.
fn selectors() -> &'static [(u32, ScopeSelectors)] {
    static SELECTORS: OnceLock<Vec<(u32, ScopeSelectors)>> = OnceLock::new();
    SELECTORS.get_or_init(|| {
        [
            (1, "keyword, storage"),
            (2, "string"),
            (3, "comment"),
            (4, "constant"),
            (
                5,
                "entity.name.type, entity.name.class, support.type, support.class, storage.type.primitive",
            ),
        ]
        .into_iter()
        .map(|(role, selector)| (role, selector.parse().unwrap()))
        .collect()
    })
}

fn role(stack: &ScopeStack) -> Option<u32> {
    selectors()
        .iter()
        .filter_map(|(role, selector)| {
            selector
                .does_match(stack.as_slice())
                .map(|score| (*role, score))
        })
        .max_by_key(|(_, score)| *score)
        .map(|(role, _)| role)
}

fn tokens(source: &str, language: &str) -> Option<Vec<SyntaxSpan>> {
    if source.len() > MAX_BYTES || source.split('\n').any(|line| line.len() > MAX_LINE_BYTES) {
        return None;
    }
    let language = language
        .split_whitespace()
        .next()
        .unwrap_or("")
        .to_ascii_lowercase();
    let language = match language.as_str() {
        "" | "text" | "txt" | "plaintext" | "plain" | "none" => return Some(Vec::new()),
        "js" | "javascript" => "js",
        "ts" | "typescript" => "ts",
        "py" | "python3" => "python",
        "sh" | "shell" | "shellscript" | "zsh" | "console" => "bash",
        "c++" => "cpp",
        "c#" => "cs",
        "objc" | "objective-c" => "m",
        "objective-c++" => "mm",
        "yml" => "yaml",
        other => other,
    };
    let syntaxes = SYNTAXES.get_or_init(two_face::syntax::extra_newlines);
    let syntax = syntaxes.find_syntax_by_token(language).or_else(|| {
        syntaxes
            .syntaxes()
            .iter()
            .find(|s| s.name.eq_ignore_ascii_case(language))
    });
    let Some(syntax) = syntax else {
        return Some(Vec::new());
    };
    let mut parser = ParseState::new(syntax);
    let mut stack = ScopeStack::new();
    let mut result: Vec<SyntaxSpan> = Vec::new();
    let mut location = 0;
    for line in LinesWithEndings::from(source) {
        let operations = parser.parse_line(line, syntaxes).ok()?;
        let mut start = 0;
        for (end, operation) in operations {
            append(&mut result, &line[start..end], &mut location, role(&stack));
            stack.apply(&operation).ok()?;
            start = end;
        }
        append(&mut result, &line[start..], &mut location, role(&stack));
    }
    Some(result)
}

fn append(spans: &mut Vec<SyntaxSpan>, text: &str, location: &mut usize, role: Option<u32>) {
    let length = text.encode_utf16().count();
    if length > 0 {
        if let Some(role) = role {
            if let Some(last) = spans
                .last_mut()
                .filter(|s| s.role == role && s.location + s.length == *location)
            {
                last.length += length;
            } else {
                spans.push(SyntaxSpan {
                    location: *location,
                    length,
                    role,
                });
            }
        }
        *location += length;
    }
}

/// # Safety
/// Nonempty inputs must be readable for the supplied lengths. Nonnull output
/// must be aligned, writable for capacity spans, and disjoint from the inputs.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn kasumi_syntax_highlight(
    source: *const u8,
    source_length: usize,
    language: *const u8,
    language_length: usize,
    output: *mut SyntaxSpan,
    capacity: usize,
) -> usize {
    if source_length > MAX_BYTES
        || language_length > 128
        || (source.is_null() && source_length != 0)
        || (language.is_null() && language_length != 0)
    {
        return usize::MAX;
    }
    catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: sizes/nulls checked above; callers supply readable buffers.
        let source = if source_length == 0 {
            &[]
        } else {
            unsafe { slice::from_raw_parts(source, source_length) }
        };
        let language = if language_length == 0 {
            &[]
        } else {
            unsafe { slice::from_raw_parts(language, language_length) }
        };
        let (Ok(source), Ok(language)) = (str::from_utf8(source), str::from_utf8(language)) else {
            return usize::MAX;
        };
        let Some(spans) = tokens(source, language) else {
            return usize::MAX;
        };
        if !output.is_null() && capacity >= spans.len() && !spans.is_empty() {
            // SAFETY: output is caller-owned, aligned, sufficiently large, and disjoint.
            unsafe { std::ptr::copy_nonoverlapping(spans.as_ptr(), output, spans.len()) };
        }
        spans.len()
    }))
    .unwrap_or(usize::MAX)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bundled_languages_cover_common_reader_fences() {
        let syntaxes = SYNTAXES.get_or_init(two_face::syntax::extra_newlines);
        for language in [
            "rs", "swift", "py", "js", "ts", "json", "cpp", "bash", "yaml", "html", "css", "sql",
        ] {
            assert!(
                syntaxes.find_syntax_by_token(language).is_some(),
                "Missing {language}; bundled: {:?}",
                syntaxes
                    .syntaxes()
                    .iter()
                    .map(|s| &s.name)
                    .collect::<Vec<_>>()
            );
        }
    }

    #[test]
    fn ffi_rejects_invalid_input_and_preserves_small_output() {
        let source = b"let value = 42;";
        let language = b"rust";
        let sentinel = SyntaxSpan {
            location: 999,
            length: 999,
            role: 999,
        };
        let mut output = [sentinel];
        unsafe {
            assert_eq!(
                kasumi_syntax_highlight(
                    std::ptr::null(),
                    1,
                    language.as_ptr(),
                    language.len(),
                    std::ptr::null_mut(),
                    0
                ),
                usize::MAX
            );
            assert_eq!(
                kasumi_syntax_highlight(
                    [0xff].as_ptr(),
                    1,
                    language.as_ptr(),
                    language.len(),
                    std::ptr::null_mut(),
                    0
                ),
                usize::MAX
            );
            assert!(
                kasumi_syntax_highlight(
                    source.as_ptr(),
                    source.len(),
                    language.as_ptr(),
                    language.len(),
                    output.as_mut_ptr(),
                    1
                ) > 1
            );
            assert_eq!(output, [sentinel]);
            let count = kasumi_syntax_highlight(
                source.as_ptr(),
                source.len(),
                language.as_ptr(),
                language.len(),
                std::ptr::null_mut(),
                0,
            );
            let mut output = vec![sentinel; count];
            assert_eq!(
                kasumi_syntax_highlight(
                    source.as_ptr(),
                    source.len(),
                    language.as_ptr(),
                    language.len(),
                    output.as_mut_ptr(),
                    count
                ),
                count
            );
            assert!(output.iter().all(|s| s.location + s.length <= source.len()));
        }
    }
}
