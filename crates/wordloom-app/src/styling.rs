//! Bridge to the C++ Markdown highlighter (styler.h / styler.cpp).

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("wordloom/src/styler.h");
        /// Registers `MarkdownStyler` as `import com.wordloom.styling`.
        fn register_styler_types();
    }
}
