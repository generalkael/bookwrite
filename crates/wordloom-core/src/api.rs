//! String-in / JSON-out dispatcher used by the UI.
//!
//! The QML front end calls a single `call(method, argsJson)` entry point; this
//! module routes it to [`Session`]. Every call returns
//! `{"ok": true, "result": …}` or `{"ok": false, "error": "…"}` and reports
//! whether project data changed, so the UI knows when to refresh.

use std::path::{Path, PathBuf};

use serde_json::{json, Value};

use crate::history::Checkpoint;
use crate::{recent, Error, Result, Session};

pub struct App {
    pub session: Option<Session>,
    /// Where the recent-projects list is stored.
    pub recent_file: PathBuf,
}

/// Outcome of one call.
pub struct Reply {
    pub json: String,
    /// Project data changed (UI should refresh views).
    pub mutated: bool,
    /// The error message, when the call failed.
    pub error: Option<String>,
}

/// Turn a QML/Qt URL (`file:///…`) or a plain path into a filesystem path.
pub fn to_path(s: &str) -> PathBuf {
    let s = s.trim();
    if s.starts_with("file:") {
        if let Ok(u) = url::Url::parse(s) {
            if let Ok(p) = u.to_file_path() {
                return p;
            }
        }
    }
    PathBuf::from(s)
}

struct Args<'a>(&'a [Value]);

impl Args<'_> {
    fn str(&self, i: usize) -> &str {
        self.0.get(i).and_then(Value::as_str).unwrap_or("")
    }
    fn int(&self, i: usize) -> i64 {
        match self.0.get(i) {
            Some(Value::Number(n)) => n.as_f64().map(|f| f.round() as i64).unwrap_or(0),
            Some(Value::String(s)) => s.trim().parse().unwrap_or(0),
            _ => 0,
        }
    }
    fn float(&self, i: usize) -> f64 {
        match self.0.get(i) {
            Some(Value::Number(n)) => n.as_f64().unwrap_or(0.0),
            Some(Value::String(s)) => s.trim().parse().unwrap_or(0.0),
            _ => 0.0,
        }
    }
    fn bool(&self, i: usize) -> bool {
        match self.0.get(i) {
            Some(Value::Bool(b)) => *b,
            Some(Value::String(s)) => s == "true",
            _ => false,
        }
    }
    /// An argument that may be a JSON object or a JSON string; returned as a
    /// JSON string.
    fn json(&self, i: usize) -> String {
        match self.0.get(i) {
            Some(Value::String(s)) => s.clone(),
            Some(v) => v.to_string(),
            None => String::new(),
        }
    }
}

/// Methods that only read state.
const READ_ONLY: &[&str] = &[
    "binder",
    "nodeInfo",
    "exists",
    "children",
    "text",
    "labels",
    "meta",
    "search",
    "stats",
    "compile",
    "snapshots",
    "compareSnapshots",
    "relations",
    "timeline",
    "recent",
    "rootId",
    "isOpen",
    "export",
    "takeSnapshot",
    "deleteSnapshot",
    "history",
];

/// Methods that change data but should not trigger a UI refresh (the
/// editor already shows the new state, and refreshing would move the caret).
const QUIET: &[&str] = &["setText"];

