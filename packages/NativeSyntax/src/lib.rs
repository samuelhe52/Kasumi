use std::{
    ffi::c_void,
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

#[cfg(test)]
std::thread_local! {
    static PARSE_PASSES: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}

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
    #[cfg(test)]
    PARSE_PASSES.with(|count| count.set(count.get() + 1));
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

unsafe fn highlight_input(
    source: *const u8,
    source_length: usize,
    language: *const u8,
    language_length: usize,
) -> Option<Vec<SyntaxSpan>> {
    if source_length > MAX_BYTES
        || language_length > 128
        || (source.is_null() && source_length != 0)
        || (language.is_null() && language_length != 0)
    {
        return None;
    }
    // SAFETY: sizes/nulls checked above; the caller supplies readable inputs.
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
    tokens(str::from_utf8(source).ok()?, str::from_utf8(language).ok()?)
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
    catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: the caller supplies readable input buffers for these lengths.
        let Some(spans) =
            (unsafe { highlight_input(source, source_length, language, language_length) })
        else {
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

pub type SyntaxVisitor = unsafe extern "C" fn(*const SyntaxSpan, usize, *mut c_void);

/// # Safety
/// Nonempty inputs must be readable for the supplied lengths. The visitor and
/// context must remain valid until this call returns. The visitor must not keep
/// the borrowed span pointer or unwind across this FFI boundary.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn kasumi_syntax_highlight_visit(
    source: *const u8,
    source_length: usize,
    language: *const u8,
    language_length: usize,
    visitor: Option<SyntaxVisitor>,
    context: *mut c_void,
) -> usize {
    let Some(visitor) = visitor else {
        return usize::MAX;
    };
    catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: the caller supplies readable input buffers for these lengths.
        let Some(spans) =
            (unsafe { highlight_input(source, source_length, language, language_length) })
        else {
            return usize::MAX;
        };
        let data = if spans.is_empty() {
            std::ptr::null()
        } else {
            spans.as_ptr()
        };
        // SAFETY: the immutable vector outlives this synchronous callback. The
        // caller supplies a valid visitor/context and does not retain data.
        unsafe { visitor(data, spans.len(), context) };
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

    #[derive(Default)]
    struct Capture {
        calls: usize,
        spans: Vec<SyntaxSpan>,
    }

    unsafe extern "C" fn capture_spans(
        data: *const SyntaxSpan,
        count: usize,
        context: *mut c_void,
    ) {
        // SAFETY: tests pass a live Capture and the bridge lends readable spans
        // during this callback. Copy values instead of retaining its pointer.
        let capture = unsafe { &mut *context.cast::<Capture>() };
        capture.calls += 1;
        if count == 0 {
            assert!(data.is_null());
        } else {
            capture
                .spans
                .extend_from_slice(unsafe { slice::from_raw_parts(data, count) });
        }
    }

    #[test]
    fn visitor_matches_legacy_spans_with_one_parser_pass() {
        for (source, language) in [
            (
                "/* 中文🙂\r\nlet hidden = 7; */\r\nlet text = \"e\u{301}👩‍💻\";",
                "rust",
            ),
            (
                "let message = \"Reflow and scroll\"\nprint(message)\n",
                "swift",
            ),
            ("if True:\n    print(\"hello\") # comment", "python"),
        ] {
            let mut capture = Capture::default();
            unsafe {
                let count = kasumi_syntax_highlight(
                    source.as_ptr(),
                    source.len(),
                    language.as_ptr(),
                    language.len(),
                    std::ptr::null_mut(),
                    0,
                );
                assert!(count > 0 && count < source.len());
                let mut expected = vec![
                    SyntaxSpan {
                        location: 0,
                        length: 0,
                        role: 0
                    };
                    count
                ];
                assert_eq!(
                    kasumi_syntax_highlight(
                        source.as_ptr(),
                        source.len(),
                        language.as_ptr(),
                        language.len(),
                        expected.as_mut_ptr(),
                        count,
                    ),
                    count
                );
                let before = PARSE_PASSES.with(|passes| passes.get());
                assert_eq!(
                    kasumi_syntax_highlight_visit(
                        source.as_ptr(),
                        source.len(),
                        language.as_ptr(),
                        language.len(),
                        Some(capture_spans),
                        (&mut capture as *mut Capture).cast(),
                    ),
                    count
                );
                assert_eq!(PARSE_PASSES.with(|passes| passes.get()), before + 1);
                assert_eq!(capture.calls, 1);
                assert_eq!(capture.spans, expected);
            }
        }
    }

    #[test]
    fn visitor_handles_empty_fallbacks_and_rejects_invalid_calls() {
        let source = b"let value = 42;";
        let invalid_utf8 = [0xff];
        let mut capture = Capture::default();
        for language in ["plain", "unknown-language"] {
            let mut empty = Capture::default();
            assert_eq!(
                unsafe {
                    kasumi_syntax_highlight_visit(
                        source.as_ptr(),
                        source.len(),
                        language.as_ptr(),
                        language.len(),
                        Some(capture_spans),
                        (&mut empty as *mut Capture).cast(),
                    )
                },
                0
            );
            assert_eq!(empty.calls, 1);
            assert!(empty.spans.is_empty());
        }
        for (input, length, visitor) in [
            (std::ptr::null(), 1, Some(capture_spans as SyntaxVisitor)),
            (
                invalid_utf8.as_ptr(),
                1,
                Some(capture_spans as SyntaxVisitor),
            ),
            (
                source.as_ptr(),
                MAX_BYTES + 1,
                Some(capture_spans as SyntaxVisitor),
            ),
            (source.as_ptr(), source.len(), None),
        ] {
            let language = b"rust";
            assert_eq!(
                unsafe {
                    kasumi_syntax_highlight_visit(
                        input,
                        length,
                        language.as_ptr(),
                        language.len(),
                        visitor,
                        (&mut capture as *mut Capture).cast(),
                    )
                },
                usize::MAX
            );
        }
        assert_eq!(capture.calls, 0);
    }
}
