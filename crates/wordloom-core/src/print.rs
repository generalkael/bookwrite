//! The manuscript as HTML for paged output (the app's PDF export, which
//! lays it out with Qt's text engine and adds the title page, running
//! header and page numbers itself).
//!
//! Two looks: **Book** (justified, book-style indents, chapters on new
//! pages) and **Manuscript**, the standard submission format: double
//! spaced, half-inch indents, chapter titles a third of the way down a new
//! page, and "END" at the close. CSS lengths are px at 96 per inch.
//!
//! Each chapter starts after a [`CHAPTER`] marker, and the app lays out
//! every chapter on its own pages (Qt's page breaks add a title's top margin
//! twice, so they aren't used). A hairline empty paragraph comes before each
//! chapter title, because Qt ignores the top margin of a document's first
//! block.

use serde::{Deserialize, Serialize};

use crate::compile::{blocks, esc, inline_html, pieces, Block, CompileOptions, Piece};
use crate::model::Project;

#[derive(Serialize, Deserialize, Clone, Copy, PartialEq, Eq, Debug, Default)]
#[serde(rename_all = "snake_case")]
pub enum PdfStyle {
    #[default]
    Book,
    Manuscript,
}

/// Comes before each chapter title.
pub const CHAPTER: &str = "<!--wordloom:chapter-->";

/// Keeps a chapter title from being its document's first block.
const SPACER: &str =
    "<p style=\"margin-top:0;margin-bottom:0;font-size:1pt;line-height:100%\">&nbsp;</p>";

/// Inline styles for each kind of block. (Qt's rich text applies inline
/// styles reliably; its stylesheet selectors and heading defaults less so.)
struct Look {
    para: &'static str,
    first: &'static str,
    chapter: &'static str,
    sub: &'static str,
    sep: &'static str,
    quote: &'static str,
}

const BOOK: Look = Look {
    para: "margin-top:0;margin-bottom:0;text-indent:24px;line-height:135%;text-align:justify",
    first: "margin-top:0;margin-bottom:0;text-indent:0;line-height:135%;text-align:justify",
    chapter: "margin-top:110px;margin-bottom:40px;text-align:center;text-indent:0;font-size:18pt",
    sub: "margin-top:24px;margin-bottom:14px;text-align:center;text-indent:0;font-size:13pt;font-style:italic",
    sep: "margin-top:14px;margin-bottom:14px;text-align:center;text-indent:0",
    quote: "margin-top:8px;margin-bottom:8px;margin-left:36px;margin-right:36px;text-indent:0;line-height:135%;font-style:italic",
};

const MANUSCRIPT: Look = Look {
    para: "margin-top:0;margin-bottom:0;text-indent:48px;line-height:200%",
    first: "margin-top:0;margin-bottom:0;text-indent:48px;line-height:200%",
    // A third of the way down the page.
    chapter: "margin-top:210px;margin-bottom:24px;text-align:center;text-indent:0;line-height:200%",
    sub: "margin-top:0;margin-bottom:0;text-align:center;text-indent:0;line-height:200%",
    sep: "margin-top:0;margin-bottom:0;text-align:center;text-indent:0;line-height:200%",
    quote: "margin-top:0;margin-bottom:0;margin-left:48px;margin-right:48px;text-indent:0;line-height:200%",
};

