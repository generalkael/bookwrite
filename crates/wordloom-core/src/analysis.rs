//! Text analysis for revision: the words and phrases you lean on, sentence
//! lengths, -ly adverbs and how much of the text is dialogue.
//!
//! Works on the documents under one binder item (the whole manuscript by
//! default), with Markdown markers and inline comments removed.

use std::collections::{HashMap, HashSet};

use serde::Serialize;

use crate::model::{NodeId, Project};

/// Common English words that say nothing about style.
const STOP: &str = "a about above after again against all am an and any are as at be because been \
before being below between both but by can could did do does doing down during each few for from \
further had has have having he her here hers herself him himself his how i if in into is it its \
itself just me more most my myself no nor not now of off on once only or other our ours ourselves \
out over own same she should so some such than that the their theirs them themselves then there \
these they this those through to too under until up very was we were what when where which while \
who whom why will with would you your yours yourself yourselves said says say s t don didn wasn \
isn couldn wouldn shouldn won can't let one back like got get went go going come came there's \
it's i'm he's she's that's what's i'd i'll you're we're they're don't didn't wasn't isn't \
couldn't wouldn't won't hadn't haven't hasn't aren't weren't";

/// Words ending in -ly that aren't adverbs.
const NOT_LY: &[&str] = &[
    "only",
    "family",
    "early",
    "reply",
    "apply",
    "supply",
    "holy",
    "ugly",
    "belly",
    "lily",
    "jelly",
    "rally",
    "ally",
    "bully",
    "tally",
    "folly",
    "holly",
    "italy",
    "july",
    "fly",
    "daily",
    "likely",
    "lonely",
    "lovely",
    "friendly",
    "silly",
    "elderly",
    "costly",
    "deadly",
    "lively",
    "chilly",
    "hilly",
    "curly",
    "burly",
    "surly",
    "oily",
    "woolly",
    "jolly",
    "assembly",
    "anomaly",
    "monopoly",
    "melancholy",
    "homily",
    "unruly",
    "kindly",
    "orderly",
    "ghostly",
    "ghastly",
    "beastly",
    "sickly",
    "stately",
    "comely",
    "manly",
    "womanly",
    "timely",
    "unlikely",
    "worldly",
    "earthly",
    "heavenly",
    "measly",
    "smelly",
    "bubbly",
    "wobbly",
    "prickly",
    "crumbly",
    "gangly",
    "pebbly",
    "scaly",
];

#[derive(Serialize, Debug, PartialEq)]
pub struct Count {
    pub text: String,
    pub count: usize,
}

#[derive(Serialize, Debug)]
pub struct LongSentence {
    pub node: NodeId,
    pub title: String,
    pub words: usize,
    /// The sentence, shortened to about 140 characters.
    pub text: String,
}

#[derive(Serialize, Debug, Default)]
pub struct Analysis {
    pub documents: usize,
    pub words: usize,
    pub unique_words: usize,
    pub sentences: usize,
    pub paragraphs: usize,
    pub avg_sentence_words: f64,
    /// Share of words inside quotation marks, 0–1.
    pub dialogue_share: f64,
    pub ly_words: usize,
    /// Your most used words, leaving out common ones like "the".
    pub top_words: Vec<Count>,
    /// Three-word phrases used more than once.
    pub phrases: Vec<Count>,
    pub top_ly: Vec<Count>,
    pub longest: Vec<LongSentence>,
}

/// Lower-cased words of `s`.
fn words_of(s: &str) -> Vec<String> {
    words_as_written(s)
        .into_iter()
        .map(|w| w.to_lowercase())
        .collect()
}

fn words_as_written(s: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut cur = String::new();
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        let c = if c == '’' { '\'' } else { c };
        if c.is_alphanumeric() {
            cur.push(c);
        } else if (c == '\'' || c == '-')
            && !cur.is_empty()
            && chars.peek().is_some_and(|n| n.is_alphanumeric())
        {
            // "don't", "well-known": one word, as in the word count.
            cur.push(c);
        } else if !cur.is_empty() {
            out.push(std::mem::take(&mut cur));
        }
    }
    if !cur.is_empty() {
        out.push(cur);
    }
    out
}

