use std::{
    panic::{AssertUnwindSafe, catch_unwind},
    slice, str,
};
use unicode_linebreak::{BreakOpportunity, linebreaks};

#[repr(C)]
pub struct KasumiLineBreak {
    pub offset: usize,
    pub mandatory: u8,
}

/// Caller-owned, two-pass C interface. See CLineBreak.h for the safety contract.
///
/// # Safety
/// Nonempty input must be readable for `length` bytes. A nonnull output with
/// sufficient capacity must be aligned, writable, and disjoint from the input.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn kasumi_linebreaks(
    utf8: *const u8,
    length: usize,
    out: *mut KasumiLineBreak,
    capacity: usize,
) -> usize {
    if length > isize::MAX as usize || (utf8.is_null() && length != 0) {
        return usize::MAX;
    }
    catch_unwind(AssertUnwindSafe(|| {
        let bytes = if length == 0 {
            &[]
        } else {
            // SAFETY: the caller provides readable bytes; size/null were checked.
            unsafe { slice::from_raw_parts(utf8, length) }
        };
        let Ok(text) = str::from_utf8(bytes) else {
            return usize::MAX;
        };
        let count = linebreaks(text).count();
        if !out.is_null() && capacity >= count {
            for (index, (offset, opportunity)) in linebreaks(text).enumerate() {
                // SAFETY: caller supplies enough aligned storage, disjoint from
                // input; the deterministic second pass yields exactly count.
                unsafe {
                    out.add(index).write(KasumiLineBreak {
                        offset,
                        mandatory: u8::from(opportunity == BreakOpportunity::Mandatory),
                    });
                }
            }
        }
        count
    }))
    .unwrap_or(usize::MAX)
}
