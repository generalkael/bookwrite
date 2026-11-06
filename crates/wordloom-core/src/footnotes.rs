//! Footnotes in compiled output, written the Markdown way:
//!
//! ```text
//! The keeper's log said otherwise.[^log]
//!
//! [^log]: The log for October 1891 is missing two pages.
//! ```
//!
//! A definition is a paragraph of its own starting `[^label]:`, in the same
//! document as the reference. Compile numbers the notes through the whole
//! book in the order they're referenced, takes the definitions out of the
//! text, and replaces each reference with a marker that every format renders
//! its own way: real footnotes in Word, superscript links and a Notes
//! section in HTML and EPUB, `[^n]` in Markdown, `[n]` in plain text.
//! A reference without a definition is left as typed; a definition that
//! nothing refers to is left out.

use std::collections::HashMap;

/// Around a note number in compiled text (Unicode private-use characters,
/// which can't come from what the writer typed in practice).
pub(crate) const OPEN: char = '\u{E000}';
pub(crate) const CLOSE: char = '\u{E001}';
/// Stands for the file holding the notes in an HTML link (empty for a
/// single-file book; EPUB puts the notes in a chapter file of their own).
pub(crate) const NOTES_FILE: char = '\u{E002}';

/// Number the footnotes in one document, continuing from `notes`: returns
/// the text with definitions removed and references replaced by markers
/// (or `None` if it has no footnotes), and appends the note texts to `notes`.
pub(crate) fn number(text: &str, notes: &mut Vec<String>) -> Option<String> {
    if !text.contains("[^") {
        return None;
    }
    let mut defs: HashMap<String, String> = HashMap::new();
    let mut kept: Vec<&str> = Vec::new();
    for block in text.split("\n\n") {
        match definition(block) {
            Some((label, note)) => {
                defs.insert(label, note);
            }
            None => kept.push(block),
        }
    }
    let body = kept.join("\n\n");
    let mut numbers: HashMap<String, usize> = HashMap::new();
    let mut out = String::with_capacity(body.len());
    let mut rest = body.as_str();
    while let Some(i) = rest.find("[^") {
        out.push_str(&rest[..i]);
        let after = &rest[i + 2..];
        let label_end = after.find(']');
        let label = label_end.map(|e| &after[..e]);
        match label {
            Some(l) if valid_label(l) && defs.contains_key(l) => {
                let n = *numbers.entry(l.to_string()).or_insert_with(|| {
                    notes.push(defs[l].clone());
                    notes.len()
                });
                out.push(OPEN);
                out.push_str(&n.to_string());
                out.push(CLOSE);
                rest = &after[l.len() + 1..];
            }
            _ => {
                out.push_str("[^");
                rest = after;
            }
        }
    }
    out.push_str(rest);
    Some(out)
}

fn valid_label(l: &str) -> bool {
    !l.is_empty() && !l.chars().any(|c| c.is_whitespace() || c == '[' || c == '^')
}

/// `[^label]: text` (the text may run over several lines).
fn definition(block: &str) -> Option<(String, String)> {
    let b = block.trim();
    let rest = b.strip_prefix("[^")?;
    let end = rest.find("]:")?;
    let label = &rest[..end];
    if !valid_label(label) {
        return None;
    }
    let note: Vec<&str> = rest[end + 2..].lines().map(str::trim).collect();
    Some((label.to_string(), note.join(" ").trim().to_string()))
}

/// Replace each note marker with `f(n)`.
pub(crate) fn render(text: &str, f: impl Fn(usize) -> String) -> String {
    if !text.contains(OPEN) {
        return text.to_string();
    }
    let mut out = String::with_capacity(text.len() + 16);
    let mut rest = text;
    while let Some(i) = rest.find(OPEN) {
        out.push_str(&rest[..i]);
        let after = &rest[i + OPEN.len_utf8()..];
        match after.find(CLOSE) {
            Some(e) => {
                match after[..e].parse::<usize>() {
                    Ok(n) => out.push_str(&f(n)),
                    Err(_) => out.push_str(&after[..e]),
                }
                rest = &after[e + CLOSE.len_utf8()..];
            }
            None => {
                rest = after;
            }
        }
    }
    out.push_str(rest);
    out
}

/// A note reference as HTML: a superscript number linking to the note.
pub(crate) fn html_ref(n: usize) -> String {
    format!("<sup class=\"fnref\"><a href=\"{NOTES_FILE}#fn-{n}\">{n}</a></sup>")
}

