//! On-disk project format.
//!
//! A project is a directory (conventionally `Name.wordloom/`):
//!
//! ```text
//! Name.wordloom/
//!   project.json          binder, metadata, labels, timeline, stats
//!   content/<uuid>.md     one Markdown file per document with text
//!   snapshots/<uuid>.json saved versions of a document
//!   files/<uuid>.<ext>    imported research files (images, PDFs, …)
//!   backups/              rolling copies of project.json
//! ```
//!
//! Everything is plain text so projects diff and merge well under version
//! control and survive without Wordloom. Writes go to a temp file and are
//! renamed into place so a crash never leaves a half-written file.

use std::fs;
use std::path::{Path, PathBuf};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::model::{NodeId, Project, FORMAT_VERSION};
use crate::{Error, Result};

pub const PROJECT_FILE: &str = "project.json";
pub const EXTENSION: &str = "wordloom";
const KEEP_BACKUPS: usize = 20;
/// Autosave runs often; only keep a backup if the newest is older than this.
const BACKUP_INTERVAL_SECS: u64 = 10 * 60;

/// Resolve whatever the user picked (the bundle dir, or project.json inside
/// it) to the bundle directory.
pub fn bundle_dir(path: &Path) -> PathBuf {
    if path.file_name().is_some_and(|n| n == PROJECT_FILE) {
        path.parent().unwrap_or(path).to_path_buf()
    } else {
        path.to_path_buf()
    }
}

/// Bundle path for a new project called `title` inside `parent`.
pub fn new_bundle_path(parent: &Path, title: &str) -> PathBuf {
    let safe: String = title
        .chars()
        .map(|c| {
            if c.is_alphanumeric() || c == ' ' || c == '-' || c == '_' {
                c
            } else {
                '_'
            }
        })
        .collect();
    let safe = safe.trim();
    let safe = if safe.is_empty() { "Untitled" } else { safe };
    parent.join(format!("{safe}.{EXTENSION}"))
}

pub fn is_project(path: &Path) -> bool {
    bundle_dir(path).join(PROJECT_FILE).is_file()
}

fn write_atomic(path: &Path, data: &[u8]) -> Result<()> {
    let tmp = path.with_extension(format!(
        "{}.tmp",
        path.extension().and_then(|e| e.to_str()).unwrap_or("")
    ));
    fs::write(&tmp, data)?;
    fs::rename(&tmp, path)?;
    Ok(())
}

pub const FILES_DIR: &str = "files";

/// Copy `src` into the bundle's `files/` directory under a fresh name and
/// return that name. Imported files are never deleted by Wordloom, so undo,
/// duplicates and backups can always refer back to them.
pub fn import_file(dir: &Path, src: &Path) -> Result<String> {
    if !src.is_file() {
        return Err(Error::Invalid(format!("{} is not a file", src.display())));
    }
    let ext = src
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_ascii_lowercase())
        .filter(|e| !e.is_empty() && e.chars().all(|c| c.is_ascii_alphanumeric()));
    let name = match ext {
        Some(e) => format!("{}.{e}", Uuid::new_v4()),
        None => Uuid::new_v4().to_string(),
    };
    let files = dir.join(FILES_DIR);
    fs::create_dir_all(&files)?;
    fs::copy(src, files.join(&name))?;
    Ok(name)
}

/// Files in `files/` whose names aren't in `keep`, with their sizes.
pub fn unused_files(
    dir: &Path,
    keep: &std::collections::HashSet<&str>,
) -> Result<Vec<(String, u64)>> {
    let files = dir.join(FILES_DIR);
    if !files.is_dir() {
        return Ok(Vec::new());
    }
    let mut out = Vec::new();
    for entry in fs::read_dir(&files)? {
        let entry = entry?;
        if !entry.file_type()?.is_file() {
            continue;
        }
        let name = entry.file_name().to_string_lossy().into_owned();
        if !keep.contains(name.as_str()) {
            out.push((name, entry.metadata()?.len()));
        }
    }
    out.sort();
    Ok(out)
}

/// Copy imported files and snapshots to a new bundle (Save As).
pub fn copy_assets(from: &Path, to: &Path) -> Result<()> {
    for sub in [FILES_DIR, "snapshots"] {
        let src = from.join(sub);
        if !src.is_dir() {
            continue;
        }
        let dst = to.join(sub);
        fs::create_dir_all(&dst)?;
        for entry in fs::read_dir(&src)? {
            let entry = entry?;
            if entry.file_type()?.is_file() {
                fs::copy(entry.path(), dst.join(entry.file_name()))?;
            }
        }
    }
    Ok(())
}

