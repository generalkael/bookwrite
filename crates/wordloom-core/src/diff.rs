//! Side-by-side comparison of two versions of a document.
//!
//! Paragraphs are matched first; a paragraph that was edited (rather than
//! added or removed) is then compared word by word, so the result reads as
//! two aligned columns with the changed words marked.

use serde::Serialize;

/// Above this many cells (tokens × tokens) a comparison is skipped and the
/// whole block is marked as changed, to bound time and memory.
const MAX_CELLS: usize = 4_000_000;

#[derive(Serialize, Debug, PartialEq, Clone, Copy)]
#[serde(rename_all = "snake_case")]
pub enum RowKind {
    Same,
    Changed,
    Added,
    Removed,
}

/// A run of text; `mark` is true where it differs from the other side.
#[derive(Serialize, Debug, PartialEq, Clone)]
pub struct Segment {
    pub text: String,
    pub mark: bool,
}

/// One aligned paragraph pair. A side is empty for added / removed rows.
#[derive(Serialize, Debug, PartialEq)]
pub struct Row {
    pub kind: RowKind,
    pub left: Vec<Segment>,
    pub right: Vec<Segment>,
}

#[derive(Serialize, Debug, PartialEq)]
pub struct Comparison {
    pub rows: Vec<Row>,
    pub words_added: usize,
    pub words_removed: usize,
}

pub fn compare(old: &str, new: &str) -> Comparison {
    let a = paragraphs(old);
    let b = paragraphs(new);
    let mut rows = Vec::new();
    let mut removed: Vec<&str> = Vec::new();
    let mut added: Vec<&str> = Vec::new();
    for op in diff(&a, &b) {
        match op {
            Op::Same(p) => {
                flush(&mut rows, &mut removed, &mut added);
                rows.push(Row {
                    kind: RowKind::Same,
                    left: plain(p),
                    right: plain(p),
                });
            }
            Op::Del(p) => removed.push(p),
            Op::Ins(p) => added.push(p),
        }
    }
    flush(&mut rows, &mut removed, &mut added);

    let mut words_added = 0;
    let mut words_removed = 0;
    for r in &rows {
        words_removed += marked_words(&r.left);
        words_added += marked_words(&r.right);
    }
    Comparison {
        rows,
        words_added,
        words_removed,
    }
}

/// Pair a run of removed paragraphs with the added ones that replaced them
/// (edited paragraphs); leftovers are plain removals / additions.
fn flush<'a>(rows: &mut Vec<Row>, removed: &mut Vec<&'a str>, added: &mut Vec<&'a str>) {
    let n = removed.len().max(added.len());
    for i in 0..n {
        match (removed.get(i), added.get(i)) {
            (Some(l), Some(r)) => {
                let (left, right) = word_diff(l, r);
                rows.push(Row {
                    kind: RowKind::Changed,
                    left,
                    right,
                });
            }
            (Some(l), None) => rows.push(Row {
                kind: RowKind::Removed,
                left: marked(l),
                right: Vec::new(),
            }),
            (None, Some(r)) => rows.push(Row {
                kind: RowKind::Added,
                left: Vec::new(),
                right: marked(r),
            }),
            (None, None) => {}
        }
    }
    removed.clear();
    added.clear();
}

fn paragraphs(s: &str) -> Vec<&str> {
    s.lines()
        .map(str::trim_end)
        .filter(|l| !l.trim().is_empty())
        .collect()
}

fn plain(s: &str) -> Vec<Segment> {
    vec![Segment {
        text: s.to_string(),
        mark: false,
    }]
}

fn marked(s: &str) -> Vec<Segment> {
    vec![Segment {
        text: s.to_string(),
        mark: true,
    }]
}

fn marked_words(segs: &[Segment]) -> usize {
    segs.iter()
        .filter(|s| s.mark)
        .map(|s| s.text.split_whitespace().count())
        .sum()
}

/// Words, runs of whitespace, and single punctuation marks.
fn tokens(s: &str) -> Vec<&str> {
    let mut out = Vec::new();
    let mut start = 0;
    let mut prev: Option<u8> = None; // 0 = word, 1 = space
    for (i, c) in s.char_indices() {
        let class = if c.is_alphanumeric() || c == '\'' || c == '’' {
            Some(0)
        } else if c.is_whitespace() {
            Some(1)
        } else {
            None
        };
        if i > start && (class.is_none() || class != prev) {
            out.push(&s[start..i]);
            start = i;
        }
        prev = class;
    }
    if start < s.len() {
        out.push(&s[start..]);
    }
    out
}

fn word_diff(old: &str, new: &str) -> (Vec<Segment>, Vec<Segment>) {
    let a = tokens(old);
    let b = tokens(new);
    let mut left: Vec<Segment> = Vec::new();
    let mut right: Vec<Segment> = Vec::new();
    let push = |side: &mut Vec<Segment>, t: &str, mark: bool| match side.last_mut() {
        Some(last) if last.mark == mark => last.text.push_str(t),
        _ => side.push(Segment {
            text: t.to_string(),
            mark,
        }),
    };
    for op in diff(&a, &b) {
        match op {
            Op::Same(t) => {
                push(&mut left, t, false);
                push(&mut right, t, false);
            }
            Op::Del(t) => push(&mut left, t, true),
            Op::Ins(t) => push(&mut right, t, true),
        }
    }
    // Whitespace alone between two changes reads better as part of them.
    for side in [&mut left, &mut right] {
        slide_spaces(side);
        merge_gaps(side);
    }
    (left, right)
}

