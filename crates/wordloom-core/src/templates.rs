//! Project templates: the shape a new project starts with (File ▸ New
//! Project…). Each one only adds folders, empty documents with guiding
//! synopses, and a few placeholder sheets; nothing is written in the text,
//! so word counts start at zero.

use crate::model::{NodeId, NodeKind, Project, RootRole};
use crate::Result;

/// (id, name, description) of every template, in the order offered.
pub const TEMPLATES: &[(&str, &str, &str)] = &[
    (
        "blank",
        "Blank",
        "One chapter with one scene. Build the rest as you go.",
    ),
    (
        "novel",
        "Novel",
        "Three acts of chapters and scenes with notes on what each act does, a protagonist and antagonist, a main setting, and a premise note.",
    ),
    (
        "short-story",
        "Short Story",
        "Five scenes from opening to resolution, with no chapters, and a protagonist.",
    ),
    (
        "nonfiction",
        "Non-fiction",
        "Front matter, chapters of sections, back matter, an outline note and a sources note in Research.",
    ),
];

/// Give a brand-new project (as made by [`Project::new`]) the shape of
/// template `id`. Unknown ids are an error.
pub fn apply(p: &mut Project, id: &str) -> Result<()> {
    if !TEMPLATES.iter().any(|t| t.0 == id) {
        return Err(crate::Error::Invalid(format!("unknown template {id}")));
    }
    if id == "blank" {
        return Ok(());
    }
    // Start from an empty Manuscript.
    let ms = p.root(RootRole::Manuscript);
    for c in std::mem::take(&mut p.node_mut(ms)?.children) {
        for d in p.subtree(c) {
            p.nodes.remove(&d);
            p.contents.remove(&d);
        }
    }
    match id {
        "novel" => novel(p, ms),
        "short-story" => short_story(p, ms),
        _ => nonfiction(p, ms),
    }
}

fn add(
    p: &mut Project,
    parent: NodeId,
    kind: NodeKind,
    title: &str,
    synopsis: &str,
) -> Result<NodeId> {
    let id = p.add_node(parent, None, kind, title)?;
    p.node_mut(id)?.synopsis = synopsis.to_string();
    Ok(id)
}

fn sheet(
    p: &mut Project,
    role: RootRole,
    kind: NodeKind,
    title: &str,
    fields: &[(&str, &str)],
) -> Result<()> {
    let root = p.root(role);
    let id = p.add_node(root, None, kind, title)?;
    for (k, v) in fields {
        p.node_mut(id)?.fields.insert(k.to_string(), v.to_string());
    }
    Ok(())
}

fn note(p: &mut Project, role: RootRole, kind: NodeKind, title: &str, text: &str) -> Result<()> {
    let root = p.root(role);
    let id = p.add_node(root, None, kind, title)?;
    p.set_text(id, text.to_string())?;
    Ok(())
}

fn novel(p: &mut Project, ms: NodeId) -> Result<()> {
    /// (title, synopsis) of a chapter.
    type Chapter<'a> = (&'a str, &'a str);
    let acts: [(&str, &str, &[Chapter]); 3] = [
        (
            "Act I",
            "Setup: the ordinary world, the inciting incident, and the decision that commits the protagonist.",
            &[
                ("Chapter 1", "Open in the protagonist's ordinary world, with a hint of what's wrong."),
                ("Chapter 2", "The inciting incident: something happens that can't be ignored."),
                ("Chapter 3", "The protagonist commits; there's no going back."),
            ],
        ),
        (
            "Act II",
            "Confrontation: rising stakes, a midpoint turn, and the lowest point.",
            &[
                ("Chapter 4", "New ground: allies, enemies, first attempts."),
                ("Chapter 5", "The midpoint: a revelation or reversal changes the goal."),
                ("Chapter 6", "Everything falls apart: the lowest point."),
            ],
        ),
        (
            "Act III",
            "Resolution: the climax, and the world after it.",
            &[
                ("Chapter 7", "The final confrontation."),
                ("Chapter 8", "The new normal: what has changed, and what it cost."),
            ],
        ),
    ];
    for (act, what, chapters) in acts {
        let a = add(p, ms, NodeKind::Folder, act, what)?;
        for (title, synopsis) in chapters {
            let c = add(p, a, NodeKind::Folder, title, synopsis)?;
            add(p, c, NodeKind::Text, "Scene 1", "")?;
        }
    }
    sheet(
        p,
        RootRole::Characters,
        NodeKind::Character,
        "Protagonist",
        &[("Role", "Protagonist")],
    )?;
    sheet(
        p,
        RootRole::Characters,
        NodeKind::Character,
        "Antagonist",
        &[("Role", "Antagonist")],
    )?;
    sheet(
        p,
        RootRole::Places,
        NodeKind::Place,
        "Main Setting",
        &[("Significance", "Where most of the story happens")],
    )?;
    note(
        p,
        RootRole::Notes,
        NodeKind::Note,
        "Premise",
        "Who wants what, what stands in the way, and what happens if they fail?\n\nThe ending, if you know it:",
    )
}

