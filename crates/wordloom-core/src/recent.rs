//! Most-recently-used project list, stored as JSON in the user's config dir.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

const MAX: usize = 12;

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Recent {
    pub path: PathBuf,
    pub title: String,
}

pub fn load(file: &Path) -> Vec<Recent> {
    std::fs::read(file)
        .ok()
        .and_then(|d| serde_json::from_slice::<Vec<Recent>>(&d).ok())
        .unwrap_or_default()
        .into_iter()
        .filter(|r| crate::storage::is_project(&r.path))
        .collect()
}

pub fn remember(file: &Path, path: &Path, title: &str) -> std::io::Result<()> {
    let mut list = load(file);
    list.retain(|r| r.path != path);
    list.insert(
        0,
        Recent {
            path: path.to_path_buf(),
            title: title.to_string(),
        },
    );
    list.truncate(MAX);
    if let Some(dir) = file.parent() {
        std::fs::create_dir_all(dir)?;
    }
    std::fs::write(file, serde_json::to_vec_pretty(&list).unwrap_or_default())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mru() {
        let tmp = tempfile::tempdir().unwrap();
        let cfg = tmp.path().join("cfg/recent.json");
        let a = crate::Session::create(tmp.path(), "A", "").unwrap();
        let b = crate::Session::create(tmp.path(), "B", "").unwrap();
        remember(&cfg, &a.dir, "A").unwrap();
        remember(&cfg, &b.dir, "B").unwrap();
        remember(&cfg, &a.dir, "A").unwrap();
        remember(&cfg, &tmp.path().join("gone.wordloom"), "Gone").unwrap();
        let l = load(&cfg);
        assert_eq!(
            l.iter().map(|r| r.title.as_str()).collect::<Vec<_>>(),
            vec!["A", "B"]
        );
    }
}
