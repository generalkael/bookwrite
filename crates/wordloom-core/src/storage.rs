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

/// Unpack a zip backup (from [`backup_zip`], or any zip holding one
/// project folder) into a new folder inside `parent`, and return it. The
/// folder keeps the project's name; if that's taken, " (restored DATE
/// TIME)" is added. Entries outside the project folder, and any path that
/// would escape it, are skipped.
pub fn restore_zip(zip_path: &Path, parent: &Path) -> Result<PathBuf> {
    let bad = || {
        Error::Invalid(format!(
            "{} isn't a Wordloom zip backup",
            zip_path.display()
        ))
    };
    let data = fs::read(zip_path)?;
    let entries = crate::zip::entries(&data).ok_or_else(bad)?;
    // The project folder: where the shallowest project.json sits.
    let root = entries
        .iter()
        .filter_map(|(n, _)| n.strip_suffix(PROJECT_FILE))
        .filter(|prefix| prefix.is_empty() || prefix.ends_with('/'))
        .min_by_key(|prefix| prefix.matches('/').count())
        .map(str::to_string)
        .ok_or_else(bad)?;
    let name = root
        .trim_end_matches('/')
        .rsplit('/')
        .next()
        .filter(|n| !n.is_empty())
        .map(str::to_string)
        .unwrap_or_else(|| {
            let stem = zip_path.file_stem().unwrap_or_default().to_string_lossy();
            format!("{stem}.{EXTENSION}")
        });
    let mut dest = parent.join(&name);
    if dest.exists() {
        let stem = name.strip_suffix(&format!(".{EXTENSION}")).unwrap_or(&name);
        let when = chrono::Local::now().format("%Y-%m-%d %H%M");
        dest = parent.join(format!("{stem} (restored {when}).{EXTENSION}"));
        if dest.exists() {
            return Err(Error::Invalid(format!("{} already exists", dest.display())));
        }
    }
    for (entry, bytes) in &entries {
        let Some(rel) = entry.strip_prefix(&root) else {
            continue;
        };
        if rel.is_empty() || rel.ends_with('/') {
            continue;
        }
        // No absolute paths, "..", or backslash tricks.
        let parts: Vec<&str> = rel.split('/').collect();
        if rel.starts_with('/')
            || rel.contains('\\')
            || parts
                .iter()
                .any(|p| p.is_empty() || *p == "." || *p == "..")
        {
            continue;
        }
        let path = parts.iter().fold(dest.clone(), |d, p| d.join(p));
        if let Some(dir) = path.parent() {
            fs::create_dir_all(dir)?;
        }
        fs::write(&path, bytes)?;
    }
    if !is_project(&dest) {
        let _ = fs::remove_dir_all(&dest);
        return Err(bad());
    }
    Ok(dest)
}

/// The files a zip backup holds, as (path inside the project, path on
/// disk), in a stable order.
fn backup_files(dir: &Path) -> Result<Vec<(String, PathBuf)>> {
    fn walk(dir: &Path, rel: &str, out: &mut Vec<(String, PathBuf)>) -> Result<()> {
        let mut entries: Vec<_> = fs::read_dir(dir)?.collect::<std::io::Result<_>>()?;
        entries.sort_by_key(|e| e.file_name());
        for e in entries {
            let name = e.file_name().to_string_lossy().into_owned();
            let path = e.path();
            let top = rel.is_empty();
            if (top
                && (name == LOCK_FILE
                    || name == BACKUPS_DIR
                    || name == AUTO_BACKUP_STATE
                    || name.contains(".damaged-")))
                || name.ends_with(".tmp")
            {
                continue;
            }
            let r = if top { name } else { format!("{rel}/{name}") };
            if e.file_type()?.is_dir() {
                walk(&path, &r, out)?;
            } else {
                out.push((r, path));
            }
        }
        Ok(())
    }
    let mut files = Vec::new();
    walk(dir, "", &mut files)?;
    Ok(files)
}

