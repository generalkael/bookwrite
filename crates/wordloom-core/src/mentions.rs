//! Where a character or place appears: the manuscript documents that
//! mention it by name.
//!
//! An item is known by its title, the first word of a multi-word title
//! ("Mara" for "Mara Quinn"), and anything listed in an *Also known as*
//! field (comma-separated). Matching is whole-word and case-sensitive, so
//! "Rose" the character isn't found in "rose from her chair" or "roses".
//! Text inside inline comments doesn't count.

use serde::Serialize;

use crate::model::{NodeId, NodeKind, Project, RootRole};

/// Field names (case-insensitive) that hold other names for an item.
const ALIAS_FIELDS: &[&str] = &["also known as", "aliases", "nicknames", "aka"];

/// The names `id` goes by, longest first.
pub fn names(p: &Project, id: NodeId) -> Vec<String> {
    let Some(n) = p.nodes.get(&id) else {
        return Vec::new();
    };
    let mut out: Vec<String> = Vec::new();
    let mut add = |s: &str| {
        let s = s.trim();
        if s.chars().count() >= 2 && !out.iter().any(|o| o == s) {
            out.push(s.to_string());
        }
    };
    add(&n.title);
    let words: Vec<&str> = n.title.split_whitespace().collect();
    // A first name, but not "The" of "The Keeper" or an initial.
    if words.len() > 1
        && words[0].chars().count() >= 3
        && words[0].chars().next().is_some_and(char::is_uppercase)
        && !matches!(
            words[0],
            "The" | "Old" | "Young" | "Mr." | "Mrs." | "Ms." | "Dr."
        )
    {
        add(words[0]);
    }
    for (k, v) in &n.fields {
        if ALIAS_FIELDS.contains(&k.to_lowercase().as_str()) {
            for alias in v.split(',') {
                add(alias);
            }
        }
    }
    out.sort_by_key(|s| std::cmp::Reverse(s.len()));
    out
}

/// How often each of `names` (longest first) occurs in `text`, as whole
/// words. A longer name wins where they overlap.
pub fn count(text: &str, names: &[String]) -> Vec<usize> {
    let mut counts = vec![0; names.len()];
    let bytes = text.as_bytes();
    let boundary_before = |i: usize| {
        i == 0
            || !text[..i]
                .chars()
                .next_back()
                .is_some_and(char::is_alphanumeric)
    };
    let boundary_after =
        |j: usize| j >= bytes.len() || !text[j..].chars().next().is_some_and(char::is_alphanumeric);
    let mut i = 0;
    while i < text.len() {
        if !text.is_char_boundary(i) {
            i += 1;
            continue;
        }
        let mut matched = None;
        if boundary_before(i) {
            for (k, name) in names.iter().enumerate() {
                if text[i..].starts_with(name.as_str()) && boundary_after(i + name.len()) {
                    matched = Some((k, name.len()));
                    break;
                }
            }
        }
        match matched {
            Some((k, len)) => {
                counts[k] += 1;
                i += len;
            }
            None => i += 1,
        }
    }
    counts
}

/// Every name a character or place goes by (outside the Trash), for name
/// completion in the editor: sorted, without duplicates.
pub fn all_names(p: &Project) -> Vec<String> {
    let trash = p.root(RootRole::Trash);
    let mut out: Vec<String> = p
        .nodes
        .values()
        .filter(|n| matches!(n.kind, NodeKind::Character | NodeKind::Place))
        .filter(|n| !p.ancestors(n.id).contains(&trash))
        .flat_map(|n| names(p, n.id))
        .collect();
    out.sort_by_key(|s| s.to_lowercase());
    out.dedup();
    out
}

#[derive(Serialize, Debug)]
pub struct Appearance {
    pub id: NodeId,
    pub title: String,
    pub count: usize,
    /// The name used most in this document (for finding it there).
    pub name: String,
}

#[derive(Serialize, Debug)]
pub struct Appearances {
    pub names: Vec<String>,
    /// Manuscript documents that mention the item, in manuscript order.
    pub documents: Vec<Appearance>,
    pub total: usize,
}

