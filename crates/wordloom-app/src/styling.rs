//! Bridge to the C++ Markdown highlighter (styler.h / styler.cpp), and the
//! spell-check callback it uses.

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("wordloom/src/styler.h");
        /// Registers `MarkdownStyler` as `import com.wordloom.styling`.
        fn register_styler_types();
    }

    extern "Rust" {
        /// True if `word` is spelled correctly (or is a project name).
        fn spell_ok(word: &str) -> bool;
    }
}

fn spell_ok(word: &str) -> bool {
    wordloom_core::spell::with(|s| s.check(word))
}
