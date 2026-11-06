//! Import a whole manuscript from Word (.docx), Markdown or plain text,
//! split into chapters and scenes.
//!
//! - A chapter starts at a level-1 heading (Word's *Heading 1*, Markdown
//!   `#`) or a paragraph that is only "Chapter 12", "CHAPTER TWELVE: The
//!   Wreck", "Prologue", "Epilogue", "Interlude" and the like.
//! - A scene starts at a level-2 heading (it becomes the scene's title) or
//!   after a scene break: `* * *`, `***`, `---`, `#`, `~`, or a paragraph of
//!   only such symbols.
//! - Word's *Title* paragraph names the imported folder; italic and bold
//!   become `*` / `**`. Text before the first chapter goes in a "Front
//!   Matter" chapter.

use std::path::Path;

use crate::{Error, Result};

#[derive(Debug, PartialEq)]
pub enum Para {
    Title(String),
    Heading(usize, String),
    Break,
    Text(String),
}

#[derive(Debug, Default, PartialEq)]
pub struct Scene {
    pub title: Option<String>,
    pub paras: Vec<String>,
}

#[derive(Debug, Default, PartialEq)]
pub struct Chapter {
    pub title: String,
    pub scenes: Vec<Scene>,
}

#[derive(Debug, Default, PartialEq)]
pub struct Book {
    pub title: Option<String>,
    pub chapters: Vec<Chapter>,
}

// ---------------------------------------------------------------- reading

/// Read a manuscript file by its extension.
pub fn read(path: &Path) -> Result<Book> {
    let ext = path
        .extension()
        .map(|e| e.to_string_lossy().to_lowercase())
        .unwrap_or_default();
    let data = std::fs::read(path)?;
    let paras = match ext.as_str() {
        "docx" => docx_paras(&data)?,
        "md" | "markdown" | "txt" | "text" => text_paras(&String::from_utf8_lossy(&data)),
        _ => {
            return Err(Error::Invalid(format!(
                "Wordloom can import .docx, .md and .txt manuscripts, not .{ext}"
            )))
        }
    };
    Ok(build(paras))
}

/// Markdown or plain text. Paragraphs are separated by blank lines; text
/// with hardly any blank lines has one paragraph per line.
pub fn text_paras(text: &str) -> Vec<Para> {
    let text = text.replace("\r\n", "\n").replace('\r', "\n");
    // A Pandoc title block ("% Title", "% Author", "% Date") at the top:
    // the first line names the book; the rest isn't text.
    let mut title = None;
    let mut body = text.as_str();
    while let Some(rest) = body.trim_start_matches('\n').strip_prefix('%') {
        let (line, after) = rest.split_once('\n').unwrap_or((rest, ""));
        if title.is_none() {
            title = Some(line.trim().to_string());
        }
        body = after;
    }
    let mut out: Vec<Para> = title.into_iter().map(Para::Title).collect();
    out.extend(body_paras(body));
    out
}

fn body_paras(text: &str) -> Vec<Para> {
    let lines = text.lines().filter(|l| !l.trim().is_empty()).count();
    let blanks = text.split("\n\n").count().saturating_sub(1);
    let blocks: Vec<String> = if lines > 4 && blanks * 4 < lines {
        text.lines().map(str::to_string).collect()
    } else {
        text.split("\n\n")
            .map(|b| b.lines().map(str::trim).collect::<Vec<_>>().join(" "))
            .collect()
    };
    blocks
        .iter()
        .map(|b| b.trim())
        .filter(|b| !b.is_empty())
        .map(|b| {
            if let Some(rest) = b.strip_prefix('#') {
                let level = 1 + rest.chars().take_while(|c| *c == '#').count();
                let t = rest.trim_start_matches('#').trim();
                if t.is_empty() {
                    return Para::Break; // a lone "#" is a scene break
                }
                return Para::Heading(level, t.to_string());
            }
            classify(b.to_string())
        })
        .collect()
}

/// A body paragraph that may really be a scene break or a chapter line.
fn classify(t: String) -> Para {
    let plain: String = t.chars().filter(|c| *c != '*' && *c != '_').collect();
    let p = plain.trim();
    if is_break(&t) {
        Para::Break
    } else if is_chapter_line(p) {
        Para::Heading(1, p.to_string())
    } else {
        Para::Text(t)
    }
}

