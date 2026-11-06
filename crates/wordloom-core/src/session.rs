//! An open project plus its location on disk, exposing a JSON-shaped API that
//! the UI layer drives. Keeping this in the core crate means all behaviour is
//! testable without Qt; the Qt bridge is a thin adapter over [`Session`].

use std::path::{Path, PathBuf};

use chrono::{Local, NaiveDate};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::compile::{self, CompileOptions};
use crate::history::History;
use crate::model::{Label, NodeId, NodeKind, Project, RootRole, Status};
use crate::timeline::{Event, Track, TrackKind};
use crate::{search, stats, storage, Error, Result};

pub struct Session {
    pub project: Project,
    pub dir: PathBuf,
    pub dirty: bool,
    /// Undo/redo for this project; not saved to disk.
    pub history: History,
}

impl Drop for Session {
    fn drop(&mut self) {
        storage::remove_lock(&self.dir);
    }
}

pub fn parse_id(s: &str) -> Result<Uuid> {
    Uuid::parse_str(s.trim()).map_err(|_| Error::Invalid(format!("bad id {s:?}")))
}

fn opt_id(s: &str) -> Result<Option<Uuid>> {
    if s.trim().is_empty() {
        Ok(None)
    } else {
        parse_id(s).map(Some)
    }
}

impl Session {
    /// Create a new project bundle named after `title` inside `parent`.
    pub fn create(parent: &Path, title: &str, author: &str) -> Result<Self> {
        let dir = storage::new_bundle_path(parent, title);
        if dir.exists() {
            return Err(Error::Invalid(format!("{} already exists", dir.display())));
        }
        let project = Project::new(title, author);
        storage::save(&project, &dir)?;
        storage::write_lock(&dir)?;
        Ok(Self {
            project,
            dir,
            dirty: false,
            history: History::default(),
        })
    }

    pub fn open(path: &Path) -> Result<Self> {
        Self::open_with(path, false)
    }

    /// Open a project; unless `force`, refuse with [`Error::Locked`] when
    /// another Wordloom has it open.
    pub fn open_with(path: &Path, force: bool) -> Result<Self> {
        let dir = storage::bundle_dir(path);
        if !force {
            if let Some(holder) = storage::lock_holder(&dir) {
                return Err(Error::Locked(holder));
            }
        }
        let project = storage::load(&dir)?;
        storage::write_lock(&dir)?;
        Ok(Self {
            project,
            dir,
            dirty: false,
            history: History::default(),
        })
    }

    pub fn save(&mut self) -> Result<()> {
        self.note_totals();
        storage::save(&self.project, &self.dir)?;
        storage::write_lock(&self.dir)?; // still here
        self.dirty = false;
        Ok(())
    }

    /// Give a binder entry back to text files the project doesn't list,
    /// e.g. documents written after the backup that was just restored
    /// (otherwise the next save would delete them). They go in a
    /// "Recovered after restore" folder at the end of the Manuscript.
    /// Returns how many were recovered.
    pub fn adopt_orphan_texts(&mut self) -> Result<usize> {
        let content = self.dir.join("content");
        let Ok(entries) = std::fs::read_dir(&content) else {
            return Ok(0);
        };
        let mut orphans: Vec<(String, String)> = Vec::new();
        for e in entries.filter_map(|e| e.ok()) {
            let path = e.path();
            let id = path
                .file_stem()
                .and_then(|s| s.to_str())
                .and_then(|s| Uuid::parse_str(s).ok());
            if path.extension().is_some_and(|x| x == "md")
                && id.is_some_and(|id| !self.project.nodes.contains_key(&id))
            {
                if let Ok(text) = std::fs::read_to_string(&path) {
                    if !text.trim().is_empty() {
                        let title: String = text
                            .split_whitespace()
                            .take(6)
                            .collect::<Vec<_>>()
                            .join(" ")
                            .trim_matches(|c: char| !c.is_alphanumeric())
                            .to_string();
                        orphans.push((
                            if title.is_empty() {
                                "Recovered".into()
                            } else {
                                title
                            },
                            text,
                        ));
                        let _ = std::fs::remove_file(&path); // re-saved under the new id
                    }
                }
            }
        }
        if orphans.is_empty() {
            return Ok(0);
        }
        let ms = self.project.root(RootRole::Manuscript);
        let folder =
            self.project
                .add_node(ms, None, NodeKind::Folder, "Recovered after restore")?;
        for (title, text) in &orphans {
            let id = self.project.add_node(folder, None, NodeKind::Text, title)?;
            self.project.set_text(id, text.clone())?;
        }
        self.changed();
        self.save()?;
        Ok(orphans.len())
    }

    /// Save, then pack the project into `Title backup YYYY-MM-DD HHMM.zip`
    /// in `folder` (or at `folder` itself if it ends in `.zip`).
    pub fn backup_zip(&mut self, folder: &Path) -> Result<Value> {
        self.save()?;
        let dest = if folder
            .extension()
            .is_some_and(|e| e.eq_ignore_ascii_case("zip"))
        {
            folder.to_path_buf()
        } else {
            let stem = storage::new_bundle_path(folder, &self.project.meta.title);
            let stem = stem
                .file_stem()
                .unwrap_or_default()
                .to_string_lossy()
                .into_owned();
            let when = chrono::Local::now().format("%Y-%m-%d %H%M");
            folder.join(format!("{stem} backup {when}.zip"))
        };
        let files = storage::backup_zip(&self.dir, &dest)?;
        let bytes = std::fs::metadata(&dest).map(|m| m.len()).unwrap_or(0);
        Ok(json!({"path": dest, "files": files, "bytes": bytes}))
    }

    /// Save a copy to a new bundle location and continue working there.
    pub fn save_as(&mut self, parent: &Path, title: &str) -> Result<()> {
        let dir = storage::new_bundle_path(parent, title);
        if dir.exists() {
            return Err(Error::Invalid(format!("{} already exists", dir.display())));
        }
        self.project.meta.title = title.to_string();
        storage::save(&self.project, &dir)?;
        storage::copy_assets(&self.dir, &dir)?;
        storage::remove_lock(&self.dir);
        storage::write_lock(&dir)?;
        self.dir = dir;
        self.dirty = false;
        Ok(())
    }