/// The body of the paged document. The title page is drawn by the app.
pub fn print_html(p: &Project, opts: &CompileOptions, style: PdfStyle) -> String {
    let look = match style {
        PdfStyle::Book => &BOOK,
        PdfStyle::Manuscript => &MANUSCRIPT,
    };
    let mut body = String::new();
    // Paragraphs after a heading or scene break aren't indented (in Book
    // style; manuscripts indent every paragraph).
    let mut first = true;
    let mut started = false;
    let mut ended = false;
    let heading = |body: &mut String, d: usize, t: &str, started: &mut bool| {
        if d <= 1 {
            // A chapter: the app starts it on a new page.
            body.push_str(CHAPTER);
            body.push_str(SPACER);
            body.push_str(&format!("\n<p style=\"{}\">{}</p>\n", look.chapter, esc(t)));
        } else {
            body.push_str(&format!("<p style=\"{}\">{}</p>\n", look.sub, esc(t)));
        }
        *started = true;
    };
    for piece in pieces(p, opts) {
        match piece {
            // Endnotes: a chapter of their own, numbered.
            Piece::Notes(notes) => {
                // A manuscript's END goes after the story, before the notes.
                if style == PdfStyle::Manuscript && started && !ended {
                    body.push_str(&format!("<p style=\"{}\">END</p>\n", look.sep));
                    ended = true;
                }
                heading(&mut body, 1, "Notes", &mut started);
                for (i, n) in notes.iter().enumerate() {
                    body.push_str(&format!(
                        "<p style=\"{}\">{}. {}</p>\n",
                        look.first,
                        i + 1,
                        inline_html(n)
                    ));
                }
                first = true;
            }
            Piece::Heading(d, t) => {
                heading(&mut body, d, &t, &mut started);
                first = true;
            }
            Piece::Separator => {
                body.push_str(&format!(
                    "<p style=\"{}\">{}</p>\n",
                    look.sep,
                    esc(&opts.scene_separator)
                ));
                first = true;
            }
            Piece::Body(md) => {
                for b in blocks(&md) {
                    match b {
                        Block::Heading(level, t) => {
                            heading(&mut body, level + 1, t, &mut started);
                            first = true;
                        }
                        Block::Rule => {
                            body.push_str(&format!("<p style=\"{}\">* * *</p>\n", look.sep));
                            first = true;
                        }
                        Block::Quote(t) => {
                            body.push_str(&format!(
                                "<p style=\"{}\">{}</p>\n",
                                look.quote,
                                inline_html(&t)
                            ));
                            started = true;
                            first = true;
                        }
                        Block::Para(t) => {
                            let st = if first { look.first } else { look.para };
                            body.push_str(&format!("<p style=\"{st}\">{}</p>\n", inline_html(&t)));
                            started = true;
                            first = false;
                        }
                    }
                }
            }
        }
    }
    if style == PdfStyle::Manuscript && started && !ended {
        body.push_str(&format!("<p style=\"{}\">END</p>\n", look.sep));
    }
    // The notes are in the same document.
    let body = body.replace(crate::footnotes::NOTES_FILE, "");
    format!("<html><body>\n{body}</body></html>\n")
}

/// "about 80,000 words": rounded the way submission title pages do it (to
/// the nearest hundred under 10,000 words, else the nearest thousand).
pub fn word_estimate(words: usize) -> String {
    let step = if words < 10_000 { 100 } else { 1000 };
    let mut rounded = (words + step / 2) / step * step;
    if rounded == 0 {
        rounded = words; // a very short piece: give the exact count
    }
    let mut s = rounded.to_string();
    let mut i = s.len() as isize - 3;
    while i > 0 {
        s.insert(i as usize, ',');
        i -= 3;
    }
    format!("about {s} words")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{NodeKind, RootRole};

    fn book() -> Project {
        let mut p = Project::new("Book", "Ann Author");
        let ms = p.root(RootRole::Manuscript);
        let ch = p.nodes[&ms].children[0];
        let s1 = p.nodes[&ch].children[0];
        p.set_text(s1, "One *two*.\n\nThree.".into()).unwrap();
        let s2 = p.add_node(ch, None, NodeKind::Text, "S2").unwrap();
        p.set_text(s2, "Four.".into()).unwrap();
        let ch2 = p.add_node(ms, None, NodeKind::Folder, "Two").unwrap();
        let s3 = p.add_node(ch2, None, NodeKind::Text, "S3").unwrap();
        p.set_text(s3, "Five.".into()).unwrap();
        p
    }

    #[test]
    fn book_layout() {
        let html = print_html(&book(), &CompileOptions::default(), PdfStyle::Book);
        // Every chapter starts after the marker; nothing else does.
        assert_eq!(html.matches(CHAPTER).count(), 2);
        assert!(!html.contains("page-break"));
        assert!(html.contains(&format!("{CHAPTER}{SPACER}\n<p style=\"margin-top:110px;margin-bottom:40px;text-align:center;text-indent:0;font-size:18pt\">Two</p>")));
        assert!(html
            .contains("text-indent:0;line-height:135%;text-align:justify\">One <em>two</em>.</p>"));
        assert!(html.contains("text-indent:24px;line-height:135%;text-align:justify\">Three.</p>"));
        assert!(!html.contains("END"));
    }

    #[test]
    fn manuscript_layout() {
        let html = print_html(&book(), &CompileOptions::default(), PdfStyle::Manuscript);
        assert!(html.contains("line-height:200%"));
        assert!(html.ends_with(">END</p>\n</body></html>\n"));
    }

    #[test]
    fn word_estimates() {
        assert_eq!(word_estimate(42), "about 42 words");
        assert_eq!(word_estimate(4_321), "about 4,300 words");
        assert_eq!(word_estimate(81_499), "about 81,000 words");
        assert_eq!(word_estimate(1_234_567), "about 1,235,000 words");
    }
}