/// A fingerprint of everything a zip backup would hold (FNV-1a over the
/// names and contents), so an automatic backup can tell whether anything
/// changed since the last one.
pub fn backup_fingerprint(dir: &Path) -> Result<String> {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    let mut eat = |bytes: &[u8]| {
        for b in bytes {
            h ^= *b as u64;
            h = h.wrapping_mul(0x0100_0000_01b3);
        }
    };
    for (rel, path) in backup_files(dir)? {
        eat(rel.as_bytes());
        eat(&[0]);
        let data = fs::read(path)?;
        eat(&(data.len() as u64).to_le_bytes());
        eat(&data);
    }
    Ok(format!("{h:016x}"))
}

/// Pack the project folder into one zip file at `dest`: everything a copy
/// needs (project.json, documents, snapshots, imported files), without the
/// lock, the rolling backups or half-written temp files. Entries sit under
/// the folder's own name, so unzipping gives back `Title.wordloom/`.
/// Returns the number of files packed.
pub fn backup_zip(dir: &Path, dest: &Path) -> Result<usize> {
    let files = backup_files(dir)?;
    let folder = dir
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| format!("Project.{EXTENSION}"));
    // Zip timestamps are local time.
    let mut z = crate::zip::ZipWriter::new(chrono::Local::now().naive_local().and_utc());
    let mut total: u64 = 0;
    for (rel, path) in &files {
        let data = fs::read(path)?;
        total += data.len() as u64;
        // A plain (non-zip64) archive tops out at 4 GB.
        if total > u32::MAX as u64 - (1 << 24) || files.len() > u16::MAX as usize {
            return Err(Error::Invalid(
                "the project is too large for a zip backup (over 4 GB); copy the folder instead"
                    .into(),
            ));
        }
        z.add(&format!("{folder}/{rel}"), &data);
    }
    write_atomic(dest, &z.finish())?;
    Ok(files.len())
}

pub fn is_project(path: &Path) -> bool {
    bundle_dir(path).join(PROJECT_FILE).is_file()
}

pub(crate) fn write_atomic(path: &Path, data: &[u8]) -> Result<()> {
    let tmp = path.with_extension(format!(
        "{}.tmp",
        path.extension().and_then(|e| e.to_str()).unwrap_or("")
    ));
    fs::write(&tmp, data)?;
    fs::rename(&tmp, path)?;
    Ok(())
}

pub const FILES_DIR: &str = "files";
pub const BACKUPS_DIR: &str = "backups";
/// Remembers the fingerprint of the last automatic zip backup (and where it
/// went), so closing an unchanged project doesn't make another one.
pub const AUTO_BACKUP_STATE: &str = "autobackup.txt";

/// Marks a project as open, so a second Wordloom (another window, or
/// another computer sharing the folder) can warn before both write to it.
pub const LOCK_FILE: &str = ".wordloom.lock";
/// A lock not refreshed for this long is treated as stale. The app
/// refreshes it every couple of minutes while the project is open.
const LOCK_STALE_SECS: i64 = 10 * 60;

#[derive(Serialize, Deserialize)]
struct LockInfo {
    pid: u32,
    host: String,
    at: DateTime<Utc>,
    /// Written from a sandbox (Flatpak), whose process ids mean nothing
    /// outside it.
    #[serde(default)]
    sandboxed: bool,
}

/// Inside a Flatpak, each instance has its own process-id namespace.
fn sandboxed() -> bool {
    Path::new("/.flatpak-info").exists()
}

fn host_name() -> String {
    fs::read_to_string("/proc/sys/kernel/hostname")
        .ok()
        .or_else(|| std::env::var("HOSTNAME").ok())
        .or_else(|| std::env::var("COMPUTERNAME").ok())
        .map(|h| h.trim().to_string())
        .filter(|h| !h.is_empty())
        .unwrap_or_else(|| "this computer".into())
}

