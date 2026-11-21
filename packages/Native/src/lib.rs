// Build all bridges with one Rust runtime. Their individual crates remain usable
// for focused tests and development tools.
#[path = "../../NativeDagre/src/lib.rs"]
pub mod dagre;
#[path = "../../NativeLineBreak/src/lib.rs"]
pub mod linebreak;
#[path = "../../NativeHyphenation/src/lib.rs"]
pub mod hyphenation;
#[path = "../../NativeSyntax/src/lib.rs"]
pub mod syntax;