    fn changed(&mut self) {
        self.dirty = true;
        self.project.touch();
    }

    // ----- undo -----------------------------------------------------------

    /// Undo the last change; returns its label, or None if there was none.
    pub fn undo(&mut self) -> Option<String> {
        let label = self.history.undo(&mut self.project)?;
        self.dirty = true;
        Some(label)
    }

    /// Redo the last undone change; returns its label.
    pub fn redo(&mut self) -> Option<String> {
        let label = self.history.redo(&mut self.project)?;
        self.dirty = true;
        Some(label)
    }

    // ----- binder ---------------------------------------------------------

    pub fn binder(&self) -> Value {
        json!(self.project.flatten())
    }

    pub fn toggle_expanded(&mut self, id: &str) -> Result<()> {
        let n = self.project.node_mut(parse_id(id)?)?;
        n.expanded = !n.expanded;
        self.dirty = true;
        Ok(())
    }

    pub fn set_all_expanded(&mut self, expanded: bool) {
        for n in self.project.nodes.values_mut() {
            if !n.children.is_empty() {
                n.expanded = expanded;
            }
        }
        self.dirty = true;
    }

    pub fn node_info(&self, id: &str) -> Result<Value> {
        let id = parse_id(id)?;
        let p = &self.project;
        let n = p.node(id)?;
        let mut crumbs: Vec<String> = p
            .ancestors(id)
            .iter()
            .map(|a| p.nodes[a].title.clone())
            .collect();
        crumbs.reverse();
        let events: Vec<Value> = p
            .timeline
            .events_for_node(id)
            .iter()
            .map(
                |e| json!({"id": e.id, "title": e.title, "start": e.start, "duration": e.duration}),
            )
            .collect();
        Ok(json!({
            "id": n.id,
            "title": n.title,
            "kind": n.kind,
            "role": n.role,
            "section": p.section_of(id)?,
            "is_root": p.is_root(id),
            "synopsis": n.synopsis,
            "notes": n.notes,
            "label": n.label,
            "status": n.status,
            "keywords": n.keywords,
            "include_in_compile": n.include_in_compile,
            "target_words": n.target_words,
            "fields": n.fields,
            "file": n.file.as_ref().map(|f| self.file_info(f)),
            "words": p.own_words(id),
            "total_words": p.total_words(id),
            "chars": stats::count_chars(p.text(id)),
            "child_count": n.children.len(),
            "created": n.created,
            "modified": n.modified,
            "breadcrumbs": crumbs,
            "events": events,
            "relations": p
                .relations
                .for_node(id)
                .map(|r| {
                    let other = if r.from == id { r.to } else { r.from };
                    json!({
                        "id": r.id,
                        "other": other,
                        "other_title": p.nodes.get(&other).map(|n| n.title.as_str()).unwrap_or(""),
                        "label": r.label,
                        "outgoing": r.from == id,
                    })
                })
                .collect::<Vec<_>>(),
        }))
    }

    /// Where an imported file lives, and how the UI should show it.
    fn file_info(&self, name: &str) -> Value {
        let path = self.dir.join(storage::FILES_DIR).join(name);
        let ext = Path::new(name)
            .extension()
            .and_then(|e| e.to_str())
            .unwrap_or("");
        let kind = match ext {
            "png" | "jpg" | "jpeg" | "gif" | "webp" | "bmp" | "svg" => "image",
            "pdf" => "pdf",
            _ => "other",
        };
        json!({
            "url": url::Url::from_file_path(&path).map(String::from).unwrap_or_default(),
            "kind": kind,
            "exists": path.is_file(),
        })
    }

    /// Imported files nothing refers to: not the project (trash included)
    /// and not any undo / redo step. `delete` removes them; either way the
    /// result is `{count, bytes}`.
    pub fn unused_files(&self, delete: bool) -> Result<Value> {
        let keep: std::collections::HashSet<&str> = self
            .project
            .nodes
            .values()
            .filter_map(|n| n.file.as_deref())
            .chain(self.history.referenced_files())
            .collect();
        let unused = storage::unused_files(&self.dir, &keep)?;
        if delete {
            for (name, _) in &unused {
                std::fs::remove_file(self.dir.join(storage::FILES_DIR).join(name))?;
            }
        }
        Ok(json!({
            "count": unused.len(),
            "bytes": unused.iter().map(|(_, b)| b).sum::<u64>(),
        }))
    }

    /// Import a file as a research item under `parent` (default: the
    /// Research section), titled after the file.
    pub fn import_file(&mut self, parent: &str, src: &Path) -> Result<String> {
        let parent = match opt_id(parent)? {
            Some(id) => id,
            None => self.project.root(RootRole::Research),
        };
        self.project.node(parent)?;
        let name = storage::import_file(&self.dir, src)?;
        let title = src
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("Imported file");
        let id = self
            .project
            .add_node(parent, None, NodeKind::Research, title)?;
        self.project.node_mut(id)?.file = Some(name);
        self.changed();
        Ok(id.to_string())
    }

    /// Children of `id` as index cards (corkboard / outliner).
    pub fn children(&self, id: &str) -> Result<Value> {
        let p = &self.project;
        let n = p.node(parse_id(id)?)?;
        let cards: Vec<Value> = n
            .children
            .iter()
            .map(|c| {
                let cn = &p.nodes[c];
                json!({
                    "id": cn.id,
                    "title": cn.title,
                    "kind": cn.kind,
                    "synopsis": cn.synopsis,
                    "label": cn.label,
                    "status": cn.status,
                    "label_color": cn.label.and_then(|l| p.label(l)).map(|l| l.color.clone()),
                    "label_name": cn.label.and_then(|l| p.label(l)).map(|l| l.name.clone()),
                    "status_name": cn.status.and_then(|s| p.status(s)).map(|s| s.name.clone()),
                    "words": p.own_words(cn.id),
                    "total_words": p.total_words(cn.id),
                    "target_words": cn.target_words,
                    "child_count": cn.children.len(),
                    "include_in_compile": cn.include_in_compile,
                    "keywords": cn.keywords,
                })
            })
            .collect();
        Ok(json!(cards))
    }

