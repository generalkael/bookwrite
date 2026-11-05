//! The binder: a tree of folders and documents, plus the metadata that hangs
//! off each item (synopsis, notes, label, status, keywords, targets).
//!
//! Nodes live in a flat arena keyed by id; tree shape is expressed by each
//! node's `parent` and ordered `children`. This keeps moves cheap and makes the
//! on-disk JSON stable and diff-friendly.

use std::collections::{BTreeMap, HashMap, HashSet};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::stats::WritingStats;
use crate::timeline::Timeline;
use crate::{Error, Result};

pub type NodeId = Uuid;

/// What kind of binder item this is. Every kind can hold text and children;
/// the kind drives icons, defaults and where the item is compiled.
#[derive(Serialize, Deserialize, Clone, Copy, PartialEq, Eq, Debug, Hash)]
#[serde(rename_all = "snake_case")]
pub enum NodeKind {
    Folder,
    Text,
    Character,
    Place,
    Research,
    Note,
}

impl NodeKind {
    pub fn parse(s: &str) -> Option<Self> {
        Some(match s {
            "folder" => Self::Folder,
            "text" => Self::Text,
            "character" => Self::Character,
            "place" => Self::Place,
            "research" => Self::Research,
            "note" => Self::Note,
            _ => return None,
        })
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Folder => "folder",
            Self::Text => "text",
            Self::Character => "character",
            Self::Place => "place",
            Self::Research => "research",
            Self::Note => "note",
        }
    }
}

/// The fixed top-level sections of every project. Roots cannot be moved,
/// renamed away or trashed.
#[derive(Serialize, Deserialize, Clone, Copy, PartialEq, Eq, Debug, Hash)]
#[serde(rename_all = "snake_case")]
pub enum RootRole {
    Manuscript,
    Characters,
    Places,
    Research,
    Notes,
    Trash,
}

impl RootRole {
    pub const ALL: [RootRole; 6] = [
        Self::Manuscript,
        Self::Characters,
        Self::Places,
        Self::Research,
        Self::Notes,
        Self::Trash,
    ];