pub fn appearances(p: &Project, id: NodeId) -> Appearances {
    let names = names(p, id);
    let mut documents = Vec::new();
    let mut total = 0;
    if !names.is_empty() {
        for d in p.subtree(p.root(RootRole::Manuscript)) {
            if d == id || p.nodes[&d].kind == NodeKind::Folder && p.text(d).is_empty() {
                continue;
            }
            let text = crate::comments::strip(p.text(d));
            let counts = count(&text, &names);
            let sum: usize = counts.iter().sum();
            if sum == 0 {
                continue;
            }
            let best = (0..names.len())
                .max_by_key(|&k| (counts[k], std::cmp::Reverse(k)))
                .unwrap_or(0);
            total += sum;
            documents.push(Appearance {
                id: d,
                title: p.nodes[&d].title.clone(),
                count: sum,
                name: names[best].clone(),
            });
        }
    }
    Appearances {
        names,
        documents,
        total,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn strs(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn whole_words_longest_first() {
        let names = strs(&["Mara Quinn", "Mara"]);
        assert_eq!(
            count("Mara Quinn met Mara. Mara's lamp; Maralyn; SMara", &names),
            vec![1, 2]
        );
        assert_eq!(
            count("rose from her chair; Rose; roses", &strs(&["Rose"])),
            vec![1]
        );
        assert_eq!(count("Zoë and Zoëy, Zoë.", &strs(&["Zoë"])), vec![2]);
    }

    #[test]
    fn names_from_title_and_aliases() {
        let mut p = Project::new("B", "");
        let chars = p.root(RootRole::Characters);
        let m = p
            .add_node(chars, None, NodeKind::Character, "Mara Quinn")
            .unwrap();
        p.node_mut(m)
            .unwrap()
            .fields
            .insert("Also known as".into(), "the Keeper's girl, Mae".into());
        assert_eq!(
            names(&p, m),
            strs(&["the Keeper's girl", "Mara Quinn", "Mara", "Mae"])
        );
        let k = p
            .add_node(chars, None, NodeKind::Character, "The Keeper")
            .unwrap();
        assert_eq!(names(&p, k), strs(&["The Keeper"]));
    }

    #[test]
    fn all_names_for_completion() {
        let mut p = Project::new("B", "");
        let chars = p.root(RootRole::Characters);
        let m = p
            .add_node(chars, None, NodeKind::Character, "Mara Quinn")
            .unwrap();
        p.node_mut(m)
            .unwrap()
            .fields
            .insert("Also known as".into(), "Mae".into());
        p.add_node(
            p.root(RootRole::Places),
            None,
            NodeKind::Place,
            "Skerry Light",
        )
        .unwrap();
        let gone = p
            .add_node(chars, None, NodeKind::Character, "Zed Old")
            .unwrap();
        let trash = p.root(RootRole::Trash);
        p.move_node(gone, trash, 0).unwrap();
        assert_eq!(
            all_names(&p),
            strs(&["Mae", "Mara", "Mara Quinn", "Skerry", "Skerry Light"])
        );
    }

    #[test]
    fn appearances_in_manuscript_order() {
        let mut p = Project::new("B", "");
        let ms = p.root(RootRole::Manuscript);
        let ch = p.nodes[&ms].children[0];
        let s1 = p.nodes[&ch].children[0];
        p.set_text(s1, "Tobias waited. {>>Tobias? check<<}".into())
            .unwrap();
        let s2 = p.add_node(ch, None, NodeKind::Text, "Two").unwrap();
        p.set_text(s2, "Nobody here.".into()).unwrap();
        let s3 = p.add_node(ch, None, NodeKind::Text, "Three").unwrap();
        p.set_text(s3, "Tobias Wren and Tobias.".into()).unwrap();
        let t = p
            .add_node(
                p.root(RootRole::Characters),
                None,
                NodeKind::Character,
                "Tobias Wren",
            )
            .unwrap();
        let a = appearances(&p, t);
        assert_eq!(a.total, 3);
        assert_eq!(a.documents.len(), 2);
        assert_eq!((a.documents[0].id, a.documents[0].count), (s1, 1));
        assert_eq!(a.documents[0].name, "Tobias");
        assert_eq!(a.documents[1].title, "Three");
        assert_eq!(a.documents[1].count, 2);
    }
}