    /// Text analysis of `id` and the documents under it (the manuscript if
    /// `id` is empty).
    pub fn analyse(&self, id: &str) -> Result<Value> {
        let root = if id.is_empty() {
            self.project.root(crate::model::RootRole::Manuscript)
        } else {
            let id = parse_id(id)?;
            self.project.node(id)?;
            id
        };
        Ok(json!(crate::analysis::analyse(&self.project, root)))
    }

    /// Import a manuscript (.docx, .md, .txt) into a new folder at the end of
    /// the Manuscript: one folder per chapter, one document per scene.
    pub fn import_manuscript(&mut self, path: &Path) -> Result<Value> {
        let book = crate::import::read(path)?;
        let words: usize = book
            .chapters
            .iter()
            .flat_map(|c| &c.scenes)
            .flat_map(|s| &s.paras)
            .map(|t| stats::count_words(t))
            .sum();
        if words == 0 {
            return Err(Error::Invalid("No text found to import".into()));
        }
        let p = &mut self.project;
        let ms = p.root(RootRole::Manuscript);
        let name = book.title.clone().unwrap_or_else(|| {
            path.file_stem()
                .map(|s| s.to_string_lossy().into_owned())
                .unwrap_or_else(|| "Imported".into())
        });
        let folder = p.add_node(ms, None, NodeKind::Folder, &name)?;
        let mut scenes = 0;
        for c in &book.chapters {
            let ch = p.add_node(folder, None, NodeKind::Folder, &c.title)?;
            for (k, s) in c.scenes.iter().enumerate() {
                let title = s
                    .title
                    .clone()
                    .unwrap_or_else(|| format!("Scene {}", k + 1));
                let d = p.add_node(ch, None, NodeKind::Text, &title)?;
                p.set_text(d, s.paras.join("\n\n"))?;
                scenes += 1;
            }
        }
        self.changed();
        Ok(
            json!({"folder": folder, "chapters": book.chapters.len(), "scenes": scenes, "words": words}),
        )
    }

    /// Binder items matching `query` for Go to… (recent items if empty).
    pub fn go_to(&self, query: &str) -> Value {
        json!(crate::goto::go_to(&self.project, query, 40))
    }

    /// Expand the folders above `id` so the binder shows it.
    pub fn reveal(&mut self, id: &str) -> Result<()> {
        let id = parse_id(id)?;
        self.project.node(id)?;
        crate::goto::reveal(&mut self.project, id);
        self.dirty = true;
        Ok(())
    }

    /// The manuscript documents that mention character / place `id`.
    pub fn appearances(&self, id: &str) -> Result<Value> {
        let id = parse_id(id)?;
        self.project.node(id)?;
        Ok(json!(crate::mentions::appearances(&self.project, id)))
    }

    /// Inline comments in `id` and everything under it, in binder order.
    pub fn comments(&self, id: &str) -> Result<Value> {
        let p = &self.project;
        let root = parse_id(id)?;
        p.node(root)?;
        let mut out = Vec::new();
        for n in p.subtree(root) {
            for c in crate::comments::list(p.text(n)) {
                out.push(json!({
                    "node": n, "title": p.nodes[&n].title,
                    "start": c.start, "end": c.end, "text": c.text,
                }));
            }
        }
        Ok(json!(out))
    }

    pub fn text(&self, id: &str) -> Result<String> {
        Ok(self.project.text(parse_id(id)?).to_string())
    }

    pub fn set_text(&mut self, id: &str, text: &str) -> Result<()> {
        let id = parse_id(id)?;
        if self.project.text(id) == text {
            return Ok(());
        }
        let delta = self.project.set_text(id, text.to_string())?;
        if self.project.section_of(id)? == RootRole::Manuscript {
            self.project.stats.record(delta);
        }
        self.dirty = true;
        Ok(())
    }

    /// Set one metadata field from a string value (as edited in the UI).
    pub fn set_field(&mut self, id: &str, field: &str, value: &str) -> Result<()> {
        let id = parse_id(id)?;
        let is_root = self.project.is_root(id);
        let labels_ok = |p: &Project, v: Option<Uuid>| v.is_none_or(|v| p.label(v).is_some());
        let statuses_ok = |p: &Project, v: Option<Uuid>| v.is_none_or(|v| p.status(v).is_some());
        let label = if field == "label" {
            opt_id(value)?
        } else {
            None
        };
        let status = if field == "status" {
            opt_id(value)?
        } else {
            None
        };
        if !labels_ok(&self.project, label) || !statuses_ok(&self.project, status) {
            return Err(Error::Invalid("unknown label or status".into()));
        }
        let n = self.project.node_mut(id)?;
        match field {
            "title" => {
                let v = value.trim();
                if v.is_empty() {
                    return Err(Error::Invalid("title cannot be empty".into()));
                }
                n.title = v.to_string();
            }
            "synopsis" => n.synopsis = value.to_string(),
            "notes" => n.notes = value.to_string(),
            "label" => n.label = label,
            "status" => n.status = status,
            "keywords" => {
                n.keywords = value
                    .split(',')
                    .map(str::trim)
                    .filter(|k| !k.is_empty())
                    .map(String::from)
                    .collect()
            }
            "include_in_compile" => n.include_in_compile = value == "true",
            "target_words" => n.target_words = value.trim().parse().ok().filter(|v| *v > 0),
            "kind" if !is_root => {
                n.kind = NodeKind::parse(value).ok_or_else(|| Error::Invalid("bad kind".into()))?
            }
            f if f.starts_with("field:") => {
                let key = f["field:".len()..].trim().to_string();
                if value.is_empty() {
                    n.fields.remove(&key);
                } else {
                    n.fields.insert(key, value.to_string());
                }
            }
            _ => return Err(Error::Invalid(format!("unknown field {field}"))),
        }
        n.modified = chrono::Utc::now();
        self.changed();
        Ok(())
    }