fn content_path(dir: &Path, id: NodeId) -> PathBuf {
    dir.join("content").join(format!("{id}.md"))
}

pub fn save(project: &Project, dir: &Path) -> Result<()> {
    fs::create_dir_all(dir.join("content"))?;
    let pf = dir.join(PROJECT_FILE);
    if pf.is_file() {
        backup(dir, &pf)?;
    }
    let json = serde_json::to_vec_pretty(project)?;
    write_atomic(&pf, &json)?;

    // Write changed bodies, drop files for removed or emptied documents.
    for (id, text) in &project.contents {
        let path = content_path(dir, *id);
        // Text can outlive its node in memory (kept so redo can restore it).
        if text.is_empty() || !project.nodes.contains_key(id) {
            let _ = fs::remove_file(&path);
            continue;
        }
        let same = fs::read_to_string(&path)
            .map(|old| old == *text)
            .unwrap_or(false);
        if !same {
            write_atomic(&path, text.as_bytes())?;
        }
    }
    for entry in fs::read_dir(dir.join("content"))? {
        let path = entry?.path();
        let keep = path
            .file_stem()
            .and_then(|s| s.to_str())
            .and_then(|s| Uuid::parse_str(s).ok())
            .is_some_and(|id| project.nodes.contains_key(&id) && !project.text(id).is_empty());
        if !keep && path.extension().is_some_and(|e| e == "md") {
            fs::remove_file(path)?;
        }
    }
    Ok(())
}

fn backup(dir: &Path, pf: &Path) -> Result<()> {
    let bdir = dir.join("backups");
    fs::create_dir_all(&bdir)?;
    let newest = fs::read_dir(&bdir)?
        .filter_map(|e| e.ok()?.metadata().ok()?.modified().ok())
        .max();
    let recent = newest.is_some_and(|t| {
        t.elapsed()
            .map(|d| d.as_secs() < BACKUP_INTERVAL_SECS)
            .unwrap_or(true)
    });
    if recent {
        return Ok(());
    }
    let stamp = Utc::now().format("%Y%m%dT%H%M%S%.3f");
    fs::copy(pf, bdir.join(format!("project-{stamp}.json")))?;
    let mut olds: Vec<PathBuf> = fs::read_dir(&bdir)?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().is_some_and(|e| e == "json"))
        .collect();
    olds.sort();
    while olds.len() > KEEP_BACKUPS {
        fs::remove_file(olds.remove(0))?;
    }
    Ok(())
}

pub fn load(path: &Path) -> Result<Project> {
    let dir = bundle_dir(path);
    let pf = dir.join(PROJECT_FILE);
    if !pf.is_file() {
        return Err(Error::NotAProject(dir));
    }
    load_file(&dir, &pf).map_err(|e| match e {
        Error::Json(_) | Error::Invalid(_) | Error::NoSuchNode(_)
            if !e.to_string().contains("newer Wordloom") =>
        {
            let backup = backups_newest_first(&dir).into_iter().next();
            Error::Damaged {
                reason: format!(
                    "project.json in {} is damaged ({e}).{}",
                    dir.display(),
                    if backup.is_some() {
                        " Wordloom can restore it from the newest backup."
                    } else {
                        " There is no backup to restore from."
                    }
                ),
                backup,
            }
        }
        e => e,
    })
}

/// Backups in `backups/`, newest first.
pub fn backups_newest_first(dir: &Path) -> Vec<PathBuf> {
    let mut all: Vec<PathBuf> = fs::read_dir(dir.join("backups"))
        .map(|rd| {
            rd.filter_map(|e| e.ok().map(|e| e.path()))
                .filter(|p| p.extension().is_some_and(|e| e == "json"))
                .collect()
        })
        .unwrap_or_default();
    all.sort();
    all.reverse();
    all
}

/// Replace a damaged project.json with the newest backup that loads. The
/// damaged file is kept beside it as `project.json.damaged-<time>`. Returns
/// the backup used.
pub fn restore_newest_backup(path: &Path) -> Result<PathBuf> {
    let dir = bundle_dir(path);
    let pf = dir.join(PROJECT_FILE);
    let good = backups_newest_first(&dir)
        .into_iter()
        .find(|b| load_file(&dir, b).is_ok())
        .ok_or_else(|| Error::Invalid("no usable backup was found".into()))?;
    if pf.exists() {
        let stamp = Utc::now().format("%Y%m%dT%H%M%S");
        fs::rename(&pf, dir.join(format!("{PROJECT_FILE}.damaged-{stamp}")))?;
    }
    fs::copy(&good, &pf)?;
    Ok(good)
}

