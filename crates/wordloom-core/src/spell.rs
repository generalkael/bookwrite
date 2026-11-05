//! Spell checking with Hunspell-format dictionaries (via `spellbook`).
//!
//! The dictionary for the user's language is looked up in the usual system
//! places (`/usr/share/hunspell`, …); without one, a bundled US English
//! dictionary is used (SCOWL, see `dict/COPYRIGHT-en_US.txt`). Words the user
//! adds go to a personal word list, and the names of the project's
//! characters and places are always accepted.
//!
//! There is one checker per process, loaded on first use, because the
//! editor's highlighter asks about every word it draws.

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};

use spellbook::Dictionary;

const BUNDLED_AFF: &str = include_str!("../dict/en_US.aff");
const BUNDLED_DIC: &str = include_str!("../dict/en_US.dic");

pub struct Speller {
    dict: Dictionary,
    /// e.g. "en_US (system)" or "en_US (built in)".
    pub source: String,
    personal: HashSet<String>,
    personal_path: Option<PathBuf>,
    project: HashSet<String>,
}

/// Language code from the environment, e.g. "en_GB" for `LANG=en_GB.UTF-8`.
fn env_language() -> Option<String> {
    ["LC_ALL", "LC_MESSAGES", "LANG"]
        .iter()
        .filter_map(|k| std::env::var(k).ok())
        .map(|v| v.split(['.', '@']).next().unwrap_or("").to_string())
        .find(|v| !v.is_empty() && v != "C" && v != "POSIX")
}

fn dictionary_dirs() -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    if let Some(home) = std::env::var_os("HOME") {
        dirs.push(Path::new(&home).join(".local/share/hunspell"));
    }
    let data = std::env::var("XDG_DATA_DIRS").unwrap_or_default();
    for d in data.split(':').filter(|d| !d.is_empty()) {
        dirs.push(Path::new(d).join("hunspell"));
        dirs.push(Path::new(d).join("myspell/dicts"));
    }
    for d in [
        "/app/share/hunspell",
        "/usr/share/hunspell",
        "/usr/share/myspell/dicts",
        "/usr/share/myspell",
        "/usr/local/share/hunspell",
    ] {
        dirs.push(PathBuf::from(d));
    }
    dirs
}

fn load_system(lang: &str) -> Option<(Dictionary, String)> {
    for dir in dictionary_dirs() {
        let (aff, dic) = (
            dir.join(format!("{lang}.aff")),
            dir.join(format!("{lang}.dic")),
        );
        if let (Ok(a), Ok(d)) = (std::fs::read_to_string(&aff), std::fs::read_to_string(&dic)) {
            if let Ok(dict) = Dictionary::new(&a, &d) {
                return Some((dict, format!("{lang} ({})", dir.display())));
            }
        }
    }
    None
}

impl Speller {
    /// Load the best dictionary for `lang` (default: the environment's
    /// language), and the personal word list at `personal_path`.
    pub fn load(lang: Option<&str>, personal_path: Option<PathBuf>) -> Self {
        let lang = lang.map(String::from).or_else(env_language);
        let (dict, source) = lang
            .as_deref()
            .and_then(load_system)
            .or_else(|| load_system("en_US"))
            .unwrap_or_else(|| {
                (
                    Dictionary::new(BUNDLED_AFF, BUNDLED_DIC).expect("bundled dictionary parses"),
                    "en_US (built in)".into(),
                )
            });
        let personal: HashSet<String> = personal_path
            .as_ref()
            .and_then(|p| std::fs::read_to_string(p).ok())
            .map(|t| {
                t.lines()
                    .map(|l| l.trim().to_string())
                    .filter(|l| !l.is_empty())
                    .collect()
            })
            .unwrap_or_default();
        Self {
            dict,
            source,
            personal,
            personal_path,
            project: HashSet::new(),
        }
    }