fn is_break(t: &str) -> bool {
    let t = t.trim();
    !t.is_empty()
        && t.chars().count() <= 12
        && t.chars()
            .all(|c| matches!(c, '*' | '-' | '_' | '#' | '~' | '•' | '·' | '⁂' | ' '))
        && (t.chars().filter(|c| !c.is_whitespace()).count() >= 3
            || matches!(t, "#" | "~" | "⁂" | "•"))
}

const NUMBER_WORDS: &[&str] = &[
    "one",
    "two",
    "three",
    "four",
    "five",
    "six",
    "seven",
    "eight",
    "nine",
    "ten",
    "eleven",
    "twelve",
    "thirteen",
    "fourteen",
    "fifteen",
    "sixteen",
    "seventeen",
    "eighteen",
    "nineteen",
    "twenty",
    "thirty",
    "forty",
    "fifty",
];

/// "Chapter 3", "CHAPTER TWENTY-ONE: Home", "Prologue", "Part II", "12".
fn is_chapter_line(p: &str) -> bool {
    if p.is_empty() || p.chars().count() > 70 || p.ends_with(['.', ',', ';']) && !p.ends_with("...")
    {
        return false;
    }
    let lower = p.to_lowercase();
    let first = lower.split([' ', ':', '.', '—', '-']).next().unwrap_or("");
    if matches!(
        first,
        "prologue" | "epilogue" | "interlude" | "afterword" | "foreword"
    ) {
        return lower.split_whitespace().count() <= 6;
    }
    // A bare chapter number ("12" or "XII") on its own line.
    if lower.chars().all(|c| c.is_ascii_digit()) && lower.len() <= 3 {
        return true;
    }
    for word in ["chapter ", "part ", "book "] {
        if let Some(rest) = lower.strip_prefix(word) {
            let n = rest.split([' ', ':', '.', '—']).next().unwrap_or("");
            let numeric = !n.is_empty() && n.chars().all(|c| c.is_ascii_digit());
            let roman = !n.is_empty() && n.chars().all(|c| "ivxlc".contains(c));
            let spelled = n.split('-').all(|w| NUMBER_WORDS.contains(&w));
            return numeric || roman || spelled;
        }
    }
    false
}

// ---------------------------------------------------------------- docx

/// The bytes of `name` in a zip archive (stored or deflated).
fn zip_entry(zip: &[u8], name: &str) -> Option<Vec<u8>> {
    let u16le = |i: usize| {
        zip.get(i..i + 2)
            .map(|b| u16::from_le_bytes([b[0], b[1]]) as usize)
    };
    let u32le = |i: usize| {
        zip.get(i..i + 4)
            .map(|b| u32::from_le_bytes([b[0], b[1], b[2], b[3]]) as usize)
    };
    // End of central directory: the last "PK\5\6".
    let from = zip.len().saturating_sub(22 + 65_535);
    let eocd = (from..zip.len().saturating_sub(21))
        .rev()
        .find(|&i| zip[i..i + 4] == *b"PK\x05\x06")?;
    let count = u16le(eocd + 10)?;
    let mut at = u32le(eocd + 16)?;
    for _ in 0..count {
        if zip.get(at..at + 4)? != b"PK\x01\x02" {
            return None;
        }
        let method = u16le(at + 10)?;
        let csize = u32le(at + 20)?;
        let nlen = u16le(at + 28)?;
        let elen = u16le(at + 30)?;
        let clen = u16le(at + 32)?;
        let local = u32le(at + 42)?;
        let entry = std::str::from_utf8(zip.get(at + 46..at + 46 + nlen)?).ok()?;
        if entry == name {
            let data_at = local + 30 + u16le(local + 26)? + u16le(local + 28)?;
            let raw = zip.get(data_at..data_at + csize)?;
            return match method {
                0 => Some(raw.to_vec()),
                8 => miniz_oxide::inflate::decompress_to_vec(raw).ok(),
                _ => None,
            };
        }
        at += 46 + nlen + elen + clen;
    }
    None
}