/// Split text at note markers: `(text before, Some(n))` pairs, the last
/// with `None`.
pub(crate) fn split(text: &str) -> Vec<(String, Option<usize>)> {
    let mut out = Vec::new();
    let mut rest = text;
    while let Some(i) = rest.find(OPEN) {
        let after = &rest[i + OPEN.len_utf8()..];
        let Some(e) = after.find(CLOSE) else { break };
        out.push((rest[..i].to_string(), after[..e].parse().ok()));
        rest = &after[e + CLOSE.len_utf8()..];
    }
    out.push((rest.to_string(), None));
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn shown(s: &str) -> String {
        render(s, |n| format!("<{n}>"))
    }

    #[test]
    fn numbers_references_and_removes_definitions() {
        let mut notes = Vec::new();
        let t = number(
            "One.[^a] Two.[^b]\n\n[^a]: First\nnote.\n\nMore.[^a]\n\n[^b]: Second.",
            &mut notes,
        )
        .unwrap();
        assert_eq!(shown(&t), "One.<1> Two.<2>\n\nMore.<1>");
        assert_eq!(notes, ["First note.", "Second."]);
        // Numbering continues in the next document.
        let t = number("Three.[^x]\n\n[^x]: Third.", &mut notes).unwrap();
        assert_eq!(shown(&t), "Three.<3>");
    }

    #[test]
    fn undefined_and_unreferenced_notes() {
        let mut notes = Vec::new();
        let t = number(
            "See [^nope] and [^ spaced].\n\n[^unused]: Never cited.",
            &mut notes,
        )
        .unwrap();
        assert_eq!(shown(&t), "See [^nope] and [^ spaced].");
        assert!(notes.is_empty());
        assert!(number("No notes here.", &mut notes).is_none());
    }

    #[test]
    fn split_at_markers() {
        let mut notes = Vec::new();
        let t = number("A[^1] b[^2]\n\n[^1]: x\n\n[^2]: y", &mut notes).unwrap();
        assert_eq!(
            split(&t),
            [
                ("A".to_string(), Some(1)),
                (" b".to_string(), Some(2)),
                (String::new(), None)
            ]
        );
    }

    #[test]
    fn every_format_renders_the_notes() {
        use crate::compile::{compile, compile_file, CompileOptions, Format};
        use crate::model::{NodeKind, Project, RootRole};
        let mut p = Project::new("Book", "Me");
        let ms = p.root(RootRole::Manuscript);
        let ch = p.nodes[&ms].children[0];
        let s1 = p.nodes[&ch].children[0];
        p.set_text(s1, "The log lied.[^log] *Twice.*[^two]\n\n[^log]: Pages were cut.\n\n[^two]: Per the *Gazette*.".into())
            .unwrap();
        let ch2 = p.add_node(ms, None, NodeKind::Folder, "Two").unwrap();
        let s2 = p.add_node(ch2, None, NodeKind::Text, "S").unwrap();
        p.set_text(s2, "Later.[^a]\n\n[^a]: Third note.".into())
            .unwrap();
        let opts = |format| CompileOptions {
            format,
            ..Default::default()
        };

        let md = compile(&p, &opts(Format::Markdown));
        assert!(
            md.contains("The log lied.[^1] *Twice.*[^2]") && md.contains("Later.[^3]"),
            "{md}"
        );
        assert!(
            md.trim_end().ends_with(
                "[^1]: Pages were cut.\n\n[^2]: Per the *Gazette*.\n\n[^3]: Third note."
            ),
            "{md}"
        );
        assert!(!md.contains("[^log]"));

        let txt = compile(&p, &opts(Format::PlainText));
        assert!(
            txt.contains("The log lied.[1] Twice.[2]")
                && txt.contains("NOTES\n\n1. Pages were cut.\n\n2. Per the Gazette."),
            "{txt}"
        );

        let html = compile(&p, &opts(Format::Html));
        assert!(
            html.contains("lied.<sup class=\"fnref\"><a href=\"#fn-1\">1</a></sup>"),
            "{html}"
        );
        assert!(html.contains("<li id=\"fn-2\">Per the <em>Gazette</em>.</li>"));
        assert!(!html.contains(NOTES_FILE));

        let epub = String::from_utf8_lossy(&compile_file(&p, &opts(Format::Epub))).into_owned();
        // Title page, two chapters, then the notes in c3.xhtml.
        assert!(
            epub.contains("<a href=\"c3.xhtml#fn-1\">1</a>"),
            "references link to the notes chapter"
        );
        assert!(epub.contains("<li id=\"fn-3\">Third note.</li>"));

        let docx = String::from_utf8_lossy(&compile_file(&p, &opts(Format::Docx))).into_owned();
        assert!(
            docx.contains("<w:footnoteReference w:id=\"1\"/>")
                && docx.contains("<w:footnoteReference w:id=\"3\"/>")
        );
        assert!(docx.contains("<w:footnote w:id=\"2\">") && docx.contains("Gazette"));
        assert!(docx.contains("word/footnotes.xml") && docx.contains("relationships/footnotes"));

        let pdf =
            crate::print::print_html(&p, &opts(Format::Pdf), crate::print::PdfStyle::Manuscript);
        let end = pdf.find(">END</p>").unwrap();
        let notes = pdf.rfind(">Notes</p>").unwrap();
        assert!(end < notes, "END comes before the notes");
        assert!(pdf.contains("1. Pages were cut.") && !pdf.contains(NOTES_FILE));
    }
}