    /// The bundled dictionary only (tests).
    pub fn bundled() -> Self {
        Self {
            dict: Dictionary::new(BUNDLED_AFF, BUNDLED_DIC).expect("bundled dictionary parses"),
            source: "en_US (built in)".into(),
            personal: HashSet::new(),
            personal_path: None,
            project: HashSet::new(),
        }
    }

    pub fn check(&self, word: &str) -> bool {
        let word = word.trim_matches(|c: char| c == '\'' || c == '’');
        if word.chars().count() <= 1 || word.chars().any(|c| c.is_ascii_digit()) {
            return true;
        }
        let plain = word.replace('’', "'");
        if self.personal.contains(&plain)
            || self.project.contains(&plain)
            || self.personal.contains(&plain.to_lowercase())
        {
            return true;
        }
        if self.dict.check(&plain) {
            return true;
        }
        // Possessives of names and other dictionary words: "Mara's".
        if let Some(stem) = plain.strip_suffix("'s") {
            return self.project.contains(stem)
                || self.personal.contains(stem)
                || self.dict.check(stem);
        }
        false
    }

    pub fn suggest(&self, word: &str) -> Vec<String> {
        let mut out = Vec::new();
        self.dict.suggest(&word.replace('’', "'"), &mut out);
        out.truncate(8);
        out
    }

    /// Accept `word` from now on and remember it in the personal list.
    pub fn add_personal(&mut self, word: &str) -> std::io::Result<()> {
        let word = word.trim().replace('’', "'");
        if word.is_empty() || !self.personal.insert(word.clone()) {
            return Ok(());
        }
        if let Some(path) = &self.personal_path {
            if let Some(dir) = path.parent() {
                std::fs::create_dir_all(dir)?;
            }
            use std::io::Write;
            let mut f = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(path)?;
            writeln!(f, "{word}")?;
        }
        Ok(())
    }

    /// Words always accepted for the open project (character and place names).
    pub fn set_project_words(&mut self, words: HashSet<String>) {
        self.project = words;
    }
}

static GLOBAL: OnceLock<Mutex<Option<Speller>>> = OnceLock::new();
static PERSONAL_PATH: OnceLock<PathBuf> = OnceLock::new();

/// Where the personal word list lives; call once at startup.
pub fn set_personal_path(path: PathBuf) {
    let _ = PERSONAL_PATH.set(path);
}

/// Run `f` with the shared checker, loading it on first use.
pub fn with<R>(f: impl FnOnce(&mut Speller) -> R) -> R {
    let cell = GLOBAL.get_or_init(|| Mutex::new(None));
    let mut guard = cell.lock().unwrap_or_else(|e| e.into_inner());
    let speller = guard.get_or_insert_with(|| Speller::load(None, PERSONAL_PATH.get().cloned()));
    f(speller)
}

/// Like [`with`], but does nothing if the checker hasn't been loaded yet.
pub fn if_loaded(f: impl FnOnce(&mut Speller)) {
    if let Some(cell) = GLOBAL.get() {
        if let Some(s) = cell.lock().unwrap_or_else(|e| e.into_inner()).as_mut() {
            f(s);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn checks_suggests_and_learns() {
        let tmp = tempfile::tempdir().unwrap();
        let mut s = Speller::bundled();
        s.personal_path = Some(tmp.path().join("words.txt"));
        assert!(s.check("lighthouse"));
        assert!(s.check("keeper's"));
        assert!(s.check("don’t"));
        assert!(s.check("1893"));
        assert!(!s.check("lighthuose"));
        assert!(s.suggest("lighthuose").iter().any(|w| w == "lighthouse"));
        // Names from the project, with possessives.
        assert!(!s.check("Ulirath"));
        s.set_project_words(["Ulirath".to_string(), "Skerry".to_string()].into());
        assert!(s.check("Ulirath") && s.check("Ulirath's") && s.check("Skerry"));
        // Personal words persist to the list.
        assert!(!s.check("grimdark"));
        s.add_personal("grimdark").unwrap();
        assert!(s.check("grimdark"));
        let again = Speller::load(Some("xx_XX"), s.personal_path.clone());
        assert!(again.check("grimdark"));
    }
}