    /// Add an item. With `inside`, it becomes the last child of `target`;
    /// otherwise the next sibling (roots always receive children).
    pub fn add(&mut self, target: &str, kind: &str, title: &str, inside: bool) -> Result<String> {
        let target = parse_id(target)?;
        let kind = NodeKind::parse(kind);
        let section = self.project.section_of(target)?;
        let title = if title.trim().is_empty() {
            match kind.unwrap_or(section.child_kind()) {
                NodeKind::Folder => "New Folder",
                NodeKind::Character => "New Character",
                NodeKind::Place => "New Place",
                _ => "Untitled",
            }
        } else {
            title.trim()
        };
        let id = if inside {
            let k = kind.unwrap_or(section.child_kind());
            self.project.add_node(target, None, k, title)?
        } else {
            self.project.add_near(target, kind, title)?
        };
        self.changed();
        Ok(id.to_string())
    }

    pub fn move_node(&mut self, id: &str, parent: &str, index: i32) -> Result<()> {
        self.project
            .move_node(parse_id(id)?, parse_id(parent)?, index.max(0) as usize)?;
        self.changed();
        Ok(())
    }

    /// Drop `id` relative to `target`: "before", "after" or "inside".
    pub fn drop_on(&mut self, id: &str, target: &str, position: &str) -> Result<()> {
        let id = parse_id(id)?;
        let target = parse_id(target)?;
        let p = &mut self.project;
        if position == "inside" || p.is_root(target) {
            let len = p.node(target)?.children.len();
            p.move_node(id, target, len)?;
        } else {
            let parent = p.node(target)?.parent.expect("non-root");
            let idx = p.index_in_parent(target)? + usize::from(position == "after");
            p.move_node(id, parent, idx)?;
        }
        self.changed();
        Ok(())
    }

    pub fn shift(&mut self, id: &str, delta: i32) -> Result<()> {
        self.project.shift(parse_id(id)?, delta)?;
        self.changed();
        Ok(())
    }

    pub fn indent(&mut self, id: &str) -> Result<()> {
        self.project.indent(parse_id(id)?)?;
        self.changed();
        Ok(())
    }

    pub fn outdent(&mut self, id: &str) -> Result<()> {
        self.project.outdent(parse_id(id)?)?;
        self.changed();
        Ok(())
    }

    pub fn trash(&mut self, id: &str) -> Result<()> {
        self.project.trash(parse_id(id)?)?;
        self.changed();
        Ok(())
    }

    pub fn empty_trash(&mut self) -> usize {
        let n = self.project.empty_trash().len();
        self.changed();
        n
    }

    pub fn duplicate(&mut self, id: &str) -> Result<String> {
        let id = self.project.duplicate(parse_id(id)?)?;
        self.changed();
        Ok(id.to_string())
    }

    pub fn split(&mut self, id: &str, char_offset: i32, title: &str) -> Result<String> {
        let title = if title.trim().is_empty() {
            "Untitled"
        } else {
            title
        };
        let id = self
            .project
            .split(parse_id(id)?, char_offset.max(0) as usize, title)?;
        self.changed();
        Ok(id.to_string())
    }

    /// Merge `id` with its next sibling.
    pub fn merge_with_next(&mut self, id: &str) -> Result<()> {
        let id = parse_id(id)?;
        let parent = self
            .project
            .node(id)?
            .parent
            .ok_or_else(|| Error::Invalid("root".into()))?;
        let idx = self.project.index_in_parent(id)?;
        let next = *self
            .project
            .node(parent)?
            .children
            .get(idx + 1)
            .ok_or_else(|| Error::Invalid("nothing below to merge with".into()))?;
        self.project.merge(&[id, next])?;
        self.changed();
        Ok(())
    }

    pub fn root_id(&self, role: &str) -> Result<String> {
        let role = RootRole::ALL
            .into_iter()
            .find(|r| r.as_str() == role)
            .ok_or_else(|| Error::Invalid(format!("no section {role}")))?;
        Ok(self.project.root(role).to_string())
    }

    // ----- labels & statuses ---------------------------------------------

    pub fn labels(&self) -> Value {
        json!({"labels": self.project.labels, "statuses": self.project.statuses})
    }

    pub fn upsert_label(&mut self, id: &str, name: &str, color: &str) -> Result<String> {
        let id = opt_id(id)?.unwrap_or_else(Uuid::new_v4);
        let l = Label {
            id,
            name: name.trim().into(),
            color: color.into(),
        };
        match self.project.labels.iter_mut().find(|x| x.id == id) {
            Some(x) => *x = l,
            None => self.project.labels.push(l),
        }
        self.changed();
        Ok(id.to_string())
    }

    pub fn remove_label(&mut self, id: &str) -> Result<()> {
        let id = parse_id(id)?;
        self.project.labels.retain(|l| l.id != id);
        for n in self.project.nodes.values_mut() {
            if n.label == Some(id) {
                n.label = None;
            }
        }
        self.changed();
        Ok(())
    }

    pub fn upsert_status(&mut self, id: &str, name: &str) -> Result<String> {
        let id = opt_id(id)?.unwrap_or_else(Uuid::new_v4);
        let s = Status {
            id,
            name: name.trim().into(),
        };
        match self.project.statuses.iter_mut().find(|x| x.id == id) {
            Some(x) => *x = s,
            None => self.project.statuses.push(s),
        }
        self.changed();
        Ok(id.to_string())
    }

    pub fn remove_status(&mut self, id: &str) -> Result<()> {
        let id = parse_id(id)?;
        self.project.statuses.retain(|s| s.id != id);
        for n in self.project.nodes.values_mut() {
            if n.status == Some(id) {
                n.status = None;
            }
        }
        self.changed();
        Ok(())
    }

    // ----- project metadata, search, stats, compile ------------------------

    pub fn meta(&self) -> Value {
        json!({
            "title": self.project.meta.title,
            "author": self.project.meta.author,
            "path": self.dir,
            "dirty": self.dirty,
            "keywords": self.project.all_keywords(),
        })
    }

    pub fn set_meta(&mut self, title: &str, author: &str) {
        if !title.trim().is_empty() {
            self.project.meta.title = title.trim().into();
        }
        self.project.meta.author = author.trim().into();
        self.changed();
    }

    pub fn search(&self, q: &str) -> Value {
        json!(search::search(&self.project, q))
    }

    pub fn replace_all(&mut self, find: &str, rep: &str) -> Value {
        let (docs, n) = search::replace_all(&mut self.project, find, rep);
        if n > 0 {
            self.changed();
        }
        json!({"documents": docs, "replacements": n})
    }