fn unescape(s: &str) -> String {
    if !s.contains('&') {
        return s.to_string();
    }
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(i) = rest.find('&') {
        out.push_str(&rest[..i]);
        rest = &rest[i..];
        let Some(end) = rest.find(';') else { break };
        let ent = &rest[1..end];
        let ch = match ent {
            "amp" => Some('&'),
            "lt" => Some('<'),
            "gt" => Some('>'),
            "quot" => Some('"'),
            "apos" => Some('\''),
            _ if ent.starts_with("#x") => u32::from_str_radix(&ent[2..], 16)
                .ok()
                .and_then(char::from_u32),
            _ if ent.starts_with('#') => ent[1..].parse().ok().and_then(char::from_u32),
            _ => None,
        };
        match ch {
            Some(c) => {
                out.push(c);
                rest = &rest[end + 1..];
            }
            None => {
                out.push('&');
                rest = &rest[1..];
            }
        }
    }
    out.push_str(rest);
    out
}

/// The value of attribute `name` (e.g. `w:val`) in a tag's text.
fn attr<'a>(tag: &'a str, name: &str) -> Option<&'a str> {
    let i = tag.find(&format!("{name}=\""))? + name.len() + 2;
    let end = tag[i..].find('"')? + i;
    Some(&tag[i..end])
}

/// Whether a toggle property tag (`<w:i/>`, `<w:b w:val="0"/>`) is on.
fn on(tag: &str) -> bool {
    !matches!(attr(tag, "w:val"), Some("0" | "false" | "off"))
}

/// Paragraph style ids → their names ("Heading1" → "heading 1"), so
/// headings are found whatever language Word was in.
fn style_names(styles: &str) -> Vec<(String, String)> {
    let mut out = Vec::new();
    for chunk in styles.split("<w:style ").skip(1) {
        let head = &chunk[..chunk.find('>').unwrap_or(0)];
        if let (Some(id), Some(n)) = (attr(head, "w:styleId"), chunk.find("<w:name ")) {
            let tag = &chunk[n..n + chunk[n..].find('>').unwrap_or(0)];
            if let Some(name) = attr(tag, "w:val") {
                out.push((id.to_string(), name.to_lowercase()));
            }
        }
    }
    out
}

pub fn docx_paras(data: &[u8]) -> Result<Vec<Para>> {
    let bad = || Error::Invalid("This doesn't look like a Word document (.docx)".into());
    let doc = zip_entry(data, "word/document.xml").ok_or_else(bad)?;
    let doc = String::from_utf8_lossy(&doc);
    let styles = zip_entry(data, "word/styles.xml")
        .map(|s| style_names(&String::from_utf8_lossy(&s)))
        .unwrap_or_default();
    let body = doc.split("<w:body>").nth(1).unwrap_or(&doc);
    let mut paras = Vec::new();
    for p in body.split("<w:p>").flat_map(|c| c.split("<w:p ")).skip(1) {
        let p = p.split("</w:p>").next().unwrap_or(p);
        let style = p
            .find("<w:pStyle ")
            .and_then(|i| attr(&p[i..i + p[i..].find('>').unwrap_or(0)], "w:val"))
            .map(|id| {
                styles
                    .iter()
                    .find(|(sid, _)| sid == id)
                    .map(|(_, n)| n.clone())
                    .unwrap_or_else(|| id.to_lowercase())
            })
            .unwrap_or_default();
        // Runs: text with italic / bold, merged where the formatting is the same.
        let mut runs: Vec<(String, bool, bool)> = Vec::new();
        for r in p.split("<w:r>").flat_map(|c| c.split("<w:r ")).skip(1) {
            let r = r.split("</w:r>").next().unwrap_or(r);
            let props = r
                .split("</w:rPr>")
                .next()
                .filter(|_| r.contains("</w:rPr>"))
                .unwrap_or("");
            let tag_on = |name: &str| {
                props
                    .find(&format!("<{name}/>"))
                    .map(|_| true)
                    .or_else(|| {
                        props
                            .find(&format!("<{name} "))
                            .map(|i| on(&props[i..i + props[i..].find('>').unwrap_or(0)]))
                    })
                    .unwrap_or(false)
            };
            let (italic, bold) = (tag_on("w:i"), tag_on("w:b"));
            let mut text = String::new();
            let mut rest = r;
            while let Some(i) = rest.find('<') {
                let end = rest[i..].find('>').map_or(rest.len(), |e| i + e + 1);
                let tag = &rest[i..end];
                if tag.starts_with("<w:t>") || tag.starts_with("<w:t ") {
                    let close = rest[end..].find("</w:t>").map_or(rest.len(), |c| end + c);
                    text.push_str(&unescape(&rest[end..close]));
                    rest = &rest[close..];
                    continue;
                } else if tag.starts_with("<w:tab")
                    || tag.starts_with("<w:br")
                    || tag.starts_with("<w:cr")
                {
                    text.push(' ');
                } else if tag.starts_with("<w:noBreakHyphen") {
                    text.push('-');
                }
                rest = &rest[end..];
            }
            if text.is_empty() {
                continue;
            }
            match runs.last_mut() {
                Some(last) if last.1 == italic && last.2 == bold => last.0.push_str(&text),
                _ => runs.push((text, italic, bold)),
            }
        }
        let mut md = String::new();
        for (text, italic, bold) in &runs {
            let mark = match (*italic, *bold) {
                (true, true) => "***",
                (false, true) => "**",
                (true, false) => "*",
                _ => "",
            };
            let core = text.trim();
            if mark.is_empty() || core.is_empty() {
                md.push_str(text);
                continue;
            }
            // Keep spaces outside the markers: "*word* ", not "*word *".
            let lead = &text[..text.len() - text.trim_start().len()];
            let trail = &text[text.trim_end().len()..];
            md.push_str(&format!("{lead}{mark}{core}{mark}{trail}"));
        }
        let md = md.split_whitespace().collect::<Vec<_>>().join(" ");
        if md.is_empty() {
            continue;
        }
        let level = style
            .strip_prefix("heading ")
            .and_then(|n| n.trim().parse::<usize>().ok());
        let plain: String = md.chars().filter(|c| *c != '*').collect();
        paras.push(match (style.as_str(), level) {
            ("title", _) => Para::Title(plain),
            (_, Some(l)) => Para::Heading(l, plain),
            _ => classify(md),
        });
    }
    Ok(paras)
}

