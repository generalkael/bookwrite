//! Inline comments: notes to yourself inside the text, written
//! `{>> like this <<}` (the CriticMarkup comment syntax). They stay in the
//! document but are left out of word counts, compile and reading mode.
//!
//! A comment opens with `{>>` and closes with the first `<<}` after it on
//! the same line; an unclosed `{>>` is ordinary text.

use std::borrow::Cow;

use serde::Serialize;

pub const OPEN: &str = "{>>";
pub const CLOSE: &str = "<<}";

/// Byte ranges of every comment in `text`, markers included.
pub fn ranges(text: &str) -> Vec<(usize, usize)> {
    let mut out = Vec::new();
    let mut from = 0;
    while let Some(i) = text[from..].find(OPEN) {
        let start = from + i;
        let inner = start + OPEN.len();
        let line_end = text[inner..].find('\n').map_or(text.len(), |k| inner + k);
        match text[inner..line_end].find(CLOSE) {
            Some(k) => {
                let end = inner + k + CLOSE.len();
                out.push((start, end));
                from = end;
            }
            None => from = inner,
        }
    }
    out
}

/// `text` without its comments. A line that held only comments disappears
/// (so it doesn't split a paragraph), and the space around a comment
/// between two words is not doubled.
pub fn strip(text: &str) -> Cow<'_, str> {
    let rs = ranges(text);
    if rs.is_empty() {
        return Cow::Borrowed(text);
    }
    let mut out = String::with_capacity(text.len());
    let mut last = 0;
    for (s, e) in rs {
        out.push_str(&text[last..s]);
        // "a {>>x<<} b" → "a b"
        if out.ends_with(' ') && text[e..].starts_with(' ') {
            out.pop();
        }
        last = e;
    }
    out.push_str(&text[last..]);
    // Drop lines that only held comments. The lines of `text` and `out`
    // pair up because a comment never spans a newline.
    let mut kept = String::with_capacity(out.len());
    for (orig, line) in text.split('\n').zip(out.split('\n')) {
        if line.trim().is_empty() && !orig.trim().is_empty() {
            continue;
        }
        kept.push_str(line);
        kept.push('\n');
    }
    kept.pop();
    Cow::Owned(kept)
}

#[derive(Serialize, Debug, PartialEq)]
pub struct Comment {
    /// Position in UTF-16 code units (what QML's TextEdit uses), markers included.
    pub start: usize,
    pub end: usize,
    /// The comment's text, without the markers.
    pub text: String,
}

/// Every comment in `text`, in order.
pub fn list(text: &str) -> Vec<Comment> {
    let mut out = Vec::new();
    let mut pos = 0; // bytes counted so far
    let mut units = 0; // UTF-16 units up to `pos`
    let utf16 = |s: &str| s.encode_utf16().count();
    for (s, e) in ranges(text) {
        units += utf16(&text[pos..s]);
        let len = utf16(&text[s..e]);
        out.push(Comment {
            start: units,
            end: units + len,
            text: text[s + OPEN.len()..e - CLOSE.len()].trim().to_string(),
        });
        units += len;
        pos = e;
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_comments_on_one_line() {
        let t = "One {>>check this<<} two {>>unclosed\n<<} three {>> b <<}";
        assert_eq!(
            ranges(t).iter().map(|&(s, e)| &t[s..e]).collect::<Vec<_>>(),
            vec!["{>>check this<<}", "{>> b <<}"]
        );
    }

    #[test]
    fn strip_keeps_the_prose_tidy() {
        assert_eq!(strip("plain"), Cow::Borrowed("plain"));
        assert_eq!(strip("a {>>note<<} b"), "a b");
        assert_eq!(strip("end.{>>note<<}"), "end.");
        assert_eq!(
            strip("First line\n{>>only a note<<}\nsecond line\n\nNext"),
            "First line\nsecond line\n\nNext"
        );
        assert_eq!(strip("x\n\n{>>n<<}\n\ny"), "x\n\n\ny");
    }

    #[test]
    fn list_uses_utf16_positions() {
        let l = list("“Hi” 😀 {>> fix <<}!");
        assert_eq!(l.len(), 1);
        // “Hi” = 4 units, space, 😀 = 2 units, space → 8
        assert_eq!(l[0].start, 8);
        assert_eq!(l[0].end, 8 + 11);
        assert_eq!(l[0].text, "fix");
    }
}
