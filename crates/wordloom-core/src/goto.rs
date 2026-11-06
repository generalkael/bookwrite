//! "Go to…": find any binder item by a few letters of its title.
//!
//! Matches rank: the title starts with the query, then a word in it does,
//! then the query appears anywhere, then its letters appear in order
//! ("lhk" finds "Lighthouse Keeper"). Ties keep binder order. With no query
//! the most recently modified items are offered.

use serde::Serialize;

use crate::model::{NodeId, NodeKind, Project, RootRole};

#[derive(Serialize, Debug)]
pub struct Hit {
    pub id: NodeId,
    pub title: String,
    pub kind: NodeKind,
    pub role: Option<RootRole>,
    /// Where it is: "Manuscript › The Log".
    pub path: String,
    pub in_trash: bool,
}

/// How well `title` matches `q` (both lower case); lower is better.
fn rank(title: &str, q: &str) -> Option<u32> {
    if title.starts_with(q) {
        return Some(0);
    }
    if title.match_indices(q).any(|(i, _)| {
        title[..i]
            .chars()
            .next_back()
            .is_some_and(|c| !c.is_alphanumeric())
    }) {
        return Some(1);
    }
    if title.contains(q) {
        return Some(2);
    }
    // Letters in order, ignoring spaces in the query.
    let mut it = title.chars();
    let all = q
        .chars()
        .filter(|c| !c.is_whitespace())
        .all(|c| it.any(|t| t == c));
    all.then_some(3)
}

pub fn go_to(p: &Project, query: &str, limit: usize) -> Vec<Hit> {
    let q = query.trim().to_lowercase();
    let mut order: Vec<NodeId> = Vec::new();
    for r in &p.roots {
        order.extend(p.subtree(*r));
    }
    let trash = p.root(RootRole::Trash);
    let mut scored: Vec<(u32, usize, NodeId)> = Vec::new();
    for (pos, id) in order.iter().enumerate() {
        let n = &p.nodes[id];
        let in_trash = *id != trash && p.ancestors(*id).contains(&trash);
        let score = if q.is_empty() {
            Some(0)
        } else {
            rank(&n.title.to_lowercase(), &q)
        };
        if let Some(s) = score {
            // Trashed items only after everything else.
            scored.push((s + if in_trash { 10 } else { 0 }, pos, *id));
        }
    }
    if q.is_empty() {
        // Recent work: documents and folders, newest change first.
        scored.retain(|(_, _, id)| !p.is_root(*id) && p.nodes[id].parent.is_some());
        scored.sort_by_key(|(s, _, id)| (*s, std::cmp::Reverse(p.nodes[id].modified)));
    } else {
        scored.sort();
    }
    scored
        .into_iter()
        .take(limit)
        .map(|(_, _, id)| {
            let n = &p.nodes[&id];
            let mut crumbs: Vec<&str> = p
                .ancestors(id)
                .iter()
                .map(|a| p.nodes[a].title.as_str())
                .collect();
            crumbs.reverse();
            Hit {
                id,
                title: n.title.clone(),
                kind: n.kind,
                role: n.role,
                path: crumbs.join(" › "),
                in_trash: id != trash && p.ancestors(id).contains(&trash),
            }
        })
        .collect()
}

/// Expand every folder above `id`, so the binder shows it.
pub fn reveal(p: &mut Project, id: NodeId) {
    for a in p.ancestors(id) {
        if let Some(n) = p.nodes.get_mut(&a) {
            n.expanded = true;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ranking() {
        assert_eq!(rank("night watch", "night"), Some(0));
        assert_eq!(rank("night watch", "wat"), Some(1));
        assert_eq!(rank("the lighthouse", "house"), Some(2));
        assert_eq!(rank("lighthouse keeper", "lhk"), Some(3));
        assert_eq!(rank("lighthouse keeper", "lh kp"), Some(3));
        assert_eq!(rank("arrival", "xyz"), None);
    }

    #[test]
    fn finds_hidden_items_and_reveals_them() {
        let mut p = Project::new("B", "");
        let ms = p.root(RootRole::Manuscript);
        let ch = p.nodes[&ms].children[0];
        let s = p.add_node(ch, None, NodeKind::Text, "Night Watch").unwrap();
        let w = p.add_node(ms, None, NodeKind::Text, "Watchtower").unwrap();
        let gone = p.add_node(ms, None, NodeKind::Text, "Watch notes").unwrap();
        let trash = p.root(RootRole::Trash);
        p.move_node(gone, trash, 0).unwrap();
        p.node_mut(ch).unwrap().expanded = false;
        let hits = go_to(&p, "watch", 10);
        let ids: Vec<NodeId> = hits.iter().map(|h| h.id).collect();
        // Title start beats word start; the trashed one comes last.
        assert_eq!(ids, vec![w, s, gone]);
        assert_eq!(hits[1].path, "Manuscript › Chapter 1");
        assert!(hits[2].in_trash);
        reveal(&mut p, s);
        assert!(p.nodes[&ch].expanded);
        // No query: recent items, not section roots.
        assert!(go_to(&p, "", 10).iter().all(|h| !p.is_root(h.id)));
    }
}
