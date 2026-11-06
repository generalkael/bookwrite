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
        /// Repeated words in one paragraph, as flat UTF-16
        /// `[start, end, start, end, …]` offsets.
        fn repeated_words(text: &str) -> Vec<u32>;
    }
}

fn spell_ok(word: &str) -> bool {
    wordloom_core::spell::with(|s| s.check(word))
}

fn repeated_words(text: &str) -> Vec<u32> {
    wordloom_core::repeats::repeats(text, wordloom_core::repeats::WINDOW)
        .into_iter()
        .flat_map(|(s, e)| [s as u32, e as u32])
        .collect()
}
