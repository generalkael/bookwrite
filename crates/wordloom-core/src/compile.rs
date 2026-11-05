//! Compile the manuscript into a single output document.

use serde::{Deserialize, Serialize};

use crate::model::{NodeId, NodeKind, Project, RootRole};

#[derive(Serialize, Deserialize, Clone, Copy, PartialEq, Eq, Debug, Default)]
#[serde(rename_all = "snake_case")]
pub enum Format {
    #[default]
    Markdown,
    Html,
    PlainText,
    Epub,
    Docx,
}

impl Format {
    pub fn extension(self) -> &'static str {
        match self {
            Self::Markdown => "md",
            Self::Html => "html",
            Self::PlainText => "txt",
            Self::Epub => "epub",
            Self::Docx => "docx",
        }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default)]
pub struct CompileOptions {
    pub format: Format,
    pub title_page: bool,
    /// Emit folder titles as headings (chapter / part titles).
    pub folder_titles: bool,
    /// Emit document titles as headings (scene titles).
    pub document_titles: bool,
    /// Inserted between consecutive documents in the same folder.
    pub scene_separator: String,
    /// Only compile this subtree instead of the whole manuscript.
    pub root: Option<NodeId>,
    /// Number top-level folders as "Chapter N" when they have no title.
    pub number_chapters: bool,
}

impl Default for CompileOptions {
    fn default() -> Self {
        Self {
            format: Format::Markdown,
            title_page: true,
            folder_titles: true,
            document_titles: false,
            scene_separator: "* * *".into(),
            root: None,
            number_chapters: false,
        }
    }
}

/// One unit of compiled output, before it is rendered to a format.
pub(crate) enum Piece<'a> {
    Heading(usize, String),
    Body(&'a str),
    Separator,
}

/// Compile to text. EPUB and DOCX return an HTML preview of their content;
/// use [`compile_file`] for the file itself.
pub fn compile(p: &Project, opts: &CompileOptions) -> String {
    let pieces = pieces(p, opts);
    match opts.format {
        Format::Markdown => render_markdown(p, opts, &pieces),
        Format::PlainText => render_plain(p, opts, &pieces),
        Format::Html | Format::Epub | Format::Docx => render_html(p, opts, &pieces),
    }
}

/// The bytes of the exported file in the chosen format.
pub fn compile_file(p: &Project, opts: &CompileOptions) -> Vec<u8> {
    match opts.format {
        Format::Epub => crate::epub::build(p, opts, &pieces(p, opts)),
        Format::Docx => crate::docx::build(p, opts, &pieces(p, opts)),
        _ => compile(p, opts).into_bytes(),
    }
}

/// The manuscript (or `opts.root`) flattened into headings, bodies and
/// separators, honouring "include in compile".
pub(crate) fn pieces<'a>(p: &'a Project, opts: &CompileOptions) -> Vec<Piece<'a>> {
    let root = opts.root.unwrap_or_else(|| p.root(RootRole::Manuscript));
    let mut pieces = Vec::new();
    let mut chapter = 0;
    if let Some(n) = p.nodes.get(&root) {
        for c in &n.children {
            collect(p, *c, 1, opts, &mut pieces, &mut chapter);
        }
    }
    pieces
}

fn collect<'a>(
    p: &'a Project,
    id: NodeId,
    depth: usize,
    opts: &CompileOptions,
    out: &mut Vec<Piece<'a>>,
    chapter: &mut usize,
) {
    let n = &p.nodes[&id];
    if !n.include_in_compile {
        return;
    }
    let is_folder = n.kind == NodeKind::Folder;
    if is_folder && depth == 1 {
        *chapter += 1;
    }
    let want_title = if is_folder {
        opts.folder_titles
    } else {
        opts.document_titles
    };
    if want_title {
        let title = if is_folder && depth == 1 && opts.number_chapters {
            if n.title.trim().is_empty() {
                format!("Chapter {chapter}")
            } else {
                format!("Chapter {chapter}: {}", n.title)
            }
        } else {
            n.title.clone()
        };
        out.push(Piece::Heading(depth.min(6), title));
    } else if !is_folder && matches!(out.last(), Some(Piece::Body(_))) {
        out.push(Piece::Separator);
    }
    let text = p.text(id).trim();
    if !text.is_empty() {
        out.push(Piece::Body(text));
    }
    for c in &n.children {
        collect(p, *c, depth + 1, opts, out, chapter);
    }
}

fn render_markdown(p: &Project, opts: &CompileOptions, pieces: &[Piece]) -> String {
    let mut s = String::new();
    if opts.title_page {
        s.push_str(&format!("% {}\n% {}\n\n", p.meta.title, p.meta.author));
    }
    for piece in pieces {
        match piece {
            Piece::Heading(d, t) => s.push_str(&format!("{} {}\n\n", "#".repeat(*d), t)),
            Piece::Body(b) => {
                s.push_str(b);
                s.push_str("\n\n");
            }
            Piece::Separator => s.push_str(&format!("{}\n\n", opts.scene_separator)),
        }
    }
    s.trim_end().to_string() + "\n"
}

