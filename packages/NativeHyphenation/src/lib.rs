use hyphenation::{Hyphenator, Language, Load, Standard};
use std::{
    io::Cursor,
    panic::{AssertUnwindSafe, catch_unwind},
    slice, str,
    sync::OnceLock,
};

struct Dictionary {
    tag: &'static str,
    language: Language,
    bytes: &'static [u8],
}

macro_rules! dictionaries {
    ($($tag:literal => $language:ident),+ $(,)?) => {
        static DICTIONARIES: &[Dictionary] = &[$(Dictionary {
            tag: $tag,
            language: Language::$language,
            bytes: include_bytes!(concat!("../dictionaries/", $tag, ".standard.bincode")),
        }),+];
    };
}

dictionaries! {
    "en-us" => EnglishUS,
    "en-gb" => EnglishGB,
    "de-1996" => German1996,
    "fr" => French,
    "es" => Spanish,
    "it" => Italian,
    "pt" => Portuguese,
    "nl" => Dutch,
    "sv" => Swedish,
    "da" => Danish,
    "nb" => NorwegianBokmal,
    "fi" => Finnish,
    "pl" => Polish,
    "cs" => Czech,
    "ru" => Russian,
}

static CACHE: [OnceLock<Option<Standard>>; 15] = [const { OnceLock::new() }; 15];

/// Caller-owned, two-pass C interface. See CHyphenation.h for the contract.
///
/// # Safety
/// Nonempty inputs must be readable for their supplied lengths. A nonnull
/// output with sufficient capacity must be aligned, writable, and disjoint
/// from both inputs.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn kasumi_hyphenate(
    word: *const u8,
    word_length: usize,
    language: *const u8,
    language_length: usize,
    output: *mut usize,
    capacity: usize,
) -> usize {
    if word_length > isize::MAX as usize
        || language_length > isize::MAX as usize
        || (word.is_null() && word_length != 0)
        || (language.is_null() && language_length != 0)
    {
        return usize::MAX;
    }
    catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: sizes/nulls were checked; callers supply readable buffers.
        let word_bytes = if word_length == 0 {
            &[]
        } else {
            unsafe { slice::from_raw_parts(word, word_length) }
        };
        let language_bytes = if language_length == 0 {
            &[]
        } else {
            unsafe { slice::from_raw_parts(language, language_length) }
        };
        let (Ok(word), Ok(language)) = (str::from_utf8(word_bytes), str::from_utf8(language_bytes))
        else {
            return usize::MAX;
        };
        let Some(index) = DICTIONARIES
            .iter()
            .position(|dictionary| dictionary.tag.eq_ignore_ascii_case(language))
        else {
            return usize::MAX;
        };
        let dictionary = &DICTIONARIES[index];
        let Some(loaded) = CACHE[index].get_or_init(|| {
            Standard::from_reader(dictionary.language, &mut Cursor::new(dictionary.bytes))
                .ok()
                .map(|mut loaded| {
                    // Native wrapper policy, applied before immutable publication.
                    // This differs from upstream's French right minimum of three.
                    let right = match dictionary.language {
                        Language::EnglishUS
                        | Language::EnglishGB
                        | Language::Portuguese
                        | Language::Czech => 3,
                        _ => 2,
                    };
                    loaded.minima = (2, right);
                    loaded
                })
        }) else {
            return usize::MAX;
        };
        let breaks = loaded.hyphenate(word).breaks;
        if !output.is_null() && capacity >= breaks.len() && !breaks.is_empty() {
            // SAFETY: caller supplies enough aligned storage disjoint from input;
            // the temporary vector belongs to this call and cannot alias output.
            unsafe { std::ptr::copy_nonoverlapping(breaks.as_ptr(), output, breaks.len()) };
        }
        breaks.len()
    }))
    .unwrap_or(usize::MAX)
}
