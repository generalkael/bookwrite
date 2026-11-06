//! The story bible: every character and place in one document, for an
//! editor, a co-writer or the next book in a series (File ▸ Export Story
//! Bible…). Each entry has its synopsis, custom fields, sheet text, notes,
//! relationships (characters) and the scenes it appears in. Items in the
//! Trash are left out; folders inside Characters or Places become
//! sub-headings.
//!
//! It is rendered with compile's own Markdown, HTML, plain-text and DOCX
//! writers, so it looks like the rest of Wordloom's exports.

use std::borrow::Cow;

use crate::compile::{CompileOptions, Format, Piece};
use crate::model::{NodeId, NodeKind, Project, RootRole};

/// The bible as compile pieces: a heading per section, entry and folder.
fn pieces(p: &Project) -> Vec<Piece<'static>> {
    let mut out = Vec::new();
    for (role, heading) in [
        (RootRole::Characters, "Characters"),
        (RootRole::Places, "Places"),
    ] {
        let root = p.root(role);
        let kids = &p.nodes[&root].children;
        if kids.is_empty() {
            continue;
        }
        out.push(Piece::Heading(1, heading.to_string()));
        for c in kids {
            entry(p, *c, 2, role, &mut out);
        }
    }
    out
}

fn entry(p: &Project, id: NodeId, depth: usize, role: RootRole, out: &mut Vec<Piece<'static>>) {
    let n = &p.nodes[&id];
    let title = if n.title.trim().is_empty() {
        "Untitled".to_string()
    } else {
        n.title.clone()
    };
    out.push(Piece::Heading(depth.min(6), title));
    let mut body: Vec<String> = Vec::new();
    if !n.synopsis.trim().is_empty() {
        body.push(format!("*{}*", one_line(&n.synopsis)));
    }
    for (k, v) in &n.fields {
        if !v.trim().is_empty() {
            body.push(format!("**{}:** {}", one_line(k), one_line(v)));
        }
    }
    let text = crate::comments::strip(p.text(id));
    if !text.trim().is_empty() {
        body.push(text.trim().to_string());
    }
    if !n.notes.trim().is_empty() {
        body.push(format!("**Notes:** {}", n.notes.trim()));
    }
    if role == RootRole::Characters {
        let links: Vec<String> = p
            .relations
            .for_node(id)
            .filter_map(|r| {
                let other = if r.from == id { r.to } else { r.from };
                let name = &p.nodes.get(&other)?.title;
                if p.section_of(other).ok()? == RootRole::Trash {
                    return None;
                }
                let label = r.label.trim();
                let (from, to) = if r.from == id {
                    (&n.title, name)
                } else {
                    (name, &n.title)
                };
                Some(if label.is_empty() {
                    format!("{from} and {to}")
                } else {
                    format!("{from} *{label}* {to}")
                })
            })
            .collect();
        if !links.is_empty() {
            body.push(format!("**Relationships:** {}", links.join("; ")));
        }
    }
    if n.kind != NodeKind::Folder {
        let seen = crate::mentions::appearances(p, id);
        body.push(if seen.documents.is_empty() {
            "**Appears in:** not mentioned in the manuscript yet".to_string()
        } else {
            let list: Vec<String> = seen
                .documents
                .iter()
                .map(|d| format!("{} ({})", d.title, d.count))
                .collect();
            format!("**Appears in:** {}", list.join(", "))
        });
    }
    if !body.is_empty() {
        out.push(Piece::Body(Cow::Owned(body.join("\n\n"))));
    }
    for c in &n.children {
        entry(p, *c, depth + 1, role, out);
    }
}

/// Field values and synopses are shown on one line (a line break would
/// start a new paragraph in Markdown).
fn one_line(s: &str) -> String {
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// The story bible as a file in `format` (Markdown, HTML, plain text or
/// DOCX), with a title page reading “Title: Story Bible”.
pub fn build(p: &Project, format: Format) -> Vec<u8> {
    let mut titled = p.clone();
    titled.meta.title = format!("{}: Story Bible", p.meta.title);
    let opts = CompileOptions {
        format,
        title_page: true,
        ..Default::default()
    };
    crate::compile::render_file(&titled, &opts, &pieces(p))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::compile::Format;

    #[test]
    fn sample_bible_has_characters_places_and_appearances() {
        let tmp = tempfile::tempdir().unwrap();
        let s = crate::demo::create(tmp.path()).unwrap();
        let md = String::from_utf8(build(&s.project, Format::Markdown)).unwrap();
        assert!(
            md.starts_with("% The Lighthouse Keeper (Sample): Story Bible"),
            "{md}"
        );
        let chars = md.find("# Characters").unwrap();
        let places = md.find("# Places").unwrap();
        assert!(chars < places);
        assert!(md.contains("## Mara Quinn"));
        assert!(md.contains("## Skerry Light"));
        assert!(md.contains("**Appears in:** "));
        // Every character entry comes before Places.
        assert!(md.find("## Ilse Varga").unwrap() < places);
        let html = String::from_utf8(build(&s.project, Format::Html)).unwrap();
        assert!(
            html.contains("<h2>Characters</h2>") && html.contains("<strong>Appears in:</strong>")
        );
        let docx = build(&s.project, Format::Docx);
        assert_eq!(&docx[..2], b"PK");
    }

    #[test]
    fn fields_notes_relationships_and_trash() {
        let tmp = tempfile::tempdir().unwrap();
        let mut s = crate::session::Session::create(tmp.path(), "B", "").unwrap();
        let chars = s.root_id("characters").unwrap();
        let ann = s.add(&chars, "text", "Ann Lee", true).unwrap();
        let bo = s.add(&chars, "text", "Bo", true).unwrap();
        let gone = s.add(&chars, "text", "Gone Guy", true).unwrap();
        let ms = s.root_id("manuscript").unwrap();
        let scene = s.add(&ms, "text", "Opening", true).unwrap();
        s.set_text(&scene, "Ann Lee waved. Ann laughed.").unwrap();
        let p = &mut s.project;
        let id = |s: &str| uuid::Uuid::parse_str(s).unwrap();
        let (a, b, g) = (id(&ann), id(&bo), id(&gone));
        p.nodes
            .get_mut(&a)
            .unwrap()
            .fields
            .insert("Age".into(), "34\nish".into());
        p.nodes.get_mut(&a).unwrap().notes = "Hates boats.".into();
        p.relations.add(a, b, "sister of").unwrap();
        p.relations.add(a, g, "rival").unwrap();
        p.trash(g).unwrap();
        let md = String::from_utf8(build(p, Format::Markdown)).unwrap();
        assert!(md.contains("**Age:** 34 ish"), "{md}");
        assert!(md.contains("**Notes:** Hates boats."));
        assert!(
            md.contains("**Relationships:** Ann Lee *sister of* Bo\n"),
            "{md}"
        );
        assert!(
            md.contains("## Bo\n\n**Relationships:** Ann Lee *sister of* Bo"),
            "{md}"
        );
        assert!(md.contains("**Appears in:** Opening (2)"));
        assert!(!md.contains("Gone Guy"));
        assert!(!md.contains("# Places"), "an empty section is left out");
    }
}