fn render_plain(p: &Project, opts: &CompileOptions, pieces: &[Piece]) -> String {
    let mut s = String::new();
    if opts.title_page {
        s.push_str(&format!(
            "{}\nby {}\n\n\n",
            p.meta.title.to_uppercase(),
            p.meta.author
        ));
    }
    for piece in pieces {
        match piece {
            Piece::Heading(d, t) => {
                if *d == 1 {
                    s.push_str(&format!("\n{}\n\n", t.to_uppercase()));
                } else {
                    s.push_str(&format!("{t}\n\n"));
                }
            }
            Piece::Body(b) => {
                s.push_str(&strip_markdown(b));
                s.push_str("\n\n");
            }
            Piece::Separator => s.push_str(&format!("{:^60}\n\n", opts.scene_separator)),
        }
    }
    s.trim_end().to_string() + "\n"
}

fn render_html(p: &Project, opts: &CompileOptions, pieces: &[Piece]) -> String {
    let mut body = String::new();
    if opts.title_page {
        body.push_str(&format!(
            "<section class=\"title-page\"><h1 class=\"title\">{}</h1><p class=\"author\">{}</p></section>\n",
            esc(&p.meta.title),
            esc(&p.meta.author)
        ));
    }
    for piece in pieces {
        body.push_str(&piece_html(piece, opts));
    }
    format!(
        "<!doctype html>\n<html><head><meta charset=\"utf-8\"><title>{}</title>\n<style>\n\
         body{{max-width:38em;margin:3em auto;font:1.1em/1.6 Georgia,serif;padding:0 1em}}\n\
         p{{margin:0;text-indent:1.5em}} h2+p,h3+p,.sep+p{{text-indent:0}}\n\
         .sep{{text-align:center;margin:1em 0;text-indent:0}}\n\
         .title-page{{text-align:center;margin:30vh 0;page-break-after:always}}\n\
         h2{{page-break-before:always;text-align:center;margin-top:3em}}\n\
         blockquote{{margin:1em 2em;font-style:italic}}\n\
         </style></head><body>\n{}</body></html>\n",
        esc(&p.meta.title),
        body
    )
}

/// One piece as HTML (also valid XHTML). Headings start at `<h2>`; `<h1>`
/// is the book title.
pub(crate) fn piece_html(piece: &Piece, opts: &CompileOptions) -> String {
    match piece {
        Piece::Heading(d, t) => {
            let d = (d + 1).min(6);
            format!("<h{d}>{}</h{d}>\n", esc(t))
        }
        Piece::Body(b) => markdown_to_html(b),
        Piece::Separator => format!("<p class=\"sep\">{}</p>\n", esc(&opts.scene_separator)),
    }
}

/// Escape for HTML and XML. Control characters (other than tab and
/// newlines) are dropped: XML forbids them.
pub(crate) fn esc(s: &str) -> String {
    s.replace(
        |c: char| c.is_control() && !matches!(c, '\t' | '\n' | '\r'),
        "",
    )
    .replace('&', "&amp;")
    .replace('<', "&lt;")
    .replace('>', "&gt;")
    .replace('"', "&quot;")
}

/// A run of text with the same emphasis.
#[derive(Debug, PartialEq)]
pub(crate) struct Span {
    pub text: String,
    pub bold: bool,
    pub italic: bool,
}

/// Inline emphasis: `***x***`, `**x**`, `*x*`, `_x_`. Unclosed markers run
/// to the end of the paragraph; underscores inside words are literal.
pub(crate) fn spans(s: &str) -> Vec<Span> {
    let chars: Vec<char> = s.chars().collect();
    let mut out: Vec<Span> = Vec::new();
    // Open markers, innermost last: 1 = italic, 2 = bold, 3 = both.
    let mut open: Vec<usize> = Vec::new();
    let mut text = String::new();
    let flush = |text: &mut String, open: &[usize], out: &mut Vec<Span>| {
        if !text.is_empty() {
            out.push(Span {
                text: std::mem::take(text),
                bold: open.iter().any(|r| *r >= 2),
                italic: open.iter().any(|r| *r != 2),
            });
        }
    };
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c == '*' || c == '_' {
            let run = chars[i..].iter().take_while(|x| **x == c).count().min(3);
            let inside_word = c == '_'
                && i > 0
                && chars[i - 1].is_alphanumeric()
                && chars.get(i + run).is_some_and(|n| n.is_alphanumeric());
            if inside_word {
                text.push(c);
                i += 1;
                continue;
            }
            flush(&mut text, &open, &mut out);
            if open.last() == Some(&run) {
                open.pop();
            } else {
                open.push(run);
            }
            i += run;
        } else {
            text.push(c);
            i += 1;
        }
    }
    flush(&mut text, &open, &mut out);
    out
}