fn short_story(p: &mut Project, ms: NodeId) -> Result<()> {
    for (title, synopsis) in [
        ("Opening", "Who, where, and what's off-balance."),
        (
            "Complication",
            "The problem grows; the first attempt fails.",
        ),
        ("Turn", "A discovery or choice changes everything."),
        ("Climax", "The decisive moment."),
        ("Resolution", "The last image: what has changed."),
    ] {
        add(p, ms, NodeKind::Text, title, synopsis)?;
    }
    sheet(
        p,
        RootRole::Characters,
        NodeKind::Character,
        "Protagonist",
        &[("Role", "Protagonist")],
    )
}

fn nonfiction(p: &mut Project, ms: NodeId) -> Result<()> {
    let front = add(p, ms, NodeKind::Folder, "Front Matter", "")?;
    add(
        p,
        front,
        NodeKind::Text,
        "Introduction",
        "Why this book, who it's for, and what the reader will get from it.",
    )?;
    for (n, synopsis) in [
        (1, "The first big idea."),
        (2, "The second big idea."),
        (3, "The third big idea."),
    ] {
        let c = add(p, ms, NodeKind::Folder, &format!("Chapter {n}"), synopsis)?;
        add(p, c, NodeKind::Text, "Section 1", "")?;
        add(p, c, NodeKind::Text, "Section 2", "")?;
    }
    let back = add(p, ms, NodeKind::Folder, "Back Matter", "")?;
    add(
        p,
        back,
        NodeKind::Text,
        "Conclusion",
        "What it all adds up to.",
    )?;
    add(p, back, NodeKind::Text, "Acknowledgements", "")?;
    note(
        p,
        RootRole::Notes,
        NodeKind::Note,
        "Outline",
        "The book's argument in one sentence:\n\nChapter by chapter:",
    )?;
    note(
        p,
        RootRole::Research,
        NodeKind::Research,
        "Sources",
        "Books, articles and interviews to cite. Footnotes: Edit ▸ Insert Footnote (Ctrl+Alt+F).",
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn titles(p: &Project, id: NodeId) -> Vec<String> {
        p.nodes[&id]
            .children
            .iter()
            .map(|c| p.nodes[c].title.clone())
            .collect()
    }

    #[test]
    fn every_template_builds() {
        for (id, _, _) in TEMPLATES {
            let mut p = Project::new("T", "");
            apply(&mut p, id).unwrap();
            let ms = p.root(RootRole::Manuscript);
            assert!(!p.nodes[&ms].children.is_empty(), "{id}");
            assert_eq!(p.total_words(ms), 0, "{id} starts at zero words");
            // No orphans left behind by clearing the default chapter.
            for (nid, n) in &p.nodes {
                if let Some(parent) = n.parent {
                    assert!(p.nodes[&parent].children.contains(nid), "{id}");
                }
            }
        }
    }

    #[test]
    fn shapes() {
        let mut p = Project::new("N", "");
        apply(&mut p, "novel").unwrap();
        let ms = p.root(RootRole::Manuscript);
        assert_eq!(titles(&p, ms), ["Act I", "Act II", "Act III"]);
        let act1 = p.nodes[&ms].children[0];
        assert_eq!(titles(&p, act1), ["Chapter 1", "Chapter 2", "Chapter 3"]);
        assert_eq!(
            titles(&p, p.root(RootRole::Characters)),
            ["Protagonist", "Antagonist"]
        );

        let mut p = Project::new("S", "");
        apply(&mut p, "short-story").unwrap();
        let ms = p.root(RootRole::Manuscript);
        assert_eq!(titles(&p, ms).len(), 5);
        assert!(p.nodes[&ms]
            .children
            .iter()
            .all(|c| p.nodes[c].kind == NodeKind::Text));

        let mut p = Project::new("B", "");
        apply(&mut p, "blank").unwrap();
        assert_eq!(titles(&p, p.root(RootRole::Manuscript)), ["Chapter 1"]);
        assert!(apply(&mut Project::new("X", ""), "sonnet").is_err());
    }
}