/// The undo-menu name for a call, and a key that lets repeats of the same
/// edit merge into one step. `None` means the call isn't undoable: it only
/// reads, is editor typing (which has the editor's own undo), or is view
/// state such as expanding a folder.
fn undo_label(method: &str, a: &Args) -> Option<(String, Option<String>)> {
    let label = match method {
        "setField" => {
            let field = a.str(1);
            let key = Some(format!("{}:{field}", a.str(0)));
            let label = match field {
                "title" => "Rename".to_string(),
                "synopsis" => "Edit Synopsis".into(),
                "notes" => "Edit Notes".into(),
                "label" => "Change Label".into(),
                "status" => "Change Status".into(),
                "keywords" => "Edit Keywords".into(),
                "include_in_compile" => "Include in Compile".into(),
                "target_words" => "Set Word Target".into(),
                "kind" => "Convert".into(),
                f => match f.strip_prefix("field:") {
                    Some(k) => format!("Edit {k}"),
                    None => "Edit".into(),
                },
            };
            return Some((label, key));
        }
        "setMeta" => "Project Details",
        "add" => "Add Item",
        "importFile" => "Import File",
        "addRelation" => "Add Relationship",
        "updateRelation" => {
            return Some((
                "Edit Relationship".into(),
                Some(format!("rel:{}", a.str(0))),
            ));
        }
        "reverseRelation" => "Reverse Relationship",
        "removeRelation" => "Delete Relationship",
        "placeOnMap" => {
            return Some(("Move on Map".into(), Some(format!("map:{}", a.str(0)))));
        }
        "move" | "dropOn" | "shift" => "Move",
        "indent" => "Indent",
        "outdent" => "Outdent",
        "trash" => "Move to Trash",
        "emptyTrash" => "Empty Trash",
        "duplicate" => "Duplicate",
        "split" => "Split",
        "mergeWithNext" => "Merge",
        "upsertLabel" | "removeLabel" => "Edit Labels",
        "upsertStatus" | "removeStatus" => "Edit Statuses",
        "replaceAll" => "Replace All",
        "setTargets" => "Set Targets",
        "restoreSnapshot" => "Restore Snapshot",
        "setTimelineSettings" => "Timeline Settings",
        "addTrack" => "Add Track",
        "updateTrack" => "Edit Track",
        "removeTrack" => "Delete Track",
        "moveTrack" => "Move Track",
        "addEvent" => "Add Event",
        "updateEvent" => "Edit Event",
        "removeEvent" => "Delete Event",
        "moveEvent" => "Move Event",
        "addMarker" => "Add Marker",
        "removeMarker" => "Delete Marker",
        "syncTracks" => "Sync Cast",
        "sceneForEvent" => "Write This Scene",
        _ => return None,
    };
    Some((label.to_string(), None))
}

impl App {
    pub fn new(recent_file: PathBuf) -> Self {
        Self {
            session: None,
            recent_file,
        }
    }

    pub fn call(&mut self, method: &str, args_json: &str) -> Reply {
        let args: Vec<Value> = if args_json.trim().is_empty() {
            Vec::new()
        } else {
            match serde_json::from_str::<Value>(args_json) {
                Ok(Value::Array(a)) => a,
                Ok(v) => vec![v],
                Err(e) => return err_reply(&Error::Json(e)),
            }
        };
        let a = Args(&args);
        let undoable = undo_label(method, &a);
        let before = match (&undoable, &self.session) {
            (Some(_), Some(s)) => Some(Checkpoint::take(&s.project)),
            _ => None,
        };
        let result = self.dispatch(method, &a);
        if let (Ok(_), Some(before), Some((label, key))) = (&result, before, undoable) {
            if let Some(s) = self.session.as_mut() {
                s.history.record(before, &s.project, &label, key);
            }
        }
        match result {
            Ok(v) => Reply {
                json: json!({"ok": true, "result": v}).to_string(),
                mutated: !READ_ONLY.contains(&method) && !QUIET.contains(&method),
                error: None,
            },
            Err(e) => err_reply(&e),
        }
    }

    fn s(&mut self) -> Result<&mut Session> {
        self.session
            .as_mut()
            .ok_or_else(|| Error::Invalid("no project is open".into()))
    }

    fn opened(&mut self, s: Session) -> Result<Value> {
        let _ = recent::remember(&self.recent_file, &s.dir, &s.project.meta.title);
        let meta = s.meta();
        self.session = Some(s);
        Ok(meta)
    }