fn inline_html(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for sp in spans(s) {
        match (sp.bold, sp.italic) {
            (true, true) => out.push_str(&format!("<strong><em>{}</em></strong>", esc(&sp.text))),
            (true, false) => out.push_str(&format!("<strong>{}</strong>", esc(&sp.text))),
            (false, true) => out.push_str(&format!("<em>{}</em>", esc(&sp.text))),
            (false, false) => out.push_str(&esc(&sp.text)),
        }
    }
    out
}

/// A block of a document body: the small Markdown subset suited to prose.
pub(crate) enum Block<'a> {
    /// `#` level (1 = `#`) and text.
    Heading(usize, &'a str),
    /// A horizontal rule (`***`, `---`), shown as a scene break.
    Rule,
    Quote(String),
    Para(String),
}

pub(crate) fn blocks(md: &str) -> Vec<Block<'_>> {
    let mut out = Vec::new();
    for block in md.split("\n\n").map(str::trim).filter(|b| !b.is_empty()) {
        if let Some(rest) = block.strip_prefix('#') {
            let level = 1 + rest.chars().take_while(|c| *c == '#').count();
            out.push(Block::Heading(level, rest.trim_start_matches('#').trim()));
        } else if block.chars().all(|c| matches!(c, '*' | '-' | '_' | ' ')) && block.len() >= 3 {
            out.push(Block::Rule);
        } else if block.starts_with('>') {
            let inner: Vec<&str> = block
                .lines()
                .map(|l| l.trim_start_matches('>').trim())
                .collect();
            out.push(Block::Quote(inner.join(" ")));
        } else {
            let joined: Vec<&str> = block.lines().map(str::trim).collect();
            out.push(Block::Para(joined.join(" ")));
        }
    }
    out
}

/// Paragraphs, headings, blockquotes, horizontal rules and emphasis.
pub fn markdown_to_html(md: &str) -> String {
    let mut out = String::new();
    for b in blocks(md) {
        match b {
            Block::Heading(level, text) => {
                let l = (level + 1).min(6);
                out.push_str(&format!("<h{l}>{}</h{l}>\n", inline_html(text)));
            }
            Block::Rule => out.push_str("<p class=\"sep\">* * *</p>\n"),
            Block::Quote(t) => out.push_str(&format!(
                "<blockquote><p>{}</p></blockquote>\n",
                inline_html(&t)
            )),
            Block::Para(t) => out.push_str(&format!("<p>{}</p>\n", inline_html(&t))),
        }
    }
    out
}

pub fn strip_markdown(md: &str) -> String {
    md.lines()
        .map(|l| {
            let l = l.trim_start_matches('#').trim_start_matches('>');
            l.replace("**", "").replace('*', "")
        })
        .collect::<Vec<_>>()
        .join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Project {
        let mut p = Project::new("Book", "Author");
        let ms = p.root(RootRole::Manuscript);
        let ch = p.nodes[&ms].children[0];
        let s1 = p.nodes[&ch].children[0];
        p.set_text(s1, "Hello *world*.".into()).unwrap();
        let s2 = p.add_node(ch, None, NodeKind::Text, "Scene 2").unwrap();
        p.set_text(s2, "Second **scene**.".into()).unwrap();
        let s3 = p.add_node(ch, None, NodeKind::Text, "Cut").unwrap();
        p.set_text(s3, "Excluded".into()).unwrap();
        p.node_mut(s3).unwrap().include_in_compile = false;
        p
    }

    #[test]
    fn markdown_output() {
        let p = sample();
        let out = compile(&p, &CompileOptions::default());
        assert_eq!(
            out,
            "% Book\n% Author\n\n# Chapter 1\n\nHello *world*.\n\n* * *\n\nSecond **scene**.\n"
        );
    }

    #[test]
    fn html_and_plain() {
        let p = sample();
        let html = compile(
            &p,
            &CompileOptions {
                format: Format::Html,
                ..Default::default()
            },
        );
        assert!(html.contains("<p>Hello <em>world</em>.</p>"));
        assert!(html.contains("<strong>scene</strong>"));
        assert!(!html.contains("Excluded"));
        let txt = compile(
            &p,
            &CompileOptions {
                format: Format::PlainText,
                number_chapters: true,
                ..Default::default()
            },
        );
        assert!(txt.contains("CHAPTER 1: CHAPTER 1"));
        assert!(txt.contains("Second scene."));
    }

    #[test]
    fn inline_rules() {
        assert_eq!(inline_html("snake_case_name"), "snake_case_name");
        assert_eq!(inline_html("***both***"), "<strong><em>both</em></strong>");
        assert_eq!(inline_html("a < b"), "a &lt; b");
    }
}