/// Sentences of one paragraph: split after . ! ? or … (and any closing
/// quotes or brackets) followed by a space.
fn sentences_of(para: &str) -> Vec<&str> {
    let mut out = Vec::new();
    let mut start = 0;
    let b: Vec<(usize, char)> = para.char_indices().collect();
    let mut i = 0;
    while i < b.len() {
        let (_, c) = b[i];
        if matches!(c, '.' | '!' | '?' | '…') {
            let mut j = i + 1;
            while j < b.len()
                && matches!(b[j].1, '.' | '!' | '?' | '…' | '"' | '”' | '’' | '\'' | ')')
            {
                j += 1;
            }
            if j >= b.len() || b[j].1.is_whitespace() {
                let end = if j < b.len() { b[j].0 } else { para.len() };
                let s = para[start..end].trim();
                if !s.is_empty() {
                    out.push(s);
                }
                start = end;
                i = j;
                continue;
            }
        }
        i += 1;
    }
    let rest = para[start..].trim();
    if !rest.is_empty() {
        out.push(rest);
    }
    out
}

/// Words inside “curly” or "straight" quotes in a paragraph. An unclosed
/// quote runs to the paragraph's end, as in fiction where a speech goes on
/// into the next paragraph.
fn dialogue_words(para: &str) -> usize {
    let mut inside = false;
    let mut chunk = String::new();
    let mut n = 0;
    for c in para.chars() {
        match c {
            '“' => {
                inside = true;
                chunk.clear();
            }
            '”' if inside => {
                n += words_of(&chunk).len();
                inside = false;
            }
            '"' => {
                if inside {
                    n += words_of(&chunk).len();
                } else {
                    chunk.clear();
                }
                inside = !inside;
            }
            _ if inside => chunk.push(c),
            _ => {}
        }
    }
    if inside {
        n += words_of(&chunk).len();
    }
    n
}

fn top(map: HashMap<String, usize>, min: usize, limit: usize) -> Vec<Count> {
    let mut v: Vec<Count> = map
        .into_iter()
        .filter(|(_, c)| *c >= min)
        .map(|(text, count)| Count { text, count })
        .collect();
    v.sort_by(|a, b| b.count.cmp(&a.count).then_with(|| a.text.cmp(&b.text)));
    v.truncate(limit);
    v
}

fn shorten(s: &str) -> String {
    let flat: String = s.split_whitespace().collect::<Vec<_>>().join(" ");
    if flat.chars().count() <= 140 {
        return flat;
    }
    let cut: String = flat.chars().take(137).collect();
    format!("{}…", cut.trim_end())
}