    fn dispatch(&mut self, m: &str, a: &Args) -> Result<Value> {
        Ok(match m {
            // --- lifecycle ---
            "recent" => json!(recent::load(&self.recent_file)),
            "isOpen" => json!(self.session.is_some()),
            "newProject" => {
                let s = Session::create(&to_path(a.str(0)), a.str(1), a.str(2))?;
                self.opened(s)?
            }
            "newDemoProject" => {
                let parent = to_path(a.str(0));
                let existing =
                    crate::storage::new_bundle_path(&parent, "The Lighthouse Keeper (Sample)");
                let s = if crate::storage::is_project(&existing) {
                    Session::open(&existing)?
                } else {
                    std::fs::create_dir_all(&parent)?;
                    crate::demo::create(&parent)?
                };
                self.opened(s)?
            }
            "openProject" => {
                let s = Session::open(&to_path(a.str(0)))?;
                self.opened(s)?
            }
            "save" => {
                self.s()?.save()?;
                json!(true)
            }
            "saveAs" => {
                let (parent, title) = (to_path(a.str(0)), a.str(1).to_string());
                let s = self.s()?;
                s.save_as(&parent, &title)?;
                let (dir, t) = (s.dir.clone(), s.project.meta.title.clone());
                let _ = recent::remember(&self.recent_file, &dir, &t);
                self.s()?.meta()
            }
            "close" => {
                if let Some(mut s) = self.session.take() {
                    if s.dirty {
                        s.save()?;
                    }
                }
                json!(true)
            }
            // --- undo ---
            "undo" => json!(self.s()?.undo()),
            "redo" => json!(self.s()?.redo()),
            "history" => {
                let h = &self.s()?.history;
                json!({"undo": h.undo_label(), "redo": h.redo_label()})
            }
            "meta" => self.s()?.meta(),
            "setMeta" => {
                self.s()?.set_meta(a.str(0), a.str(1));
                json!(true)
            }
            // --- binder ---
            "binder" => self.s()?.binder(),
            "rootId" => json!(self.s()?.root_id(a.str(0))?),
            "toggleExpanded" => unit(self.s()?.toggle_expanded(a.str(0)))?,
            "setAllExpanded" => {
                self.s()?.set_all_expanded(a.bool(0));
                json!(true)
            }
            "nodeInfo" => self.s()?.node_info(a.str(0))?,
            "exists" => {
                let id = crate::session::parse_id(a.str(0)).ok();
                json!(id.is_some_and(|id| self.s().is_ok_and(|s| s.project.nodes.contains_key(&id))))
            }
            "children" => self.s()?.children(a.str(0))?,
            "text" => json!(self.s()?.text(a.str(0))?),
            "setText" => unit(self.s()?.set_text(a.str(0), a.str(1)))?,
            "setField" => {
                let v = match a.0.get(2) {
                    Some(Value::String(s)) => s.clone(),
                    Some(Value::Null) | None => String::new(),
                    Some(v) => v.to_string(),
                };
                unit(self.s()?.set_field(a.str(0), a.str(1), &v))?
            }
            "add" => json!(self.s()?.add(a.str(0), a.str(1), a.str(2), a.bool(3))?),
            "move" => unit(self.s()?.move_node(a.str(0), a.str(1), a.int(2) as i32))?,
            "dropOn" => unit(self.s()?.drop_on(a.str(0), a.str(1), a.str(2)))?,
            "shift" => unit(self.s()?.shift(a.str(0), a.int(1) as i32))?,
            "indent" => unit(self.s()?.indent(a.str(0)))?,
            "outdent" => unit(self.s()?.outdent(a.str(0)))?,
            "trash" => unit(self.s()?.trash(a.str(0)))?,
            "emptyTrash" => json!(self.s()?.empty_trash()),
            "duplicate" => json!(self.s()?.duplicate(a.str(0))?),
            "split" => json!(self.s()?.split(a.str(0), a.int(1) as i32, a.str(2))?),
            "mergeWithNext" => unit(self.s()?.merge_with_next(a.str(0)))?,
            // --- labels/status ---
            "labels" => self.s()?.labels(),
            "upsertLabel" => json!(self.s()?.upsert_label(a.str(0), a.str(1), a.str(2))?),
            "removeLabel" => unit(self.s()?.remove_label(a.str(0)))?,
            "upsertStatus" => json!(self.s()?.upsert_status(a.str(0), a.str(1))?),
            "removeStatus" => unit(self.s()?.remove_status(a.str(0)))?,
            // --- search/stats/compile ---
            "search" => self.s()?.search(a.str(0)),
            "replaceAll" => self.s()?.replace_all(a.str(0), a.str(1)),
            "stats" => self.s()?.stats(None),
            "setTargets" => {
                self.s()?
                    .set_targets(a.int(0) as i32, a.int(1) as i32, a.str(2));
                json!(true)
            }
            "compile" => json!(self.s()?.compile(&a.json(0))?),
            "importFile" => json!(self.s()?.import_file(a.str(0), &to_path(a.str(1)))?),
            "export" => {
                let p = self.s()?.export(&to_path(a.str(0)), &a.json(1))?;
                json!(p)
            }
            // --- snapshots ---
            "snapshots" => self.s()?.snapshots(a.str(0))?,
            "relations" => self.s()?.relations(),
            "addRelation" => json!(self.s()?.add_relation(a.str(0), a.str(1), a.str(2))?),
            "updateRelation" => unit(self.s()?.update_relation(a.str(0), a.str(1), a.str(2)))?,
            "reverseRelation" => unit(self.s()?.reverse_relation(a.str(0)))?,
            "removeRelation" => unit(self.s()?.remove_relation(a.str(0)))?,
            "placeOnMap" => unit(self.s()?.place_on_map(a.str(0), a.float(1), a.float(2)))?,
            "compareSnapshots" => self.s()?.compare_snapshots(a.str(0), a.str(1), a.str(2))?,
            "takeSnapshot" => unit(self.s()?.take_snapshot(a.str(0), a.str(1)))?,
            "restoreSnapshot" => unit(self.s()?.restore_snapshot(a.str(0), a.str(1)))?,
            "deleteSnapshot" => unit(self.s()?.delete_snapshot(a.str(0), a.str(1)))?,
            // --- timeline ---
            "timeline" => self.s()?.timeline(),
            "setTimelineSettings" => {
                self.s()?.set_timeline_settings(a.str(0), a.str(1));
                json!(true)
            }
            "addTrack" => json!(self.s()?.add_track(a.str(0), a.str(1))?),
            "updateTrack" => unit(self.s()?.update_track(&a.json(0)))?,
            "removeTrack" => unit(self.s()?.remove_track(a.str(0)))?,
            "moveTrack" => unit(self.s()?.move_track(a.str(0), a.int(1) as i32))?,
            "addEvent" => json!(self
                .s()?
                .add_event(a.str(0), a.str(1), a.int(2), a.int(3))?),
            "updateEvent" => unit(self.s()?.update_event(&a.json(0)))?,
            "removeEvent" => unit(self.s()?.remove_event(a.str(0)))?,
            "moveEvent" => json!(self
                .s()?
                .move_event(a.str(0), a.int(1), a.int(2), a.bool(3))?),
            "addMarker" => json!(self.s()?.add_marker(a.int(0), a.str(1))),
            "removeMarker" => unit(self.s()?.remove_marker(a.str(0)))?,
            "syncTracks" => json!(self.s()?.sync_tracks()),
            "sceneForEvent" => json!(self.s()?.scene_for_event(a.str(0))?),
            _ => return Err(Error::Invalid(format!("unknown method {m}"))),
        })
    }

