//! Word counting, writing targets and a per-day writing history.

use std::collections::BTreeMap;

use chrono::{Local, NaiveDate};
use serde::{Deserialize, Serialize};

/// Count words the way writers expect: runs of letters/digits, with
/// apostrophes and hyphens inside a word not splitting it. Markdown markup
/// characters on their own are not words.
pub fn count_words(text: &str) -> usize {
    let mut count = 0;
    let mut in_word = false;
    for c in text.chars() {
        if c.is_alphanumeric() {
            if !in_word {
                count += 1;
                in_word = true;
            }
        } else if in_word && (c == '\'' || c == '’' || c == '-') {
            // stays inside the word; a trailing one is harmless
        } else {
            in_word = false;
        }
    }
    count
}

pub fn count_chars(text: &str) -> usize {
    text.chars().filter(|c| !c.is_whitespace()).count()
}

#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct WritingStats {
    /// Net words written per calendar day (local time).
    #[serde(default)]
    pub daily: BTreeMap<NaiveDate, i64>,
    #[serde(default)]
    pub manuscript_target: Option<u32>,
    #[serde(default)]
    pub session_target: Option<u32>,
    #[serde(default)]
    pub deadline: Option<NaiveDate>,
}

#[derive(Serialize, Debug, Clone, PartialEq)]
pub struct StatsSummary {
    pub manuscript_words: usize,
    pub manuscript_chars: usize,
    pub project_words: usize,
    pub documents: usize,
    pub words_today: i64,
    pub manuscript_target: Option<u32>,
    pub session_target: Option<u32>,
    pub deadline: Option<NaiveDate>,
    /// Words per day needed to hit the target by the deadline.
    pub words_per_day_needed: Option<u32>,
    pub days_left: Option<i64>,
    pub streak_days: u32,
    /// Most recent 30 days, oldest first.
    pub history: Vec<(NaiveDate, i64)>,
    /// Reading time of the manuscript at 250 wpm, in minutes.
    pub reading_minutes: u32,
}

impl WritingStats {
    pub fn record(&mut self, delta: i64) {
        self.record_on(Local::now().date_naive(), delta);
    }

    pub fn record_on(&mut self, day: NaiveDate, delta: i64) {
        if delta != 0 {
            *self.daily.entry(day).or_insert(0) += delta;
        }
    }

    pub fn words_on(&self, day: NaiveDate) -> i64 {
        self.daily.get(&day).copied().unwrap_or(0)
    }

    /// Consecutive days, ending today or yesterday, with positive output.
    pub fn streak(&self, today: NaiveDate) -> u32 {
        let mut day = today;
        if self.words_on(day) <= 0 {
            day = day.pred_opt().unwrap();
        }
        let mut n = 0;
        while self.words_on(day) > 0 {
            n += 1;
            day = day.pred_opt().unwrap();
        }
        n
    }

    pub fn summary(&self, p: &crate::Project, today: NaiveDate) -> StatsSummary {
        use crate::RootRole;
        let ms = p.root(RootRole::Manuscript);
        let ms_ids: Vec<_> = p
            .subtree(ms)
            .into_iter()
            .filter(|id| p.nodes[id].include_in_compile)
            .collect();
        let manuscript_words: usize = ms_ids.iter().map(|id| p.own_words(*id)).sum();
        let manuscript_chars = ms_ids.iter().map(|id| count_chars(p.text(*id))).sum();
        let trash = p.root(RootRole::Trash);
        let trashed: std::collections::HashSet<_> = p.subtree(trash).into_iter().collect();
        let live: Vec<_> = p.nodes.keys().filter(|id| !trashed.contains(id)).collect();
        let project_words = live.iter().map(|id| p.own_words(**id)).sum();
        let documents = live
            .iter()
            .filter(|id| p.nodes[**id].kind != crate::NodeKind::Folder)
            .count();

        let days_left = self.deadline.map(|d| (d - today).num_days());
        let words_per_day_needed = match (self.manuscript_target, days_left) {
            (Some(t), Some(left)) => {
                let remaining = (t as i64 - manuscript_words as i64).max(0);
                Some(if left <= 0 {
                    remaining
                } else {
                    (remaining + left - 1) / left
                } as u32)
            }
            _ => None,
        };
        let start = today - chrono::Duration::days(29);
        let history = start
            .iter_days()
            .take(30)
            .map(|d| (d, self.words_on(d)))
            .collect();

        StatsSummary {
            manuscript_words,
            manuscript_chars,
            project_words,
            documents,
            words_today: self.words_on(today),
            manuscript_target: self.manuscript_target,
            session_target: self.session_target,
            deadline: self.deadline,
            words_per_day_needed,
            days_left,
            streak_days: self.streak(today),
            history,
            reading_minutes: (manuscript_words as f64 / 250.0).ceil() as u32,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn words() {
        assert_eq!(count_words(""), 0);
        assert_eq!(count_words("  Hello,   world! "), 2);
        assert_eq!(count_words("don't stop — well-known"), 3);
        assert_eq!(count_words("# Heading\n\n* item *two*"), 3);
        assert_eq!(count_words("Ünïcödé façade 42"), 3);
    }

    #[test]
    fn streak_and_targets() {
        let d = |s: &str| NaiveDate::parse_from_str(s, "%Y-%m-%d").unwrap();
        let mut s = WritingStats::default();
        s.record_on(d("2026-01-01"), 100);
        s.record_on(d("2026-01-02"), 50);
        s.record_on(d("2026-01-03"), 10);
        assert_eq!(s.streak(d("2026-01-03")), 3);
        assert_eq!(s.streak(d("2026-01-04")), 3);
        assert_eq!(s.streak(d("2026-01-05")), 0);

        let mut p = crate::Project::new("T", "");
        p.stats.manuscript_target = Some(1000);
        p.stats.deadline = Some(d("2026-01-11"));
        let sum = p.stats.summary(&p, d("2026-01-01"));
        assert_eq!(sum.days_left, Some(10));
        assert_eq!(sum.words_per_day_needed, Some(100));
    }
}