/// Analyse `root` and the documents under it.
pub fn analyse(p: &Project, root: NodeId) -> Analysis {
    let stop: HashSet<&str> = STOP.split_whitespace().collect();
    let mut a = Analysis::default();
    let mut word_counts: HashMap<String, usize> = HashMap::new();
    // How each word is written, so names show as "Tobias": the lower-case
    // form if it ever appears that way, else the most common spelling.
    let mut written: HashMap<String, HashMap<String, usize>> = HashMap::new();
    let mut phrase_counts: HashMap<String, usize> = HashMap::new();
    let mut ly: HashMap<String, usize> = HashMap::new();
    let mut unique: HashSet<String> = HashSet::new();
    let mut dialogue = 0usize;
    let mut longest: Vec<LongSentence> = Vec::new();

    for id in p.subtree(root) {
        let n = &p.nodes[&id];
        if p.text(id).trim().is_empty() {
            continue;
        }
        a.documents += 1;
        let text = crate::compile::strip_markdown(&crate::comments::strip(p.text(id)));
        for para in text.split("\n\n").map(str::trim).filter(|s| !s.is_empty()) {
            // A scene break isn't a paragraph.
            if para.chars().all(|c| matches!(c, '*' | '-' | '_' | ' ')) {
                continue;
            }
            a.paragraphs += 1;
            dialogue += dialogue_words(para);
            for s in sentences_of(para) {
                let raw = words_as_written(s);
                let ws: Vec<String> = raw.iter().map(|w| w.to_lowercase()).collect();
                for (w, r) in ws.iter().zip(&raw) {
                    *written
                        .entry(w.clone())
                        .or_default()
                        .entry(r.clone())
                        .or_default() += 1;
                }
                if ws.is_empty() {
                    continue;
                }
                a.sentences += 1;
                a.words += ws.len();
                for w in &ws {
                    unique.insert(w.clone());
                    if w.chars().count() >= 2
                        && !stop.contains(w.as_str())
                        && !w.chars().all(|c| c.is_ascii_digit())
                    {
                        *word_counts.entry(w.clone()).or_default() += 1;
                    }
                    if w.len() >= 5 && w.ends_with("ly") && !NOT_LY.contains(&w.as_str()) {
                        a.ly_words += 1;
                        *ly.entry(w.clone()).or_default() += 1;
                    }
                }
                for g in ws.windows(3) {
                    // Skip phrases that are only filler ("and then the").
                    if g.iter().filter(|w| !stop.contains(w.as_str())).count() >= 1 {
                        *phrase_counts.entry(g.join(" ")).or_default() += 1;
                    }
                }
                if ws.len() >= 25 {
                    longest.push(LongSentence {
                        node: id,
                        title: n.title.clone(),
                        words: ws.len(),
                        text: shorten(s),
                    });
                }
            }
        }
    }
    a.unique_words = unique.len();
    a.avg_sentence_words = if a.sentences > 0 {
        a.words as f64 / a.sentences as f64
    } else {
        0.0
    };
    a.dialogue_share = if a.words > 0 {
        (dialogue as f64 / a.words as f64).min(1.0)
    } else {
        0.0
    };
    let display = |c: &mut Count| {
        if let Some(forms) = written.get(&c.text) {
            if !forms.contains_key(&c.text) {
                if let Some((f, _)) = forms
                    .iter()
                    .max_by(|x, y| x.1.cmp(y.1).then_with(|| y.0.cmp(x.0)))
                {
                    c.text = f.clone();
                }
            }
        }
    };
    a.top_words = top(word_counts, 2, 40);
    a.top_words.iter_mut().for_each(display);
    a.phrases = top(phrase_counts, 2, 30);
    a.top_ly = top(ly, 1, 20);
    longest.sort_by_key(|s| std::cmp::Reverse(s.words));
    longest.truncate(8);
    a.longest = longest;
    a
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::RootRole;

    #[test]
    fn splits_sentences_and_words() {
        assert_eq!(
            sentences_of("One. Two! “Three?” she asked. Four"),
            vec!["One.", "Two!", "“Three?”", "she asked.", "Four"]
        );
        assert_eq!(
            sentences_of("Wait… what? 3.5 miles."),
            vec!["Wait…", "what?", "3.5 miles."]
        );
        assert_eq!(
            words_of("Don’t stop—it’s 'fine'."),
            vec!["don't", "stop", "it's", "fine"]
        );
    }

    #[test]
    fn agrees_with_the_word_count() {
        let tmp = tempfile::tempdir().unwrap();
        let s = crate::demo::create(tmp.path()).unwrap();
        let p = &s.project;
        let ms = p.root(RootRole::Manuscript);
        let a = analyse(p, ms);
        assert_eq!(a.words, p.total_words(ms));
        assert!(a.sentences > 5 && a.dialogue_share > 0.0);
    }

    #[test]
    fn words_keep_their_usual_casing() {
        let mut p = Project::new("B", "");
        let ms = p.root(RootRole::Manuscript);
        let ch = p.nodes[&ms].children[0];
        let s1 = p.nodes[&ch].children[0];
        p.set_text(
            s1,
            "Tobias ran. Tobias hid, Tobias. Dark night. It was dark.".into(),
        )
        .unwrap();
        let a = analyse(&p, ms);
        let texts: Vec<&str> = a.top_words.iter().map(|c| c.text.as_str()).collect();
        assert_eq!(texts, vec!["Tobias", "dark"]);
    }

    #[test]
    fn dialogue_share() {
        assert_eq!(dialogue_words("“Go home,” she said. “Now.”"), 3);
        assert_eq!(dialogue_words("He said \"no way\" twice."), 2);
        assert_eq!(dialogue_words("“It runs on"), 3);
    }

    #[test]
    fn counts_habits() {
        let mut p = Project::new("B", "");
        let ms = p.root(RootRole::Manuscript);
        let ch = p.nodes[&ms].children[0];
        let s1 = p.nodes[&ch].children[0];
        p.set_text(
            s1,
            "She turned slowly. She turned to look. He turned to look away.\n\n\
             “Really?” he asked quietly. {>>slowly slowly<<}\n\n* * *\n\nThe *lantern* only flickered."
                .into(),
        )
        .unwrap();
        let a = analyse(&p, ms);
        assert_eq!(a.documents, 1);
        assert_eq!(a.paragraphs, 3);
        assert_eq!(a.sentences, 6);
        assert_eq!(
            a.top_words[0],
            Count {
                text: "turned".into(),
                count: 3
            }
        );
        assert!(a.phrases.contains(&Count {
            text: "turned to look".into(),
            count: 2
        }));
        // slowly, really, quietly; not "only"; the comment isn't counted.
        assert_eq!(a.ly_words, 3);
        assert!(a.dialogue_share > 0.0 && a.dialogue_share < 0.1);
        assert!(!a.top_words.iter().any(|c| c.text == "the"));
    }
}