    pub fn stats(&self, today: Option<NaiveDate>) -> Value {
        let today = today.unwrap_or_else(|| Local::now().date_naive());
        json!(self.project.stats.summary(&self.project, today))
    }

    /// Save a finished sprint: `minutes` written, net `words`, optional goal.
    pub fn record_sprint(&mut self, minutes: f64, words: i64, goal: i64) -> Result<()> {
        if !(minutes > 0.0 && minutes.is_finite()) {
            return Err(Error::Invalid("a sprint needs a positive length".into()));
        }
        let started =
            chrono::Utc::now() - chrono::Duration::milliseconds((minutes * 60_000.0) as i64);
        self.project.stats.add_sprint(crate::stats::Sprint {
            started,
            minutes,
            words,
            goal: (goal > 0).then_some(goal as u32),
        });
        self.changed();
        Ok(())
    }

    pub fn sprints(&self) -> Value {
        json!(self.project.stats.sprint_summary(10))
    }

    /// Record today's manuscript and project word totals for the history.
    fn note_totals(&mut self) {
        let today = Local::now().date_naive();
        let s = self.project.stats.summary(&self.project, today);
        self.project
            .stats
            .note_totals(today, s.manuscript_words as u64, s.project_words as u64);
    }

    /// Word history for the chart. Empty `from` means the first recorded day
    /// (or 30 days ago), empty `to` today; `bucket` is day / week / month /
    /// year, or anything else to choose by span.
    pub fn stats_history(&self, from: &str, to: &str, bucket: &str) -> Value {
        let today = Local::now().date_naive();
        let parse = |s: &str| NaiveDate::parse_from_str(s.trim(), "%Y-%m-%d").ok();
        let mut stats = self.project.stats.clone();
        // Include unsaved progress for today.
        let s = stats.summary(&self.project, today);
        stats.note_totals(today, s.manuscript_words as u64, s.project_words as u64);
        let to = parse(to).unwrap_or(today);
        let from = parse(from)
            .or_else(|| stats.first_day())
            .unwrap_or(today - chrono::Duration::days(29));
        let bucket = crate::stats::Bucket::parse(bucket, from.min(to), from.max(to));
        json!(stats.range_history(from, to, bucket))
    }

    pub fn set_targets(&mut self, manuscript: i32, session: i32, deadline: &str) {
        let s = &mut self.project.stats;
        s.manuscript_target = (manuscript > 0).then_some(manuscript as u32);
        s.session_target = (session > 0).then_some(session as u32);
        s.deadline = NaiveDate::parse_from_str(deadline.trim(), "%Y-%m-%d").ok();
        self.changed();
    }

    pub fn compile(&self, opts_json: &str) -> Result<String> {
        let opts: CompileOptions = if opts_json.trim().is_empty() {
            CompileOptions::default()
        } else {
            serde_json::from_str(opts_json)?
        };
        Ok(compile::compile(&self.project, &opts))
    }

    pub fn export(&self, path: &Path, opts_json: &str) -> Result<PathBuf> {
        let opts: CompileOptions = if opts_json.trim().is_empty() {
            CompileOptions::default()
        } else {
            serde_json::from_str(opts_json)?
        };
        if opts.format == compile::Format::Pdf {
            return Err(Error::Invalid(
                "PDF is written by the app, not the core".into(),
            ));
        }
        let mut path = path.to_path_buf();
        if path.extension().is_none() {
            path.set_extension(opts.format.extension());
        }
        std::fs::write(&path, compile::compile_file(&self.project, &opts))?;
        Ok(path)
    }

    // ----- snapshots --------------------------------------------------------

    pub fn snapshots(&self, id: &str) -> Result<Value> {
        Ok(json!(storage::list_snapshots(&self.dir, parse_id(id)?)?))
    }

    pub fn take_snapshot(&self, id: &str, title: &str) -> Result<()> {
        let id = parse_id(id)?;
        storage::take_snapshot(&self.dir, id, title, self.project.text(id))?;
        Ok(())
    }

    /// Restore a snapshot, first snapshotting the current text so nothing is
    /// ever lost.
    pub fn restore_snapshot(&mut self, id: &str, snap: &str) -> Result<()> {
        let nid = parse_id(id)?;
        let sid = parse_id(snap)?;
        let snaps = storage::list_snapshots(&self.dir, nid)?;
        let s = snaps
            .into_iter()
            .find(|s| s.id == sid)
            .ok_or_else(|| Error::Invalid("no such snapshot".into()))?;
        storage::take_snapshot(&self.dir, nid, "Before restoring", self.project.text(nid))?;
        self.set_text(id, &s.text)?;
        Ok(())
    }

    /// Compare two versions of a document side by side. `old` and `new` are
    /// snapshot ids; an empty id means the current text.
    pub fn compare_snapshots(&self, id: &str, old: &str, new: &str) -> Result<Value> {
        let nid = parse_id(id)?;
        let snaps = storage::list_snapshots(&self.dir, nid)?;
        let version = |sid: &str| -> Result<(String, String)> {
            match opt_id(sid)? {
                None => Ok(("Current text".into(), self.project.text(nid).to_string())),
                Some(sid) => snaps
                    .iter()
                    .find(|s| s.id == sid)
                    .map(|s| (s.title.clone(), s.text.clone()))
                    .ok_or_else(|| Error::Invalid("no such snapshot".into())),
            }
        };
        let (old_title, old_text) = version(old)?;
        let (new_title, new_text) = version(new)?;
        let mut v = json!(crate::diff::compare(&old_text, &new_text));
        v["left_title"] = json!(old_title);
        v["right_title"] = json!(new_title);
        Ok(v)
    }

    pub fn delete_snapshot(&self, id: &str, snap: &str) -> Result<()> {
        storage::delete_snapshot(&self.dir, parse_id(id)?, parse_id(snap)?)
    }