/// Who else has the project in `dir` open, if anyone ("laptop, 2 minutes
/// ago"). Our own lock, and locks left by a crash, don't count.
pub fn lock_holder(dir: &Path) -> Option<String> {
    let info: LockInfo = serde_json::from_slice(&fs::read(dir.join(LOCK_FILE)).ok()?).ok()?;
    let here = host_name();
    if info.host == here && info.pid == std::process::id() && info.sandboxed == sandboxed() {
        return None;
    }
    let age = (Utc::now() - info.at).num_seconds();
    let proc_dir = Path::new("/proc");
    // Process ids can only be checked between two unsandboxed processes on
    // the same computer; otherwise go by how recently the lock was refreshed.
    let pid_check = info.host == here && !info.sandboxed && !sandboxed() && proc_dir.is_dir();
    let alive = if pid_check {
        // Same computer: is that process still running Wordloom?
        fs::read(proc_dir.join(info.pid.to_string()).join("cmdline"))
            .map(|c| {
                String::from_utf8_lossy(&c)
                    .to_lowercase()
                    .contains("wordloom")
            })
            .unwrap_or(false)
    } else {
        age < LOCK_STALE_SECS
    };
    alive.then(|| {
        let when = if age < 90 {
            "just now".to_string()
        } else {
            format!("{} minutes ago", age / 60)
        };
        if info.host == here {
            format!("another window on this computer, active {when}")
        } else {
            format!("on {}, active {when}", info.host)
        }
    })
}

/// Take (or refresh) the lock for this process.
pub fn write_lock(dir: &Path) -> Result<()> {
    let info = LockInfo {
        pid: std::process::id(),
        host: host_name(),
        at: Utc::now(),
        sandboxed: sandboxed(),
    };
    write_atomic(&dir.join(LOCK_FILE), &serde_json::to_vec(&info)?)
}

/// Remove the lock if it is ours.
pub fn remove_lock(dir: &Path) {
    let path = dir.join(LOCK_FILE);
    if let Ok(info) = fs::read(&path)
        .and_then(|b| serde_json::from_slice::<LockInfo>(&b).map_err(std::io::Error::other))
    {
        if info.pid == std::process::id()
            && info.host == host_name()
            && info.sandboxed == sandboxed()
        {
            let _ = fs::remove_file(path);
        }
    }
}

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
    let bdir = dir.join(BACKUPS_DIR);
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
    let mut all: Vec<PathBuf> = fs::read_dir(dir.join(BACKUPS_DIR))
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
        assert_eq!(fs::read_dir(dir.join(BACKUPS_DIR)).unwrap().count(), 1);
    }

    #[test]
    fn project_lock() {
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path();
        assert_eq!(lock_holder(dir), None);
        // Our own lock never blocks us.
        write_lock(dir).unwrap();
        assert_eq!(lock_holder(dir), None);
        // Another computer, recently active: blocks; long ago: stale.
        let other = |host: &str, mins: i64| {
            let info = LockInfo {
                pid: 1,
                host: host.into(),
                at: Utc::now() - chrono::Duration::minutes(mins),
                sandboxed: false,
            };
            fs::write(dir.join(LOCK_FILE), serde_json::to_vec(&info).unwrap()).unwrap();
        };
        other("laptop", 2);
        assert!(lock_holder(dir).unwrap().contains("laptop"));
        other("laptop", 60);
        assert_eq!(lock_holder(dir), None);
        // This computer, but a process that isn't running (crashed): stale.
        let info = LockInfo {
            pid: u32::MAX - 7,
            host: host_name(),
            at: Utc::now(),
            sandboxed: false,
        };
        fs::write(dir.join(LOCK_FILE), serde_json::to_vec(&info).unwrap()).unwrap();
        assert_eq!(lock_holder(dir), None);
        // A sandboxed instance on this computer: its pid can't be checked,
        // so a fresh lock counts and an old one doesn't.
        let flatpak = |mins: i64| {
            let info = LockInfo {
                pid: 2,
                host: host_name(),
                at: Utc::now() - chrono::Duration::minutes(mins),
                sandboxed: true,
            };
            fs::write(dir.join(LOCK_FILE), serde_json::to_vec(&info).unwrap()).unwrap();
        };
        flatpak(1);
        assert!(lock_holder(dir).unwrap().contains("this computer"));
        flatpak(30);
        assert_eq!(lock_holder(dir), None);
        // remove_lock only removes ours.
        remove_lock(dir);
        assert!(dir.join(LOCK_FILE).exists());
        write_lock(dir).unwrap();
        remove_lock(dir);
        assert!(!dir.join(LOCK_FILE).exists());
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
