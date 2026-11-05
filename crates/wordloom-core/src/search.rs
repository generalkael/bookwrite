//! Project-wide search across titles, text, synopses, notes and keywords.

use serde::Serialize;

use crate::model::{NodeId, Project, RootRole};

#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct Hit {
    pub id: NodeId,
    pub title: String,
    /// Where the match was found: title, text, synopsis, notes, keyword.
    pub field: &'static str,
    pub snippet: String,
    pub count: usize,
}

/// Case-insensitive search. Results come in binder order, one hit per
/// (item, field). Trashed items are skipped.
pub fn search(p: &Project, query: &str) -> Vec<Hit> {
    let q = query.trim().to_lowercase();
    if q.is_empty() {
        return Vec::new();
    }
    let mut out = Vec::new();
    for root in &p.roots {
        if p.nodes[root].role == Some(RootRole::Trash) {
            continue;
        }
        for id in p.subtree(*root) {
            let n = &p.nodes[&id];
            let fields: [(&'static str, &str); 4] = [
                ("title", &n.title),
                ("text", p.text(id)),
                ("synopsis", &n.synopsis),
                ("notes", &n.notes),
            ];
            for (field, value) in fields {
                let lower = value.to_lowercase();
                let count = lower.matches(&q).count();
                if count > 0 {
                    out.push(Hit {
                        id,
                        title: n.title.clone(),
                        field,
                        snippet: snippet(value, &lower, &q),
                        count,
                    });
                }
            }
            if n.keywords.iter().any(|k| k.to_lowercase().contains(&q)) {
                out.push(Hit {
                    id,
                    title: n.title.clone(),
                    field: "keyword",
                    snippet: n.keywords.join(", "),
                    count: 1,
                });
            }
        }
    }
    out
}

fn snippet(orig: &str, lower: &str, q: &str) -> String {
    // Work in chars so we never split a UTF-8 sequence. Lowercasing can change
    // lengths for a few scripts; fall back to the start if positions disagree.
    let Some(byte) = lower.find(q) else {
        return String::new();
    };
    let char_pos = lower[..byte].chars().count();
    let chars: Vec<char> = orig.chars().collect();
    let start = char_pos.saturating_sub(40);
    let end = (char_pos + q.chars().count() + 40).min(chars.len());
    let mut s: String = chars[start.min(chars.len())..end].iter().collect();
    s = s.replace('\n', " ");
    if start > 0 {
        s.insert(0, '…');
    }
    if end < chars.len() {
        s.push('…');
    }
    s
}

/// Replace every case-insensitive occurrence of `find` in document text.
/// Returns (documents changed, total replacements).
pub fn replace_all(p: &mut Project, find: &str, replace: &str) -> (usize, usize) {
    if find.is_empty() {
        return (0, 0);
    }
    let needle = find.to_lowercase();
    let ids: Vec<NodeId> = p.contents.keys().copied().collect();
    let (mut docs, mut total) = (0, 0);
    for id in ids {
        let text = p.text(id).to_string();
        let (new, n) = replace_ci(&text, &needle, replace);
        if n > 0 {
            docs += 1;
            total += n;
            let _ = p.set_text(id, new);
        }
    }
    (docs, total)
}

fn replace_ci(text: &str, needle_lower: &str, rep: &str) -> (String, usize) {
    let mut out = String::with_capacity(text.len());
    let mut n = 0;
    let mut rest = text;
    let nlen = needle_lower.chars().count();
    loop {
        let lower = rest.to_lowercase();
        let Some(pos) = lower.find(needle_lower) else {
            break;
        };
        // Map lowercase byte offset back to original via char count.
        let cpos = lower[..pos].chars().count();
        let start = rest
            .char_indices()
            .nth(cpos)
            .map(|(b, _)| b)
            .unwrap_or(rest.len());
        let end = rest[start..]
            .char_indices()
            .nth(nlen)
            .map(|(b, _)| start + b)
            .unwrap_or(rest.len());
        out.push_str(&rest[..start]);
        out.push_str(rep);
        rest = &rest[end..];
        n += 1;
    }
    out.push_str(rest);
    (out, n)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_and_replaces() {
        let mut p = Project::new("N", "");
        let ms = p.root(RootRole::Manuscript);
        let ch = p.nodes[&ms].children[0];
        let s = p.nodes[&ch].children[0];
        p.set_text(s, "The Dragon slept. A dragon woke.".into())
            .unwrap();
        p.node_mut(s).unwrap().keywords.push("dragons".into());
        let hits = search(&p, "dragon");
        assert_eq!(hits.len(), 2);
        assert_eq!(hits[0].field, "text");
        assert_eq!(hits[0].count, 2);
        assert_eq!(replace_all(&mut p, "DRAGON", "wyrm"), (1, 2));
        assert_eq!(p.text(s), "The wyrm slept. A wyrm woke.");
        p.trash(ch).unwrap();
        assert!(search(&p, "wyrm").is_empty());
    }
}