    /// Words in the names of characters, places and timeline tracks, for
    /// the spell checker.
    pub fn project_name_words(&self) -> std::collections::HashSet<String> {
        let p = &self.project;
        p.nodes
            .values()
            .filter(|n| matches!(n.kind, NodeKind::Character | NodeKind::Place))
            .map(|n| n.title.as_str())
            .chain(p.timeline.tracks.iter().map(|t| t.name.as_str()))
            .flat_map(|t| t.split(|c: char| !(c.is_alphanumeric() || c == '\'' || c == '’')))
            .filter(|w| !w.is_empty())
            .map(|w| w.replace('’', "'"))
            .collect()
    }

    // ----- relationship map -----------------------------------------------

    /// Everyone on the map (characters not in the trash, plus anything else
    /// that has a relationship) and the relationships between them.
    pub fn relations(&self) -> Value {
        let p = &self.project;
        let r = &p.relations;
        let in_trash = |id: &NodeId| {
            p.section_of(*id)
                .map(|s| s == RootRole::Trash)
                .unwrap_or(true)
        };
        let linked: std::collections::HashSet<NodeId> =
            r.links.iter().flat_map(|l| [l.from, l.to]).collect();
        let people: Vec<Value> = p
            .subtree(p.root(RootRole::Characters))
            .into_iter()
            .filter(|id| p.nodes[id].kind == NodeKind::Character)
            .chain(linked.iter().copied().filter(|id| {
                p.nodes
                    .get(id)
                    .is_some_and(|n| n.kind != NodeKind::Character)
            }))
            .filter(|id| !in_trash(id))
            .map(|id| {
                let n = &p.nodes[&id];
                let pos = r.positions.get(&id);
                json!({
                    "id": id,
                    "title": n.title,
                    "kind": n.kind,
                    "synopsis": n.synopsis,
                    "x": pos.map(|q| q[0]),
                    "y": pos.map(|q| q[1]),
                })
            })
            .collect();
        let shown: std::collections::HashSet<String> = people
            .iter()
            .filter_map(|v| v["id"].as_str().map(String::from))
            .collect();
        let links: Vec<&crate::relations::Relationship> = r
            .links
            .iter()
            .filter(|l| shown.contains(&l.from.to_string()) && shown.contains(&l.to.to_string()))
            .collect();
        json!({ "people": people, "links": links })
    }

    pub fn add_relation(&mut self, from: &str, to: &str, label: &str) -> Result<String> {
        let (from, to) = (parse_id(from)?, parse_id(to)?);
        self.project.node(from)?;
        self.project.node(to)?;
        let id = self.project.relations.add(from, to, label)?;
        self.changed();
        Ok(id.to_string())
    }

    pub fn update_relation(&mut self, id: &str, label: &str, notes: &str) -> Result<()> {
        self.project.relations.update(parse_id(id)?, label, notes)?;
        self.changed();
        Ok(())
    }

    pub fn reverse_relation(&mut self, id: &str) -> Result<()> {
        self.project.relations.reverse(parse_id(id)?)?;
        self.changed();
        Ok(())
    }

    pub fn remove_relation(&mut self, id: &str) -> Result<()> {
        self.project.relations.remove(parse_id(id)?);
        self.changed();
        Ok(())
    }

    pub fn place_on_map(&mut self, id: &str, x: f64, y: f64) -> Result<()> {
        let id = parse_id(id)?;
        self.project.node(id)?;
        self.project.relations.place(id, x, y);
        self.changed();
        Ok(())
    }

    // ----- timeline -------------------------------------------------------

    pub fn timeline(&self) -> Value {
        let t = &self.project.timeline;
        let p = &self.project;
        let scenes: Vec<Value> = p
            .subtree(p.root(RootRole::Manuscript))
            .into_iter()
            .skip(1)
            .filter(|id| p.nodes[id].kind != NodeKind::Folder)
            .map(|id| json!({"id": id, "title": p.nodes[&id].title}))
            .collect();
        let chronology: Vec<Value> = t
            .chronology()
            .into_iter()
            .filter_map(|(id, at)| {
                p.nodes
                    .get(&id)
                    .map(|n| json!({"id": id, "title": n.title, "at": at}))
            })
            .collect();
        let (lo, hi) = t.range().unwrap_or((0, 30));
        json!({
            "unit_name": t.unit_name,
            "calendar_start": t.calendar_start,
            "tracks": t.tracks,
            "events": t.events,
            "markers": t.markers,
            "problems": t.problems(),
            "range": [lo, hi],
            "scenes": scenes,
            "chronology": chronology,
        })
    }

    pub fn set_timeline_settings(&mut self, unit_name: &str, calendar_start: &str) {
        let t = &mut self.project.timeline;
        if !unit_name.trim().is_empty() {
            t.unit_name = unit_name.trim().into();
        }
        t.calendar_start = NaiveDate::parse_from_str(calendar_start.trim(), "%Y-%m-%d").ok();
        self.changed();
    }

    pub fn add_track(&mut self, name: &str, kind: &str) -> Result<String> {
        let kind: TrackKind = serde_json::from_value(json!(kind)).unwrap_or_default();
        let name = if name.trim().is_empty() {
            "New Track"
        } else {
            name.trim()
        };
        let id = self.project.timeline.add_track(name, kind);
        self.changed();
        Ok(id.to_string())
    }

    pub fn update_track(&mut self, track_json: &str) -> Result<()> {
        let t: Track = serde_json::from_str(track_json)?;
        self.project.timeline.upsert_track(t);
        self.changed();
        Ok(())
    }

    pub fn remove_track(&mut self, id: &str) -> Result<()> {
        self.project.timeline.remove_track(parse_id(id)?);
        self.changed();
        Ok(())
    }

    pub fn move_track(&mut self, id: &str, delta: i32) -> Result<()> {
        self.project.timeline.move_track(parse_id(id)?, delta);
        self.changed();
        Ok(())
    }

    pub fn add_event(
        &mut self,
        title: &str,
        track: &str,
        start: i64,
        duration: i64,
    ) -> Result<String> {
        let title = if title.trim().is_empty() {
            "New Event"
        } else {
            title.trim()
        };
        let id = self
            .project
            .timeline
            .add_event(title, parse_id(track)?, start, duration)?;
        self.changed();
        Ok(id.to_string())
    }

    pub fn update_event(&mut self, event_json: &str) -> Result<()> {
        let e: Event = serde_json::from_str(event_json)?;
        self.project.timeline.upsert_event(e)?;
        self.changed();
        Ok(())
    }