fn load_file(dir: &Path, pf: &Path) -> Result<Project> {
    let mut project: Project = serde_json::from_slice(&fs::read(pf)?)?;
    if project.format_version > FORMAT_VERSION {
        return Err(Error::Invalid(format!(
            "this project was made by a newer Wordloom (format {})",
            project.format_version
        )));
    }
    let ids: Vec<NodeId> = project.nodes.keys().copied().collect();
    for id in ids {
        if let Ok(text) = fs::read_to_string(content_path(dir, id)) {
            project.contents.insert(id, text);
        }
    }
    project.validate()?;
    Ok(project)
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Snapshot {
    pub id: Uuid,
    pub created: DateTime<Utc>,
    pub title: String,
    pub text: String,
}

fn snapshot_file(dir: &Path, node: NodeId) -> PathBuf {
    dir.join("snapshots").join(format!("{node}.json"))
}

pub fn list_snapshots(dir: &Path, node: NodeId) -> Result<Vec<Snapshot>> {
    match fs::read(snapshot_file(dir, node)) {
        Ok(data) => Ok(serde_json::from_slice(&data)?),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Vec::new()),
        Err(e) => Err(e.into()),
    }
}

/// Save the current text of a document as a named snapshot (newest first).
pub fn take_snapshot(dir: &Path, node: NodeId, title: &str, text: &str) -> Result<Snapshot> {
    let mut all = list_snapshots(dir, node)?;
    let snap = Snapshot {
        id: Uuid::new_v4(),
        created: Utc::now(),
        title: if title.trim().is_empty() {
            Utc::now().format("Snapshot %Y-%m-%d %H:%M").to_string()
        } else {
            title.trim().to_string()
        },
        text: text.to_string(),
    };
    all.insert(0, snap.clone());
    fs::create_dir_all(dir.join("snapshots"))?;
    write_atomic(&snapshot_file(dir, node), &serde_json::to_vec_pretty(&all)?)?;
    Ok(snap)
}

pub fn delete_snapshot(dir: &Path, node: NodeId, snap: Uuid) -> Result<()> {
    let mut all = list_snapshots(dir, node)?;
    all.retain(|s| s.id != snap);
    write_atomic(&snapshot_file(dir, node), &serde_json::to_vec_pretty(&all)?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::RootRole;

    #[test]
    fn round_trip() {
        let tmp = tempfile::tempdir().unwrap();
        let dir = new_bundle_path(tmp.path(), "My: Novel");
        assert!(dir.ends_with("My_ Novel.wordloom"));
        let mut p = Project::new("My Novel", "A. Writer");
        let ms = p.root(RootRole::Manuscript);
        let ch = p.nodes[&ms].children[0];
        let scene = p.nodes[&ch].children[0];
        p.set_text(scene, "It was a dark and stormy night.".into())
            .unwrap();
        save(&p, &dir).unwrap();
        assert!(is_project(&dir.join(PROJECT_FILE)));

        let q = load(&dir.join(PROJECT_FILE)).unwrap();
        assert_eq!(q.text(scene), "It was a dark and stormy night.");
        assert_eq!(q.nodes.len(), p.nodes.len());

        // Removing text removes the file; saving again makes a backup.
        p.set_text(scene, String::new()).unwrap();
        save(&p, &dir).unwrap();
        assert!(!content_path(&dir, scene).exists());
        assert_eq!(fs::read_dir(dir.join("backups")).unwrap().count(), 1);
    }

    #[test]
    fn snapshots() {
        let tmp = tempfile::tempdir().unwrap();
        let id = Uuid::new_v4();
        assert!(list_snapshots(tmp.path(), id).unwrap().is_empty());
        let a = take_snapshot(tmp.path(), id, "first", "v1").unwrap();
        take_snapshot(tmp.path(), id, "", "v2").unwrap();
        let all = list_snapshots(tmp.path(), id).unwrap();
        assert_eq!(all.len(), 2);
        assert_eq!(all[1].text, "v1");
        delete_snapshot(tmp.path(), id, a.id).unwrap();
        assert_eq!(list_snapshots(tmp.path(), id).unwrap().len(), 1);
    }

    #[test]
    fn load_rejects_non_project() {
        let tmp = tempfile::tempdir().unwrap();
        assert!(matches!(load(tmp.path()), Err(Error::NotAProject(_))));
    }
}