/// "her[ alone] on" and "her [alone ]on" are the same change; prefer the
/// second, so marks start on a word.
fn slide_spaces(side: &mut [Segment]) {
    for i in 1..side.len().saturating_sub(1) {
        if !side[i].mark || side[i - 1].mark || side[i + 1].mark {
            continue;
        }
        let Some(c) = side[i].text.chars().next().filter(|c| c.is_whitespace()) else {
            continue;
        };
        if side[i].text.len() > c.len_utf8() && side[i + 1].text.starts_with(c) {
            side[i - 1].text.push(c);
            side[i].text.remove(0);
            side[i].text.push(c);
            side[i + 1].text.remove(0);
        }
    }
}

fn merge_gaps(side: &mut Vec<Segment>) {
    let mut i = 1;
    while i + 1 < side.len() {
        if !side[i].mark && side[i].text.trim().is_empty() && side[i - 1].mark && side[i + 1].mark {
            let gap = side.remove(i).text;
            let next = side.remove(i).text;
            side[i - 1].text.push_str(&gap);
            side[i - 1].text.push_str(&next);
        } else {
            i += 1;
        }
    }
}

enum Op<'a> {
    Same(&'a str),
    Del(&'a str),
    Ins(&'a str),
}

/// Longest-common-subsequence diff, after trimming the common prefix and
/// suffix (which is most of the text in a typical revision).
fn diff<'a>(a: &[&'a str], b: &[&'a str]) -> Vec<Op<'a>> {
    let pre = a.iter().zip(b).take_while(|(x, y)| x == y).count();
    let suf = a[pre..]
        .iter()
        .rev()
        .zip(b[pre..].iter().rev())
        .take_while(|(x, y)| x == y)
        .count();
    let (ma, mb) = (&a[pre..a.len() - suf], &b[pre..b.len() - suf]);
    let mut out: Vec<Op<'a>> = a[..pre].iter().map(|t| Op::Same(t)).collect();

    let (n, m) = (ma.len(), mb.len());
    if n * m > MAX_CELLS {
        out.extend(ma.iter().map(|t| Op::Del(t)));
        out.extend(mb.iter().map(|t| Op::Ins(t)));
    } else {
        // lcs[i][j] = LCS length of ma[i..] and mb[j..].
        let w = m + 1;
        let mut lcs = vec![0u32; (n + 1) * w];
        for i in (0..n).rev() {
            for j in (0..m).rev() {
                lcs[i * w + j] = if ma[i] == mb[j] {
                    lcs[(i + 1) * w + j + 1] + 1
                } else {
                    lcs[(i + 1) * w + j].max(lcs[i * w + j + 1])
                };
            }
        }
        let (mut i, mut j) = (0, 0);
        while i < n || j < m {
            if i < n && j < m && ma[i] == mb[j] {
                out.push(Op::Same(ma[i]));
                i += 1;
                j += 1;
            } else if j < m && (i == n || lcs[i * w + j + 1] >= lcs[(i + 1) * w + j]) {
                out.push(Op::Ins(mb[j]));
                j += 1;
            } else {
                out.push(Op::Del(ma[i]));
                i += 1;
            }
        }
    }
    out.extend(a[a.len() - suf..].iter().map(|t| Op::Same(t)));
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text(segs: &[Segment]) -> String {
        segs.iter()
            .map(|s| {
                if s.mark {
                    format!("[{}]", s.text)
                } else {
                    s.text.clone()
                }
            })
            .collect()
    }

    #[test]
    fn identical() {
        let c = compare("One.\n\nTwo.", "One.\n\nTwo.");
        assert_eq!(c.rows.len(), 2);
        assert!(c.rows.iter().all(|r| r.kind == RowKind::Same));
        assert_eq!((c.words_added, c.words_removed), (0, 0));
    }

    #[test]
    fn edited_paragraph_marks_words() {
        let c = compare(
            "The ferry left her on the jetty.\n\nRain.",
            "The old ferry left her alone on the jetty.\n\nRain.",
        );
        assert_eq!(c.rows[0].kind, RowKind::Changed);
        assert_eq!(text(&c.rows[0].left), "The ferry left her on the jetty.");
        assert_eq!(
            text(&c.rows[0].right),
            "The [old ]ferry left her [alone ]on the jetty."
        );
        assert_eq!(c.rows[1].kind, RowKind::Same);
        assert_eq!((c.words_added, c.words_removed), (2, 0));
    }

    #[test]
    fn added_and_removed_paragraphs() {
        let c = compare("A.\n\nGone.\n\nC.", "A.\n\nC.\n\nNew ending here.");
        let kinds: Vec<_> = c.rows.iter().map(|r| r.kind).collect();
        assert_eq!(
            kinds,
            [
                RowKind::Same,
                RowKind::Removed,
                RowKind::Same,
                RowKind::Added
            ]
        );
        assert!(c.rows[1].right.is_empty());
        assert_eq!((c.words_added, c.words_removed), (3, 1));
    }

    #[test]
    fn replaced_word_and_neighbouring_changes_merge() {
        let c = compare("a big red dog", "a small blue dog");
        assert_eq!(text(&c.rows[0].left), "a [big red] dog");
        assert_eq!(text(&c.rows[0].right), "a [small blue] dog");
    }

    #[test]
    fn tokens_keep_contractions() {
        assert_eq!(
            tokens("don't stop, ok"),
            ["don't", " ", "stop", ",", " ", "ok"]
        );
    }
}