    pub fn remove_event(&mut self, id: &str) -> Result<()> {
        self.project.timeline.remove_event(parse_id(id)?);
        self.changed();
        Ok(())
    }

    /// Reposition an event; with `cascade`, push dependants later as needed.
    pub fn move_event(
        &mut self,
        id: &str,
        start: i64,
        duration: i64,
        cascade: bool,
    ) -> Result<usize> {
        let id = parse_id(id)?;
        self.project.timeline.move_event(id, start, duration)?;
        let moved = if cascade {
            self.project.timeline.cascade(id)
        } else {
            0
        };
        self.changed();
        Ok(moved)
    }

    pub fn add_marker(&mut self, at: i64, title: &str) -> String {
        let id = self.project.timeline.add_marker(at, title);
        self.changed();
        id.to_string()
    }

    pub fn remove_marker(&mut self, id: &str) -> Result<()> {
        self.project.timeline.remove_marker(parse_id(id)?);
        self.changed();
        Ok(())
    }

    /// Ensure every character / place sheet in the binder has a track.
    /// Returns how many tracks were created.
    pub fn sync_tracks(&mut self) -> usize {
        let p = &mut self.project;
        let mut created = 0;
        for (role, kind) in [
            (RootRole::Characters, TrackKind::Character),
            (RootRole::Places, TrackKind::Place),
        ] {
            let root = p.root(role);
            let items: Vec<(NodeId, String)> = p
                .subtree(root)
                .into_iter()
                .skip(1)
                .filter(|id| p.nodes[id].kind != NodeKind::Folder)
                .map(|id| (id, p.nodes[&id].title.clone()))
                .collect();
            for (id, title) in items {
                if let Some(t) = p
                    .timeline
                    .tracks
                    .iter_mut()
                    .find(|t| t.linked_node == Some(id))
                {
                    t.name = title;
                } else {
                    let tid = p.timeline.add_track(&title, kind);
                    p.timeline
                        .tracks
                        .iter_mut()
                        .find(|t| t.id == tid)
                        .unwrap()
                        .linked_node = Some(id);
                    created += 1;
                }
            }
        }
        self.changed();
        created
    }