// ---------------------------------------------------------------- structure

pub fn build(paras: Vec<Para>) -> Book {
    let mut book = Book::default();
    let mut chapter: Option<Chapter> = None;
    let mut scene = Scene::default();
    let flush_scene = |scene: &mut Scene, chapter: &mut Option<Chapter>| {
        if scene.paras.is_empty() && scene.title.is_none() {
            return;
        }
        chapter
            .get_or_insert_with(|| Chapter {
                title: "Front Matter".into(),
                scenes: Vec::new(),
            })
            .scenes
            .push(std::mem::take(scene));
    };
    for p in paras {
        match p {
            Para::Title(t) => {
                if book.title.is_none() && book.chapters.is_empty() && chapter.is_none() {
                    book.title = Some(t);
                } else {
                    scene.paras.push(t);
                }
            }
            Para::Heading(1, t) => {
                flush_scene(&mut scene, &mut chapter);
                if let Some(c) = chapter.take() {
                    book.chapters.push(c);
                }
                chapter = Some(Chapter {
                    title: t,
                    scenes: Vec::new(),
                });
            }
            Para::Heading(_, t) => {
                flush_scene(&mut scene, &mut chapter);
                scene.title = Some(t);
            }
            Para::Break => flush_scene(&mut scene, &mut chapter),
            Para::Text(t) => scene.paras.push(t),
        }
    }
    flush_scene(&mut scene, &mut chapter);
    if let Some(c) = chapter.take() {
        book.chapters.push(c);
    }
    // A book with no chapter headings at all: one chapter of scenes.
    if book.chapters.len() == 1 && book.chapters[0].title == "Front Matter" {
        book.chapters[0].title = book.title.clone().unwrap_or_else(|| "Chapter 1".into());
    }
    book
}

#[cfg(test)]
mod tests {
    use super::*;

    fn titles(b: &Book) -> Vec<(String, usize)> {
        b.chapters
            .iter()
            .map(|c| (c.title.clone(), c.scenes.len()))
            .collect()
    }

    #[test]
    fn chapter_lines() {
        for yes in [
            "Chapter 1",
            "CHAPTER TWELVE",
            "Chapter Twenty-One: Home",
            "Prologue",
            "PART II",
            "12",
            "Epilogue — After",
        ] {
            assert!(is_chapter_line(yes), "{yes}");
        }
        for no in [
            "Chapter and verse were quoted.",
            "Chapters",
            "The chapter ended.",
            "Partly cloudy",
            "1999 was a year.",
        ] {
            assert!(!is_chapter_line(no), "{no}");
        }
    }