    /// Title and dirty flag for window chrome.
    pub fn title(&self) -> String {
        self.session
            .as_ref()
            .map(|s| s.project.meta.title.clone())
            .unwrap_or_default()
    }

    pub fn dirty(&self) -> bool {
        self.session.as_ref().is_some_and(|s| s.dirty)
    }

    /// Labels of the steps Undo and Redo would apply, if any.
    pub fn undo_redo(&self) -> (Option<String>, Option<String>) {
        match &self.session {
            Some(s) => (
                s.history.undo_label().map(str::to_string),
                s.history.redo_label().map(str::to_string),
            ),
            None => (None, None),
        }
    }

    pub fn path(&self) -> Option<&Path> {
        self.session.as_ref().map(|s| s.dir.as_path())
    }
}

fn unit(r: Result<()>) -> Result<Value> {
    r.map(|_| json!(true))
}

fn err_reply(e: &Error) -> Reply {
    Reply {
        json: json!({"ok": false, "error": e.to_string()}).to_string(),
        mutated: false,
        error: Some(e.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ok(r: &Reply) -> Value {
        let v: Value = serde_json::from_str(&r.json).unwrap();
        assert_eq!(v["ok"], true, "{}", r.json);
        v["result"].clone()
    }

    #[test]
    fn dispatch_round_trip() {
        let tmp = tempfile::tempdir().unwrap();
        let mut app = App::new(tmp.path().join("recent.json"));
        let r = app.call("binder", "[]");
        assert!(r.json.contains("no project is open"));
        let url = url::Url::from_file_path(tmp.path()).unwrap().to_string();
        let meta = ok(&app.call("newProject", &json!([url, "Book", "Me"]).to_string()));
        assert_eq!(meta["title"], "Book");
        let ms = ok(&app.call("rootId", r#"["manuscript"]"#));
        let r = app.call("add", &json!([ms, "text", "Intro", true]).to_string());
        assert!(r.mutated);
        let id = ok(&r);
        ok(&app.call("setField", &json!([id, "target_words", 500]).to_string()));
        ok(&app.call("setField", &json!([id, "label", null]).to_string()));
        assert_eq!(
            ok(&app.call("nodeInfo", &json!([id]).to_string()))["target_words"],
            500
        );
        let tr = ok(&app.call("addTrack", r#"["Hero","character"]"#));
        let ev = ok(&app.call("addEvent", &json!(["Call", tr, "2", 3]).to_string()));
        let tl = ok(&app.call("timeline", ""));
        assert_eq!(tl["events"][0]["id"], ev);
        assert_eq!(tl["events"][0]["start"], 2);
        assert!(!app.call("timeline", "").mutated);
        assert!(app.call("bogus", "").json.contains("unknown method"));
        ok(&app.call("close", ""));
        assert_eq!(ok(&app.call("recent", ""))[0]["title"], "Book");
    }

    #[test]
    fn relationships_through_the_api() {
        let tmp = tempfile::tempdir().unwrap();
        let mut app = App::new(tmp.path().join("recent.json"));
        let url = url::Url::from_file_path(tmp.path()).unwrap().to_string();
        ok(&app.call("newProject", &json!([url, "Book", "Me"]).to_string()));
        let chars = ok(&app.call("rootId", r#"["characters"]"#));
        let a = ok(&app.call("add", &json!([chars, "", "Ana", true]).to_string()));
        let b = ok(&app.call("add", &json!([chars, "", "Ben", true]).to_string()));
        let rel = ok(&app.call("addRelation", &json!([a, b, "rivals"]).to_string()));
        let map = ok(&app.call("relations", ""));
        assert_eq!(map["people"].as_array().unwrap().len(), 2);
        assert_eq!(map["links"][0]["label"], "rivals");
        assert_eq!(map["people"][0]["x"], Value::Null);
        // Dragging a card many times is one undo step.
        ok(&app.call("placeOnMap", &json!([a, 10, 20]).to_string()));
        ok(&app.call("placeOnMap", &json!([a, 30.5, 40]).to_string()));
        let info = ok(&app.call("nodeInfo", &json!([b]).to_string()));
        assert_eq!(info["relations"][0]["other_title"], "Ana");
        assert_eq!(info["relations"][0]["outgoing"], false);
        assert_eq!(ok(&app.call("undo", "")), "Move on Map");
        assert_eq!(
            ok(&app.call("relations", ""))["people"][0]["x"],
            Value::Null
        );
        assert_eq!(ok(&app.call("undo", "")), "Add Relationship");
        assert!(ok(&app.call("relations", ""))["links"]
            .as_array()
            .unwrap()
            .is_empty());
        assert_eq!(ok(&app.call("redo", "")), "Add Relationship");
        // Deleting a character for good drops its relationships.
        ok(&app.call("trash", &json!([a]).to_string()));
        assert!(ok(&app.call("relations", ""))["links"]
            .as_array()
            .unwrap()
            .is_empty());
        ok(&app.call("emptyTrash", ""));
        assert!(app
            .call("updateRelation", &json!([rel, "x", ""]).to_string())
            .error
            .is_some());
    }

    #[test]
    fn import_file_is_undoable() {
        let tmp = tempfile::tempdir().unwrap();
        let mut app = App::new(tmp.path().join("recent.json"));
        let url = url::Url::from_file_path(tmp.path()).unwrap().to_string();
        ok(&app.call("newProject", &json!([url, "Book", "Me"]).to_string()));
        let src = tmp.path().join("scan.pdf");
        std::fs::write(&src, b"%PDF-1.4").unwrap();
        let src_url = url::Url::from_file_path(&src).unwrap().to_string();
        let r = app.call("importFile", &json!(["", src_url]).to_string());
        assert!(r.mutated);
        let id = ok(&r);
        let info = ok(&app.call("nodeInfo", &json!([id]).to_string()));
        assert_eq!(info["file"]["kind"], "pdf");
        assert_eq!(ok(&app.call("undo", "")), "Import File");
        assert_eq!(ok(&app.call("exists", &json!([id]).to_string())), false);
        assert_eq!(ok(&app.call("redo", "")), "Import File");
        let info = ok(&app.call("nodeInfo", &json!([id]).to_string()));
        assert_eq!(info["file"]["exists"], true);
    }

    #[test]
    fn undo_through_the_api() {
        let tmp = tempfile::tempdir().unwrap();
        let mut app = App::new(tmp.path().join("recent.json"));
        let url = url::Url::from_file_path(tmp.path()).unwrap().to_string();
        ok(&app.call("newProject", &json!([url, "Book", "Me"]).to_string()));
        assert_eq!(app.undo_redo(), (None, None));
        let ms = ok(&app.call("rootId", r#"["manuscript"]"#));
        let id = ok(&app.call("add", &json!([ms, "text", "Intro", true]).to_string()));
        ok(&app.call("setText", &json!([id, "hello world"]).to_string()));
        ok(&app.call("setField", &json!([id, "title", "Opening"]).to_string()));
        // Typing isn't an undo step; renaming and adding are.
        assert_eq!(app.undo_redo().0.as_deref(), Some("Rename"));
        let r = app.call("undo", "");
        assert!(r.mutated);
        assert_eq!(ok(&r), "Rename");
        assert_eq!(
            ok(&app.call("nodeInfo", &json!([id]).to_string()))["title"],
            "Intro"
        );
        assert_eq!(ok(&app.call("undo", "")), "Add Item");
        assert!(app
            .call("nodeInfo", &json!([id]).to_string())
            .error
            .is_some());
        assert_eq!(ok(&app.call("exists", &json!([id]).to_string())), false);
        assert_eq!(
            ok(&app.call("history", "")),
            json!({"undo": null, "redo": "Add Item"})
        );
        // Saving while the item is undone must not write its orphaned text.
        ok(&app.call("save", ""));
        let md = tmp
            .path()
            .join("Book.wordloom/content")
            .join(format!("{}.md", id.as_str().unwrap()));
        assert!(!md.exists());
        assert_eq!(ok(&app.call("redo", "")), "Add Item");
        assert_eq!(
            ok(&app.call("text", &json!([id]).to_string())),
            "hello world"
        );
        // A new change clears redo.
        ok(&app.call("addTrack", r#"["Hero","character"]"#));
        assert_eq!(app.undo_redo(), (Some("Add Track".into()), None));
        // Undo with nothing to undo is harmless.
        ok(&app.call("undo", ""));
        ok(&app.call("undo", ""));
        assert_eq!(ok(&app.call("undo", "")), Value::Null);
    }
}