    /// Create a manuscript scene for an event (or return the one already
    /// linked) so timeline planning flows straight into writing.
    pub fn scene_for_event(&mut self, event: &str) -> Result<String> {
        let eid = parse_id(event)?;
        let ev = self
            .project
            .timeline
            .event(eid)
            .cloned()
            .ok_or_else(|| Error::Invalid("no such event".into()))?;
        if let Some(n) = ev
            .linked_nodes
            .iter()
            .find(|n| self.project.nodes.contains_key(n))
        {
            return Ok(n.to_string());
        }
        let ms = self.project.root(RootRole::Manuscript);
        let id = self.project.add_node(ms, None, NodeKind::Text, &ev.title)?;
        {
            let n = self.project.node_mut(id)?;
            n.synopsis = ev.notes.clone();
        }
        let mut ev = ev;
        ev.linked_nodes.push(id);
        self.project.timeline.upsert_event(ev)?;
        self.changed();
        Ok(id.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compare_snapshot_with_current() {
        let tmp = tempfile::tempdir().unwrap();
        let mut s = Session::create(tmp.path(), "Cmp", "").unwrap();
        let ms = s.root_id("manuscript").unwrap();
        let id = s.add(&ms, "", "Scene", true).unwrap();
        s.set_text(&id, "It was a dark night.").unwrap();
        s.take_snapshot(&id, "v1").unwrap();
        s.set_text(&id, "It was a dark and stormy night.").unwrap();
        s.take_snapshot(&id, "v2").unwrap();
        let snaps = s.snapshots(&id).unwrap();
        let v1 = snaps
            .as_array()
            .unwrap()
            .iter()
            .find(|x| x["title"] == "v1")
            .unwrap()["id"]
            .as_str()
            .unwrap()
            .to_string();
        let c = s.compare_snapshots(&id, &v1, "").unwrap();
        assert_eq!(c["left_title"], "v1");
        assert_eq!(c["right_title"], "Current text");
        assert_eq!(c["words_added"], 2);
        assert_eq!(c["rows"][0]["kind"], "changed");
        let v2 = snaps[0]["id"].as_str().unwrap();
        assert_eq!(s.compare_snapshots(&id, v2, "").unwrap()["words_added"], 0);
        assert!(s
            .compare_snapshots(&id, &Uuid::new_v4().to_string(), "")
            .is_err());
    }

    #[test]
    fn imported_files() {
        let tmp = tempfile::tempdir().unwrap();
        let src = tmp.path().join("Map of the Island.PNG");
        std::fs::write(&src, b"not really a png").unwrap();
        let mut s = Session::create(tmp.path(), "Isle", "").unwrap();
        assert!(s.import_file("", &tmp.path().join("missing.png")).is_err());

        let id = s.import_file("", &src).unwrap();
        let info = s.node_info(&id).unwrap();
        assert_eq!(info["title"], "Map of the Island");
        assert_eq!(info["kind"], "research");
        assert_eq!(info["section"], "research");
        assert_eq!(info["file"]["kind"], "image");
        assert_eq!(info["file"]["exists"], true);
        let url = info["file"]["url"].as_str().unwrap();
        assert!(url.starts_with("file://") && url.ends_with(".png"));

        // The reference survives a reload, and Save As takes the file along.
        s.save().unwrap();
        let mut s = Session::open(&s.dir).unwrap();
        assert_eq!(s.node_info(&id).unwrap()["file"]["exists"], true);
        let other = tmp.path().join("elsewhere");
        std::fs::create_dir(&other).unwrap();
        s.save_as(&other, "Isle 2").unwrap();
        let info = s.node_info(&id).unwrap();
        assert!(info["file"]["url"].as_str().unwrap().contains("elsewhere"));
        assert_eq!(info["file"]["exists"], true);
    }

    #[test]
    fn end_to_end() {
        let tmp = tempfile::tempdir().unwrap();
        let mut s = Session::create(tmp.path(), "Saga", "Me").unwrap();
        assert!(Session::create(tmp.path(), "Saga", "Me").is_err());
        let ms = s.root_id("manuscript").unwrap();
        let ch = s.add(&ms, "folder", "Part One", true).unwrap();
        let sc = s.add(&ch, "", "", true).unwrap();
        s.set_text(&sc, "Once upon a time there were dragons.")
            .unwrap();
        s.set_field(&sc, "synopsis", "Opening").unwrap();
        s.set_field(&sc, "keywords", "dragons, , opening").unwrap();
        s.set_field(&sc, "field:POV", "Ana").unwrap();
        assert!(s.set_field(&sc, "title", "  ").is_err());
        let info = s.node_info(&sc).unwrap();
        assert_eq!(info["words"], 7);
        assert_eq!(info["keywords"], json!(["dragons", "opening"]));
        assert_eq!(info["breadcrumbs"], json!(["Manuscript", "Part One"]));
        assert_eq!(info["fields"]["POV"], "Ana");

        // Characters -> tracks -> events -> scenes.
        let chars = s.root_id("characters").unwrap();
        let ana = s.add(&chars, "", "Ana", true).unwrap();
        assert_eq!(s.sync_tracks(), 1);
        assert_eq!(s.sync_tracks(), 0);
        let tl = s.timeline();
        let track = tl["tracks"][0]["id"].as_str().unwrap().to_string();
        assert_eq!(tl["tracks"][0]["linked_node"], json!(ana));
        let ev = s.add_event("Dragon attack", &track, 3, 2).unwrap();
        let scene = s.scene_for_event(&ev).unwrap();
        assert_eq!(s.scene_for_event(&ev).unwrap(), scene);
        assert_eq!(s.timeline()["chronology"][0]["title"], "Dragon attack");

        s.take_snapshot(&sc, "v1").unwrap();
        s.set_text(&sc, "Rewritten.").unwrap();
        let snap = s.snapshots(&sc).unwrap()[0]["id"]
            .as_str()
            .unwrap()
            .to_string();
        s.restore_snapshot(&sc, &snap).unwrap();
        assert_eq!(s.text(&sc).unwrap(), "Once upon a time there were dragons.");
        assert_eq!(s.snapshots(&sc).unwrap().as_array().unwrap().len(), 2);

        let stats = s.stats(None);
        assert_eq!(stats["manuscript_words"], 7);
        assert_eq!(stats["words_today"], 7);

        s.save().unwrap();
        let s2 = Session::open(&s.dir).unwrap();
        assert_eq!(
            s2.text(&sc).unwrap(),
            "Once upon a time there were dragons."
        );
        assert_eq!(s2.project.timeline.events.len(), 1);

        let out = tmp.path().join("book");
        let written = s.export(&out, r#"{"format":"html"}"#).unwrap();
        assert!(written.ends_with("book.html"));
        assert!(std::fs::read_to_string(written)
            .unwrap()
            .contains("dragons"));
    }

    #[test]
    fn drop_positions() {
        let tmp = tempfile::tempdir().unwrap();
        let mut s = Session::create(tmp.path(), "D", "").unwrap();
        let ms = s.root_id("manuscript").unwrap();
        let a = s.add(&ms, "text", "A", true).unwrap();
        let b = s.add(&ms, "text", "B", true).unwrap();
        s.drop_on(&b, &a, "before").unwrap();
        let kids: Vec<String> = s
            .children(&ms)
            .unwrap()
            .as_array()
            .unwrap()
            .iter()
            .map(|c| c["title"].as_str().unwrap().to_string())
            .collect();
        assert_eq!(kids, vec!["Chapter 1", "B", "A"]);
        s.drop_on(&b, &a, "inside").unwrap();
        assert_eq!(s.node_info(&a).unwrap()["child_count"], 1);
    }

    #[test]
    fn comments_are_listed_and_not_compiled() {
        let tmp = tempfile::tempdir().unwrap();
        let mut s = Session::create(tmp.path(), "C", "").unwrap();
        let ms = s.root_id("manuscript").unwrap();
        let a = s.add(&ms, "text", "A", true).unwrap();
        s.set_text(&a, "She left. {>>Too abrupt?<<} The door shut.")
            .unwrap();
        let list = s.comments(&ms).unwrap();
        assert_eq!(list[0]["text"], "Too abrupt?");
        assert_eq!(list[0]["title"], "A");
        assert_eq!(list[0]["start"], 10);
        assert_eq!(s.node_info(&a).unwrap()["words"], 5);
        let html = crate::compile::compile(
            &s.project,
            &crate::compile::CompileOptions {
                format: crate::compile::Format::Html,
                ..Default::default()
            },
        );
        assert!(html.contains("She left. The door shut."));
        assert!(!html.contains("abrupt"));
    }

    #[test]
    fn zip_backup_has_the_project_but_not_the_lock() {
        let tmp = tempfile::tempdir().unwrap();
        let mut s = Session::create(tmp.path(), "Zip Me", "").unwrap();
        let ms = s.root_id("manuscript").unwrap();
        let a = s.add(&ms, "text", "A", true).unwrap();
        s.set_text(&a, "Packed text.").unwrap();
        s.take_snapshot(&a, "v1").unwrap();
        let out = tempfile::tempdir().unwrap();
        let r = s.backup_zip(out.path()).unwrap();
        let path = std::path::PathBuf::from(r["path"].as_str().unwrap());
        let name = path.file_name().unwrap().to_string_lossy().into_owned();
        assert!(
            name.starts_with("Zip Me backup ") && name.ends_with(".zip"),
            "{name}"
        );
        let bytes = std::fs::read(&path).unwrap();
        let has = |needle: &str| bytes.windows(needle.len()).any(|w| w == needle.as_bytes());
        assert!(has("Zip Me.wordloom/project.json"));
        assert!(has("Zip Me.wordloom/content/"));
        assert!(has("Zip Me.wordloom/snapshots/"));
        assert!(has("Packed text."));
        assert!(!has(".wordloom.lock"));
        assert!(!has("/backups/"));
        assert!(r["files"].as_u64().unwrap() >= 3);
        // An explicit .zip path is used as given.
        let named = out.path().join("mine.zip");
        s.backup_zip(&named).unwrap();
        assert!(named.is_file());
    }
}