    #[test]
    fn markdown_with_headings_and_breaks() {
        let md = "% The Book\n% A. Writer\n\n# One\n\nFirst *scene*.\n\nStill first.\n\n* * *\n\nSecond.\n\n## A Titled Scene\n\nThird.\n\n# Two\n\nFourth.";
        let b = build(text_paras(md));
        assert_eq!(b.title.as_deref(), Some("The Book"));
        assert_eq!(titles(&b), vec![("One".into(), 3), ("Two".into(), 1)]);
        assert_eq!(
            b.chapters[0].scenes[0].paras,
            vec!["First *scene*.", "Still first."]
        );
        assert_eq!(
            b.chapters[0].scenes[2].title.as_deref(),
            Some("A Titled Scene")
        );
    }

    #[test]
    fn plain_text_one_paragraph_per_line() {
        let txt = "Opening words.\nCHAPTER ONE\nShe woke.\nIt was late.\n#\nLater.\nChapter 2\nThe end.\n";
        let b = build(text_paras(txt));
        assert_eq!(
            titles(&b),
            vec![
                ("Front Matter".into(), 1),
                ("CHAPTER ONE".into(), 2),
                ("Chapter 2".into(), 1)
            ]
        );
        assert_eq!(
            b.chapters[1].scenes[0].paras,
            vec!["She woke.", "It was late."]
        );
    }

    #[test]
    fn no_chapters_means_one_chapter() {
        let b = build(text_paras("A.\n\nB.\n\n***\n\nC."));
        assert_eq!(titles(&b), vec![("Chapter 1".into(), 2)]);
    }

    #[test]
    fn reads_a_docx() {
        // Our own DOCX export, read back: chapters, a scene break, italics.
        let mut p = crate::model::Project::new("Round Trip", "A. Writer");
        let ms = p.root(crate::model::RootRole::Manuscript);
        let ch = p.nodes[&ms].children[0];
        let s1 = p.nodes[&ch].children[0];
        p.set_text(s1, "She *ran* & **hid**.\n\nThen \"waited\".".into())
            .unwrap();
        let s2 = p
            .add_node(ch, None, crate::model::NodeKind::Text, "S2")
            .unwrap();
        p.set_text(s2, "Later.".into()).unwrap();
        let opts = crate::compile::CompileOptions {
            format: crate::compile::Format::Docx,
            ..Default::default()
        };
        let bytes = crate::compile::compile_file(&p, &opts);
        let b = build(docx_paras(&bytes).unwrap());
        assert_eq!(b.title.as_deref(), Some("Round Trip"));
        let ch = b
            .chapters
            .iter()
            .find(|c| c.title == "Chapter 1")
            .expect("chapter");
        assert_eq!(ch.scenes.len(), 2);
        assert_eq!(
            ch.scenes[0].paras,
            vec!["She *ran* & **hid**.", "Then \"waited\"."]
        );
        assert_eq!(ch.scenes[1].paras, vec!["Later."]);
    }

    #[test]
    fn reads_a_compressed_word_file_with_translated_styles() {
        // Deflated like Word's own files, with German style ids.
        let data = include_bytes!("../tests/fixtures/word.docx");
        let b = build(docx_paras(data).unwrap());
        assert_eq!(b.title.as_deref(), Some("The Salt Road"));
        assert_eq!(
            titles(&b),
            vec![
                ("Front Matter".into(), 1),
                ("Chapter One".into(), 2),
                ("Chapter Two".into(), 1)
            ]
        );
        assert_eq!(
            b.chapters[1].scenes[0].paras,
            vec![
                "She *never* looked back & ***never*** would.",
                "Not italic here—“quoted”."
            ]
        );
        assert_eq!(b.chapters[2].scenes[0].paras, vec!["The **end**."]);
    }

    #[test]
    fn rejects_other_files() {
        assert!(docx_paras(b"not a zip").is_err());
        assert_eq!(unescape("a &amp; b &#8212; &#x2019;"), "a & b — ’");
    }
}