    pub fn default_title(self) -> &'static str {
        match self {
            Self::Manuscript => "Manuscript",
            Self::Characters => "Characters",
            Self::Places => "Places",
            Self::Research => "Research",
            Self::Notes => "Notes",
            Self::Trash => "Trash",
        }
    }

    /// The kind given to new items created directly inside this root.
    pub fn child_kind(self) -> NodeKind {
        match self {
            Self::Manuscript | Self::Trash => NodeKind::Text,
            Self::Characters => NodeKind::Character,
            Self::Places => NodeKind::Place,
            Self::Research => NodeKind::Research,
            Self::Notes => NodeKind::Note,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Manuscript => "manuscript",
            Self::Characters => "characters",
            Self::Places => "places",
            Self::Research => "research",
            Self::Notes => "notes",
            Self::Trash => "trash",
        }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Node {
    pub id: NodeId,
    pub title: String,
    pub kind: NodeKind,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub role: Option<RootRole>,
    #[serde(default)]
    pub parent: Option<NodeId>,
    #[serde(default)]
    pub children: Vec<NodeId>,
    #[serde(default)]
    pub synopsis: String,
    #[serde(default)]
    pub notes: String,
    #[serde(default)]
    pub label: Option<Uuid>,
    #[serde(default)]
    pub status: Option<Uuid>,
    #[serde(default)]
    pub keywords: Vec<String>,
    #[serde(default = "yes")]
    pub include_in_compile: bool,
    #[serde(default)]
    pub target_words: Option<u32>,
    /// Free-form key/value metadata (e.g. a character's age or eye colour).
    #[serde(default)]
    pub fields: BTreeMap<String, String>,
    #[serde(default = "yes")]
    pub expanded: bool,
    /// An imported file (image, PDF, …) this item shows, as a name inside
    /// the bundle's `files/` directory.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub file: Option<String>,
    pub created: DateTime<Utc>,
    pub modified: DateTime<Utc>,
}

fn yes() -> bool {
    true
}

impl Node {
    fn new(title: impl Into<String>, kind: NodeKind, parent: Option<NodeId>) -> Self {
        let now = Utc::now();
        Self {
            id: Uuid::new_v4(),
            title: title.into(),
            kind,
            role: None,
            parent,
            children: Vec::new(),
            synopsis: String::new(),
            notes: String::new(),
            label: None,
            status: None,
            keywords: Vec::new(),
            include_in_compile: true,
            target_words: None,
            fields: BTreeMap::new(),
            expanded: true,
            file: None,
            created: now,
            modified: now,
        }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Label {
    pub id: Uuid,
    pub name: String,
    /// `#rrggbb`
    pub color: String,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Status {
    pub id: Uuid,
    pub name: String,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct ProjectMeta {
    pub title: String,
    #[serde(default)]
    pub author: String,
    pub created: DateTime<Utc>,
    pub modified: DateTime<Utc>,
}

/// A whole writing project, held in memory. Document bodies are kept in
/// `contents` and persisted as one Markdown file each by [`crate::storage`].
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Project {
    pub format_version: u32,
    pub meta: ProjectMeta,
    pub roots: Vec<NodeId>,
    pub nodes: BTreeMap<NodeId, Node>,
    #[serde(default)]
    pub labels: Vec<Label>,
    #[serde(default)]
    pub statuses: Vec<Status>,
    #[serde(default)]
    pub timeline: Timeline,
    /// Character relationships and their map layout.
    #[serde(default)]
    pub relations: crate::relations::Relations,
    #[serde(default)]
    pub stats: WritingStats,
    #[serde(skip)]
    pub contents: HashMap<NodeId, String>,
}

/// One visible row of the binder when the tree is flattened for display.
#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct FlatRow {
    pub id: NodeId,
    pub title: String,
    pub kind: NodeKind,
    pub role: Option<RootRole>,
    pub depth: usize,
    pub has_children: bool,
    pub expanded: bool,
    pub label_color: Option<String>,
}

pub const FORMAT_VERSION: u32 = 1;

impl Project {
    /// A fresh project with the standard sections, a starter chapter and
    /// scene, and a default set of labels and statuses.
    pub fn new(title: impl Into<String>, author: impl Into<String>) -> Self {
        let now = Utc::now();
        let mut p = Project {
            format_version: FORMAT_VERSION,
            meta: ProjectMeta {
                title: title.into(),
                author: author.into(),
                created: now,
                modified: now,
            },
            roots: Vec::new(),
            nodes: BTreeMap::new(),
            labels: Vec::new(),
            statuses: Vec::new(),
            timeline: Timeline::default(),
            relations: Default::default(),
            stats: WritingStats::default(),
            contents: HashMap::new(),
        };
        for role in RootRole::ALL {
            let kind = NodeKind::Folder;
            let mut n = Node::new(role.default_title(), kind, None);
            n.role = Some(role);
            n.expanded = role == RootRole::Manuscript;
            p.roots.push(n.id);
            p.nodes.insert(n.id, n);
        }
        let ms = p.root(RootRole::Manuscript);
        let ch = p
            .add_node(ms, None, NodeKind::Folder, "Chapter 1")
            .expect("manuscript root exists");
        p.add_node(ch, None, NodeKind::Text, "Scene 1")
            .expect("chapter exists");

        for (name, color) in [
            ("Concept", "#8e7cc3"),
            ("First Draft", "#e69138"),
            ("Revised", "#3d85c6"),
            ("Final", "#6aa84f"),
        ] {
            p.labels.push(Label {
                id: Uuid::new_v4(),
                name: name.into(),
                color: color.into(),
            });
        }
        for name in ["To Do", "In Progress", "First Draft", "Revised", "Done"] {
            p.statuses.push(Status {
                id: Uuid::new_v4(),
                name: name.into(),
            });
        }
        p
    }

    pub fn root(&self, role: RootRole) -> NodeId {
        *self
            .roots
            .iter()
            .find(|id| self.nodes[*id].role == Some(role))
            .expect("every project has all root sections")
    }

    pub fn node(&self, id: NodeId) -> Result<&Node> {
        self.nodes.get(&id).ok_or(Error::NoSuchNode(id))
    }

    pub fn node_mut(&mut self, id: NodeId) -> Result<&mut Node> {
        self.nodes.get_mut(&id).ok_or(Error::NoSuchNode(id))
    }

    pub fn text(&self, id: NodeId) -> &str {
        self.contents.get(&id).map(String::as_str).unwrap_or("")
    }

    /// Replace a document's text. Returns the change in word count so callers
    /// can feed writing-session statistics.
    pub fn set_text(&mut self, id: NodeId, text: String) -> Result<i64> {
        let before = crate::stats::count_words(self.text(id)) as i64;
        let after = crate::stats::count_words(&text) as i64;
        self.node_mut(id)?.modified = Utc::now();
        self.contents.insert(id, text);
        self.touch();
        Ok(after - before)
    }

    pub fn touch(&mut self) {
        self.meta.modified = Utc::now();
    }

    /// Which root section a node belongs to.
    pub fn section_of(&self, id: NodeId) -> Result<RootRole> {
        let mut cur = id;
        loop {
            let n = self.node(cur)?;
            match n.parent {
                Some(p) => cur = p,
                None => return n.role.ok_or(Error::Invalid("orphan node".into())),
            }
        }
    }

    pub fn is_root(&self, id: NodeId) -> bool {
        self.roots.contains(&id)
    }

    pub fn ancestors(&self, id: NodeId) -> Vec<NodeId> {
        let mut out = Vec::new();
        let mut cur = self.nodes.get(&id).and_then(|n| n.parent);
        while let Some(p) = cur {
            out.push(p);
            cur = self.nodes.get(&p).and_then(|n| n.parent);
        }
        out
    }

    /// Depth-first, pre-order list of `id` and everything under it.
    pub fn subtree(&self, id: NodeId) -> Vec<NodeId> {
        let mut out = Vec::new();
        let mut stack = vec![id];
        while let Some(cur) = stack.pop() {
            if let Some(n) = self.nodes.get(&cur) {
                out.push(cur);
                stack.extend(n.children.iter().rev());
            }
        }
        out
    }

    /// Create a node under `parent` at `index` (or at the end).
    pub fn add_node(
        &mut self,
        parent: NodeId,
        index: Option<usize>,
        kind: NodeKind,
        title: &str,
    ) -> Result<NodeId> {
        self.node(parent)?;
        let node = Node::new(title, kind, Some(parent));
        let id = node.id;
        self.nodes.insert(id, node);
        let p = self.node_mut(parent)?;
        let idx = index.unwrap_or(p.children.len()).min(p.children.len());
        p.children.insert(idx, id);
        p.expanded = true;
        self.touch();
        Ok(id)
    }

    /// Create a node as the next sibling of `sibling` (or inside it, if it is a
    /// root). The kind defaults from the section when `kind` is `None`.
    pub fn add_near(
        &mut self,
        sibling: NodeId,
        kind: Option<NodeKind>,
        title: &str,
    ) -> Result<NodeId> {
        let section = self.section_of(sibling)?;
        let kind = kind.unwrap_or(section.child_kind());
        if self.is_root(sibling) {
            return self.add_node(sibling, None, kind, title);
        }
        let parent = self.node(sibling)?.parent.expect("non-root has parent");
        let idx = self.index_in_parent(sibling)? + 1;
        self.add_node(parent, Some(idx), kind, title)
    }

    pub fn index_in_parent(&self, id: NodeId) -> Result<usize> {
        let parent = self
            .node(id)?
            .parent
            .ok_or_else(|| Error::Invalid("roots have no parent".into()))?;
        Ok(self
            .node(parent)?
            .children
            .iter()
            .position(|c| *c == id)
            .expect("child listed in parent"))
    }

    /// Move `id` to be a child of `new_parent` at `index`.
    pub fn move_node(&mut self, id: NodeId, new_parent: NodeId, index: usize) -> Result<()> {
        if self.is_root(id) {
            return Err(Error::Invalid("section roots cannot be moved".into()));
        }
        self.node(new_parent)?;
        if id == new_parent || self.ancestors(new_parent).contains(&id) {
            return Err(Error::Invalid("cannot move an item inside itself".into()));
        }
        let old_parent = self.node(id)?.parent.expect("non-root has parent");
        let old_idx = self.index_in_parent(id)?;
        self.node_mut(old_parent)?.children.remove(old_idx);
        let mut index = index;
        if old_parent == new_parent && old_idx < index {
            index -= 1;
        }
        let p = self.node_mut(new_parent)?;
        let index = index.min(p.children.len());
        p.children.insert(index, id);
        p.expanded = true;
        self.node_mut(id)?.parent = Some(new_parent);
        self.touch();
        Ok(())
    }

    /// Move an item up or down among its siblings.
    pub fn shift(&mut self, id: NodeId, delta: i32) -> Result<()> {
        let parent = self
            .node(id)?
            .parent
            .ok_or_else(|| Error::Invalid("section roots cannot be moved".into()))?;
        let idx = self.index_in_parent(id)? as i64;
        let len = self.node(parent)?.children.len() as i64;
        let new = (idx + delta as i64).clamp(0, len - 1) as usize;
        let ch = &mut self.node_mut(parent)?.children;
        let item = ch.remove(idx as usize);
        ch.insert(new, item);
        self.touch();
        Ok(())
    }

    /// Promote an item to be the sibling after its parent.
    pub fn outdent(&mut self, id: NodeId) -> Result<()> {
        let parent = self
            .node(id)?
            .parent
            .ok_or_else(|| Error::Invalid("root".into()))?;
        if self.is_root(parent) {
            return Ok(());
        }
        let grand = self.node(parent)?.parent.expect("parent is not root");
        let idx = self.index_in_parent(parent)? + 1;
        self.move_node(id, grand, idx)
    }

    /// Make an item the last child of its previous sibling.
    pub fn indent(&mut self, id: NodeId) -> Result<()> {
        let parent = self
            .node(id)?
            .parent
            .ok_or_else(|| Error::Invalid("root".into()))?;
        let idx = self.index_in_parent(id)?;
        if idx == 0 {
            return Ok(());
        }
        let prev = self.node(parent)?.children[idx - 1];
        let len = self.node(prev)?.children.len();
        self.move_node(id, prev, len)
    }

    /// Move an item to the Trash section.
    pub fn trash(&mut self, id: NodeId) -> Result<()> {
        let trash = self.root(RootRole::Trash);
        if self.section_of(id)? == RootRole::Trash && self.node(id)?.parent == Some(trash) {
            return Ok(());
        }
        let len = self.node(trash)?.children.len();
        self.move_node(id, trash, len)
    }

    /// Permanently delete everything in the Trash. Returns the removed ids so
    /// storage can delete their files.
    pub fn empty_trash(&mut self) -> Vec<NodeId> {
        let trash = self.root(RootRole::Trash);
        let kids = std::mem::take(&mut self.nodes.get_mut(&trash).unwrap().children);
        let mut removed = Vec::new();
        for k in kids {
            removed.extend(self.subtree(k));
        }
        for id in &removed {
            self.nodes.remove(id);
            self.contents.remove(id);
            self.timeline.forget_node(*id);
            self.relations.forget_node(*id);
        }
        self.touch();
        removed
    }

    /// Duplicate an item (and its subtree) right after itself.
    pub fn duplicate(&mut self, id: NodeId) -> Result<NodeId> {
        if self.is_root(id) {
            return Err(Error::Invalid("section roots cannot be duplicated".into()));
        }
        let parent = self.node(id)?.parent.unwrap();
        let idx = self.index_in_parent(id)? + 1;
        let new_id = self.clone_subtree(id, parent)?;
        self.node_mut(new_id)?.title.push_str(" (copy)");
        self.node_mut(parent)?.children.insert(idx, new_id);
        self.touch();
        Ok(new_id)
    }

    fn clone_subtree(&mut self, id: NodeId, parent: NodeId) -> Result<NodeId> {
        let src = self.node(id)?.clone();
        let now = Utc::now();
        let mut copy = src.clone();
        copy.id = Uuid::new_v4();
        copy.parent = Some(parent);
        copy.children = Vec::new();
        copy.created = now;
        copy.modified = now;
        let new_id = copy.id;
        self.nodes.insert(new_id, copy);
        if let Some(t) = self.contents.get(&id).cloned() {
            self.contents.insert(new_id, t);
        }
        for c in src.children {
            let cc = self.clone_subtree(c, new_id)?;
            self.node_mut(new_id)?.children.push(cc);
        }
        Ok(new_id)
    }

    /// Join several sibling documents into the first one.
    pub fn merge(&mut self, ids: &[NodeId]) -> Result<NodeId> {
        let (&first, rest) = ids
            .split_first()
            .ok_or_else(|| Error::Invalid("nothing to merge".into()))?;
        let mut text = self.text(first).to_string();
        for id in rest {
            let t = self.text(*id).to_string();
            if !t.is_empty() {
                if !text.is_empty() {
                    text.push_str("\n\n");
                }
                text.push_str(&t);
            }
            let kids = self.node(*id)?.children.clone();
            for k in kids {
                let len = self.node(first)?.children.len();
                self.move_node(k, first, len)?;
            }
            self.trash(*id)?;
        }
        self.set_text(first, text)?;
        Ok(first)
    }

    /// Split a document at a character offset; the tail becomes a new
    /// sibling directly after it.
    pub fn split(&mut self, id: NodeId, char_offset: usize, new_title: &str) -> Result<NodeId> {
        let text = self.text(id).to_string();
        let byte = text
            .char_indices()
            .nth(char_offset)
            .map(|(b, _)| b)
            .unwrap_or(text.len());
        let (head, tail) = text.split_at(byte);
        let kind = self.node(id)?.kind;
        let new_id = self.add_near(id, Some(kind), new_title)?;
        let tail = tail.trim_start_matches(['\n', '\r']).to_string();
        let head = head.trim_end().to_string();
        self.set_text(new_id, tail)?;
        self.set_text(id, head)?;
        Ok(new_id)
    }

    /// The binder as display rows, skipping the children of collapsed items.
    pub fn flatten(&self) -> Vec<FlatRow> {
        let mut out = Vec::new();
        for r in &self.roots {
            self.flatten_into(*r, 0, &mut out);
        }
        out
    }

    fn flatten_into(&self, id: NodeId, depth: usize, out: &mut Vec<FlatRow>) {
        let n = &self.nodes[&id];
        out.push(FlatRow {
            id,
            title: n.title.clone(),
            kind: n.kind,
            role: n.role,
            depth,
            has_children: !n.children.is_empty(),
            expanded: n.expanded,
            label_color: n.label.and_then(|l| self.label(l)).map(|l| l.color.clone()),
        });
        if n.expanded {
            for c in &n.children {
                self.flatten_into(*c, depth + 1, out);
            }
        }
    }

    pub fn label(&self, id: Uuid) -> Option<&Label> {
        self.labels.iter().find(|l| l.id == id)
    }

    pub fn status(&self, id: Uuid) -> Option<&Status> {
        self.statuses.iter().find(|s| s.id == id)
    }

    /// Words in this item's own text.
    pub fn own_words(&self, id: NodeId) -> usize {
        crate::stats::count_words(self.text(id))
    }

    /// Words in this item and all of its descendants.
    pub fn total_words(&self, id: NodeId) -> usize {
        self.subtree(id)
            .into_iter()
            .map(|n| self.own_words(n))
            .sum()
    }

    /// Every distinct keyword used in the project, sorted.
    pub fn all_keywords(&self) -> Vec<String> {
        let set: HashSet<&String> = self
            .nodes
            .values()
            .flat_map(|n| n.keywords.iter())
            .collect();
        let mut v: Vec<String> = set.into_iter().cloned().collect();
        v.sort_by_key(|k| k.to_lowercase());
        v
    }

    /// Check structural invariants; used after load and in tests.
    pub fn validate(&self) -> Result<()> {
        for role in RootRole::ALL {
            if !self
                .roots
                .iter()
                .any(|r| self.nodes.get(r).and_then(|n| n.role) == Some(role))
            {
                return Err(Error::Invalid(format!("missing section {role:?}")));
            }
        }
        let mut seen = HashSet::new();
        for r in &self.roots {
            for id in self.subtree(*r) {
                if !seen.insert(id) {
                    return Err(Error::Invalid(format!("node {id} appears twice")));
                }
                for c in &self.nodes[&id].children {
                    match self.nodes.get(c) {
                        Some(cn) if cn.parent == Some(id) => {}
                        _ => return Err(Error::Invalid(format!("bad child link {id} -> {c}"))),
                    }
                }
            }
        }
        if seen.len() != self.nodes.len() {
            return Err(Error::Invalid("unreachable nodes in project".into()));
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn titles(p: &Project, parent: NodeId) -> Vec<String> {
        p.nodes[&parent]
            .children
            .iter()
            .map(|c| p.nodes[c].title.clone())
            .collect()
    }

    #[test]
    fn new_project_is_valid() {
        let p = Project::new("Novel", "Me");
        p.validate().unwrap();
        assert_eq!(p.roots.len(), 6);
        let ms = p.root(RootRole::Manuscript);
        assert_eq!(titles(&p, ms), vec!["Chapter 1"]);
    }

    #[test]
    fn add_move_and_shift() {
        let mut p = Project::new("N", "");
        let ms = p.root(RootRole::Manuscript);
        let a = p.add_node(ms, None, NodeKind::Folder, "A").unwrap();
        let b = p.add_node(ms, None, NodeKind::Folder, "B").unwrap();
        p.move_node(b, ms, 0).unwrap();
        assert_eq!(titles(&p, ms), vec!["B", "Chapter 1", "A"]);
        p.shift(b, 5).unwrap();
        assert_eq!(titles(&p, ms), vec!["Chapter 1", "A", "B"]);
        p.move_node(b, a, 0).unwrap();
        assert_eq!(titles(&p, a), vec!["B"]);
        assert!(p.move_node(a, b, 0).is_err(), "cycle must be rejected");
        assert!(p.move_node(ms, a, 0).is_err(), "roots are fixed");
        p.validate().unwrap();
    }

    #[test]
    fn move_within_same_parent_forward() {
        let mut p = Project::new("N", "");
        let ms = p.root(RootRole::Manuscript);
        let a = p.add_node(ms, None, NodeKind::Text, "A").unwrap();
        p.add_node(ms, None, NodeKind::Text, "B").unwrap();
        // Drop A after B (index counted before removal).
        p.move_node(a, ms, 3).unwrap();
        assert_eq!(titles(&p, ms), vec!["Chapter 1", "B", "A"]);
    }

    #[test]
    fn indent_outdent() {
        let mut p = Project::new("N", "");
        let ms = p.root(RootRole::Manuscript);
        let ch = p.nodes[&ms].children[0];
        let s2 = p.add_node(ms, None, NodeKind::Text, "Loose").unwrap();
        p.indent(s2).unwrap();
        assert_eq!(p.nodes[&s2].parent, Some(ch));
        p.outdent(s2).unwrap();
        assert_eq!(p.nodes[&s2].parent, Some(ms));
        p.validate().unwrap();
    }

    #[test]
    fn trash_and_empty() {
        let mut p = Project::new("N", "");
        let ms = p.root(RootRole::Manuscript);
        let ch = p.nodes[&ms].children[0];
        let scene = p.nodes[&ch].children[0];
        p.set_text(scene, "hello world".into()).unwrap();
        p.trash(ch).unwrap();
        assert_eq!(p.section_of(scene).unwrap(), RootRole::Trash);
        let removed = p.empty_trash();
        assert_eq!(removed.len(), 2);
        assert!(!p.contents.contains_key(&scene));
        p.validate().unwrap();
    }

    #[test]
    fn duplicate_copies_subtree_and_text() {
        let mut p = Project::new("N", "");
        let ms = p.root(RootRole::Manuscript);
        let ch = p.nodes[&ms].children[0];
        let scene = p.nodes[&ch].children[0];
        p.set_text(scene, "one two three".into()).unwrap();
        let copy = p.duplicate(ch).unwrap();
        assert_eq!(p.nodes[&copy].title, "Chapter 1 (copy)");
        assert_eq!(p.total_words(copy), 3);
        assert_eq!(p.total_words(ms), 6);
        p.validate().unwrap();
    }

    #[test]
    fn split_and_merge() {
        let mut p = Project::new("N", "");
        let ms = p.root(RootRole::Manuscript);
        let ch = p.nodes[&ms].children[0];
        let scene = p.nodes[&ch].children[0];
        p.set_text(scene, "First part.\n\nSecond part.".into())
            .unwrap();
        let tail = p.split(scene, 11, "Scene 2").unwrap();
        assert_eq!(p.text(scene), "First part.");
        assert_eq!(p.text(tail), "Second part.");
        p.merge(&[scene, tail]).unwrap();
        assert_eq!(p.text(scene), "First part.\n\nSecond part.");
        assert_eq!(p.section_of(tail).unwrap(), RootRole::Trash);
    }

    #[test]
    fn flatten_respects_collapse() {
        let mut p = Project::new("N", "");
        let all = p.flatten().len();
        let ms = p.root(RootRole::Manuscript);
        p.node_mut(ms).unwrap().expanded = false;
        assert_eq!(p.flatten().len(), all - 2);
    }
}
