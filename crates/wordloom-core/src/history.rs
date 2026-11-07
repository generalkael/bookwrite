//! Project-wide undo and redo.
//!
//! Every change made through the API (binder edits, metadata, labels, the
//! timeline, replace-all, …) records a [`Step`]: the project's structure as it
//! was before the change, plus the before/after text of any document the
//! change touched. Typing in the editor is *not* recorded here; the editor has
//! its own undo, and keeping typing out means undoing an old binder move never
//! throws away paragraphs written since.
//!
//! To stay safe when typing happens between steps, undo and redo
//!
//! * keep the live writing statistics and binder expand/collapse state, and
//! * only rewrite a document's text if it still matches what the step left
//!   behind; text edited since is never overwritten.

use std::collections::HashMap;
use std::time::{Duration, Instant};

use crate::model::{NodeId, Project};
use crate::stats::WritingStats;

/// Undo steps kept per open project.
const LIMIT: usize = 200;
/// Repeated edits with the same key within this window merge into one step.
const COALESCE: Duration = Duration::from_secs(2);

/// The state of a project just before a change, used to build a [`Step`].
pub struct Checkpoint {
    state: Project,
    contents: HashMap<NodeId, String>,
}

impl Checkpoint {
    pub fn take(p: &Project) -> Self {
        Self {
            state: structure(p),
            contents: p.contents.clone(),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
struct TextChange {
    id: NodeId,
    old: String,
    new: String,
}

struct Step {
    label: String,
    key: Option<String>,
    at: Instant,
    /// The structure to restore when this step is applied.
    state: Project,
    texts: Vec<TextChange>,
}

#[derive(Default)]
pub struct History {
    undo: Vec<Step>,
    redo: Vec<Step>,
}

impl History {
    /// Record the change from `before` to `now` as one undo step called
    /// `label`. Consecutive changes with the same `key` made within a couple
    /// of seconds merge. Returns false if nothing actually changed.
    pub fn record(
        &mut self,
        before: Checkpoint,
        now: &Project,
        label: &str,
        key: Option<String>,
    ) -> bool {
        let texts = diff(&before.contents, &now.contents);
        if texts.is_empty() && fingerprint(&before.state) == fingerprint(now) {
            return false;
        }
        self.redo.clear();
        if let Some(top) = self.undo.last_mut() {
            if key.is_some() && top.key == key && top.at.elapsed() < COALESCE {
                for t in texts {
                    match top.texts.iter_mut().find(|o| o.id == t.id) {
                        Some(o) => o.new = t.new,
                        None => top.texts.push(t),
                    }
                }
                top.texts.retain(|t| t.old != t.new);
                top.at = Instant::now();
                return true;
            }
        }
        self.undo.push(Step {
            label: label.to_string(),
            key,
            at: Instant::now(),
            state: before.state,
            texts,
        });
        if self.undo.len() > LIMIT {
            self.undo.remove(0);
        }
        true
    }

    /// Undo the most recent step; returns its label.
    pub fn undo(&mut self, p: &mut Project) -> Option<String> {
        let step = self.undo.pop()?;
        let label = step.label.clone();
        let current = apply(p, step.state, &step.texts, true);
        self.redo.push(Step {
            state: current,
            at: Instant::now(),
            key: None,
            ..step
        });
        Some(label)
    }

    /// Redo the most recently undone step; returns its label.
    pub fn redo(&mut self, p: &mut Project) -> Option<String> {
        let step = self.redo.pop()?;
        let label = step.label.clone();
        let current = apply(p, step.state, &step.texts, false);
        self.undo.push(Step {
            state: current,
            at: Instant::now(),
            key: None,
            ..step
        });
        Some(label)
    }

    pub fn undo_label(&self) -> Option<&str> {
        self.undo.last().map(|s| s.label.as_str())
    }

    pub fn redo_label(&self) -> Option<&str> {
        self.redo.last().map(|s| s.label.as_str())
    }

    /// Imported file names that some undo or redo step could bring back.
    pub fn referenced_files(&self) -> impl Iterator<Item = &str> {
        self.undo
            .iter()
            .chain(&self.redo)
            .flat_map(|s| s.state.nodes.values())
            .filter_map(|n| n.file.as_deref())
    }

    pub fn clear(&mut self) {
        self.undo.clear();
        self.redo.clear();
    }
}

/// Copy of everything in a project except document text.
fn structure(p: &Project) -> Project {
    Project {
        format_version: p.format_version,
        meta: p.meta.clone(),
        roots: p.roots.clone(),
        nodes: p.nodes.clone(),
        labels: p.labels.clone(),
        statuses: p.statuses.clone(),
        timeline: p.timeline.clone(),
        relations: p.relations.clone(),
        stats: p.stats.clone(),
        contents: HashMap::new(),
    }
}

/// Serialized form of the parts a step can change, ignoring timestamps and
/// statistics, to tell whether a call changed anything.
fn fingerprint(p: &Project) -> Vec<u8> {
    serde_json::to_vec(&(
        &p.meta.title,
        &p.meta.author,
        &p.roots,
        &p.nodes,
        &p.labels,
        &p.statuses,
        &p.timeline,
        &p.relations,
        (
            p.stats.manuscript_target,
            p.stats.session_target,
            p.stats.deadline,
        ),
    ))
    .unwrap_or_default()
}

fn diff(before: &HashMap<NodeId, String>, after: &HashMap<NodeId, String>) -> Vec<TextChange> {
    let mut ids: Vec<NodeId> = before.keys().chain(after.keys()).copied().collect();
    ids.sort();
    ids.dedup();
    ids.into_iter()
        .filter_map(|id| {
            let old = before.get(&id).map(String::as_str).unwrap_or("");
            let new = after.get(&id).map(String::as_str).unwrap_or("");
            (old != new).then(|| TextChange {
                id,
                old: old.to_string(),
                new: new.to_string(),
            })
        })
        .collect()
}

/// Put `state` in place and roll texts to their old (`back`) or new side.
/// Returns the structure that was replaced, for the opposite stack.
fn apply(p: &mut Project, state: Project, texts: &[TextChange], back: bool) -> Project {
    let current = structure(p);
    let contents = std::mem::take(&mut p.contents);
    let live = std::mem::take(&mut p.stats);
    let mut state = state;
    // Targets are part of the step; the daily word history stays live.
    state.stats = WritingStats {
        manuscript_target: state.stats.manuscript_target,
        session_target: state.stats.session_target,
        deadline: state.stats.deadline,
        ..live
    };
    *p = state;
    p.contents = contents;
    for n in p.nodes.values_mut() {
        if let Some(c) = current.nodes.get(&n.id) {
            n.expanded = c.expanded;
            n.favorite = c.favorite;
        }
    }
    for t in texts {
        let (expect, target) = if back {
            (&t.new, &t.old)
        } else {
            (&t.old, &t.new)
        };
        if p.text(t.id) != expect.as_str() {
            continue; // edited since: leave the newer text alone
        }
        if target.is_empty() {
            p.contents.remove(&t.id);
        } else {
            p.contents.insert(t.id, target.clone());
        }
    }
    p.touch();
    current
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{NodeKind, RootRole};

    fn scene(p: &Project) -> NodeId {
        let ms = p.root(RootRole::Manuscript);
        p.nodes[&p.nodes[&ms].children[0]].children[0]
    }

    fn change(h: &mut History, p: &mut Project, label: &str, f: impl FnOnce(&mut Project)) {
        let cp = Checkpoint::take(p);
        f(p);
        h.record(cp, p, label, None);
    }

    #[test]
    fn undo_redo_structure_and_text() {
        let mut p = Project::new("T", "");
        let mut h = History::default();
        let s = scene(&p);
        p.set_text(s, "cat sat".into()).unwrap();
        let ms = p.root(RootRole::Manuscript);

        change(&mut h, &mut p, "Add", |p| {
            p.add_node(ms, None, NodeKind::Text, "New").unwrap();
        });
        change(&mut h, &mut p, "Replace All", |p| {
            p.set_text(s, "dog sat".into()).unwrap();
        });
        assert_eq!(h.undo_label(), Some("Replace All"));
        let count = p.nodes.len();

        assert_eq!(h.undo(&mut p).as_deref(), Some("Replace All"));
        assert_eq!(p.text(s), "cat sat");
        assert_eq!(h.undo(&mut p).as_deref(), Some("Add"));
        assert_eq!(p.nodes.len(), count - 1);
        assert!(h.undo(&mut p).is_none());
        p.validate().unwrap();

        assert_eq!(h.redo(&mut p).as_deref(), Some("Add"));
        assert_eq!(h.redo(&mut p).as_deref(), Some("Replace All"));
        assert_eq!(p.nodes.len(), count);
        assert_eq!(p.text(s), "dog sat");
        assert!(h.redo_label().is_none());
        p.validate().unwrap();
    }

    #[test]
    fn newer_typing_and_stats_survive() {
        let mut p = Project::new("T", "");
        let mut h = History::default();
        let s = scene(&p);
        let ms = p.root(RootRole::Manuscript);
        change(&mut h, &mut p, "Add", |p| {
            p.add_node(ms, None, NodeKind::Text, "New").unwrap();
        });
        change(&mut h, &mut p, "Replace All", |p| {
            p.set_text(s, "replaced".into()).unwrap();
        });
        // Typing outside the history, after both steps.
        p.set_text(s, "replaced and then typed".into()).unwrap();
        p.stats.record(5);

        h.undo(&mut p);
        h.undo(&mut p);
        assert_eq!(p.text(s), "replaced and then typed");
        assert_eq!(p.stats.words_on(chrono::Local::now().date_naive()), 5);
    }

    #[test]
    fn empty_trash_brings_text_back() {
        let mut p = Project::new("T", "");
        let mut h = History::default();
        let s = scene(&p);
        p.set_text(s, "precious".into()).unwrap();
        p.trash(s).unwrap();
        change(&mut h, &mut p, "Empty Trash", |p| {
            p.empty_trash();
        });
        assert!(!p.nodes.contains_key(&s));
        h.undo(&mut p);
        assert_eq!(p.text(s), "precious");
        p.validate().unwrap();
    }

    #[test]
    fn coalesce_and_skip_noops() {
        let mut p = Project::new("T", "");
        let mut h = History::default();
        let s = scene(&p);
        let key = Some(format!("title:{s}"));
        for t in ["A", "AB", "ABC"] {
            let cp = Checkpoint::take(&p);
            p.node_mut(s).unwrap().title = t.into();
            assert!(h.record(cp, &p, "Rename", key.clone()));
        }
        let cp = Checkpoint::take(&p);
        assert!(!h.record(cp, &p, "Nothing", None));
        h.undo(&mut p);
        assert_eq!(p.nodes[&s].title, "Scene 1");
        assert!(h.undo_label().is_none());
    }
}
