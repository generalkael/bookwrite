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
    /// Word totals at the end of each day something was saved:
    /// [manuscript words, project words].
    #[serde(default)]
    pub totals: BTreeMap<NaiveDate, [u64; 2]>,
    /// Finished writing sprints, oldest first.
    #[serde(default)]
    pub sprints: Vec<Sprint>,
}

/// A timed writing session.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Sprint {
    pub started: chrono::DateTime<chrono::Utc>,
    /// Minutes actually written (a sprint can be ended early).
    pub minutes: f64,
    /// Net manuscript words written during the sprint.
    pub words: i64,
    #[serde(default)]
    pub goal: Option<u32>,
}

#[derive(Serialize, Debug, Clone, PartialEq)]
pub struct SprintSummary {
    /// Most recent first.
    pub recent: Vec<Sprint>,
    pub count: usize,
    pub total_words: i64,
    pub total_minutes: f64,
    pub best_words: Option<i64>,
    /// Best words per minute over sprints of at least five minutes.
    pub best_pace: Option<f64>,
}

/// How [`WritingStats::range_history`] groups days.
#[derive(Serialize, Clone, Copy, PartialEq, Eq, Debug)]
#[serde(rename_all = "snake_case")]
pub enum Bucket {
    Day,
    /// Monday to Sunday.
    Week,
    Month,
    Year,
}

impl Bucket {
    /// "day", "week", "month", "year"; anything else picks a size that
    /// suits the span (days up to two months, then weeks, months, years).
    pub fn parse(s: &str, from: NaiveDate, to: NaiveDate) -> Self {
        match s {
            "day" => Self::Day,
            "week" => Self::Week,
            "month" => Self::Month,
            "year" => Self::Year,
            _ => {
                let days = (to - from).num_days();
                if days <= 62 {
                    Self::Day
                } else if days <= 366 {
                    Self::Week
                } else if days <= 366 * 5 {
                    Self::Month
                } else {
                    Self::Year
                }
            }
        }
    }

    /// First day of the bucket containing `d`.
    fn start_of(self, d: NaiveDate) -> NaiveDate {
        use chrono::Datelike;
        match self {
            Self::Day => d,
            Self::Week => d - chrono::Duration::days(d.weekday().num_days_from_monday() as i64),
            Self::Month => d.with_day(1).unwrap(),
            Self::Year => NaiveDate::from_ymd_opt(d.year(), 1, 1).unwrap(),
        }
    }

    fn next(self, start: NaiveDate) -> NaiveDate {
        use chrono::Months;
        match self {
            Self::Day => start + chrono::Duration::days(1),
            Self::Week => start + chrono::Duration::days(7),
            Self::Month => start + Months::new(1),
            Self::Year => start + Months::new(12),
        }
    }
}

/// One bar of the history chart.
#[derive(Serialize, Debug, Clone, PartialEq)]
pub struct HistoryBucket {
    /// The days covered, clipped to the requested range.
    pub start: NaiveDate,
    pub end: NaiveDate,
    /// Net words written (can be negative after heavy cutting).
    pub written: i64,
    /// Totals at the end of the bucket, carried forward from the last day
    /// they were recorded; `None` before the first record.
    pub manuscript: Option<u64>,
    pub project: Option<u64>,
}

#[derive(Serialize, Debug, Clone, PartialEq)]
pub struct RangeHistory {
    pub from: NaiveDate,
    pub to: NaiveDate,
    pub bucket: Bucket,
    pub buckets: Vec<HistoryBucket>,
    pub total_written: i64,
    /// Days in the range with more words than before.
    pub days_written: u32,
    pub average_per_day: f64,
    pub best_day: Option<(NaiveDate, i64)>,
    /// The first day anything was recorded (for "lifetime").
    pub first_day: Option<NaiveDate>,
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

    pub fn add_sprint(&mut self, sprint: Sprint) {
        self.sprints.push(sprint);
    }

    pub fn sprint_summary(&self, recent: usize) -> SprintSummary {
        let s = &self.sprints;
        SprintSummary {
            recent: s.iter().rev().take(recent).cloned().collect(),
            count: s.len(),
            total_words: s.iter().map(|x| x.words).sum(),
            total_minutes: s.iter().map(|x| x.minutes).sum(),
            best_words: s.iter().map(|x| x.words).max(),
            best_pace: s
                .iter()
                .filter(|x| x.minutes >= 5.0)
                .map(|x| x.words as f64 / x.minutes)
                .fold(None, |best: Option<f64>, p| {
                    Some(best.map_or(p, |b| b.max(p)))
                }),
        }
    }

    /// Remember the word totals as of `day` (called on save).
    pub fn note_totals(&mut self, day: NaiveDate, manuscript: u64, project: u64) {
        self.totals.insert(day, [manuscript, project]);
    }

    pub fn first_day(&self) -> Option<NaiveDate> {
        let a = self.daily.keys().next().copied();
        let b = self.totals.keys().next().copied();
        match (a, b) {
            (Some(a), Some(b)) => Some(a.min(b)),
            (a, b) => a.or(b),
        }
    }

    /// Words written and totals from `from` to `to` (inclusive), grouped.
    pub fn range_history(&self, from: NaiveDate, to: NaiveDate, bucket: Bucket) -> RangeHistory {
        let (from, to) = if from <= to { (from, to) } else { (to, from) };
        let mut buckets = Vec::new();
        let mut start = bucket.start_of(from);
        while start <= to {
            let next = bucket.next(start);
            let (s, e) = (start.max(from), (next - chrono::Duration::days(1)).min(to));
            let written = self.daily.range(s..=e).map(|(_, w)| w).sum();
            let last = self.totals.range(..=e).next_back().map(|(_, t)| *t);
            buckets.push(HistoryBucket {
                start: s,
                end: e,
                written,
                manuscript: last.map(|t| t[0]),
                project: last.map(|t| t[1]),
            });
            start = next;
        }
        let days: Vec<(NaiveDate, i64)> =
            self.daily.range(from..=to).map(|(d, w)| (*d, *w)).collect();
        let total_written = days.iter().map(|(_, w)| w).sum();
        let span = (to - from).num_days() + 1;
        RangeHistory {
            from,
            to,
            bucket,
            buckets,
            total_written,
            days_written: days.iter().filter(|(_, w)| *w > 0).count() as u32,
            average_per_day: total_written as f64 / span as f64,
            best_day: days
                .iter()
                .filter(|(_, w)| *w > 0)
                .max_by_key(|(_, w)| *w)
                .copied(),
            first_day: self.first_day(),
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
    fn sprints() {
        let mut s = WritingStats::default();
        assert_eq!(s.sprint_summary(5).best_words, None);
        let at = chrono::Utc::now();
        for (m, w) in [(15.0, 300), (2.0, 80), (25.0, 450)] {
            s.add_sprint(Sprint {
                started: at,
                minutes: m,
                words: w,
                goal: Some(400),
            });
        }
        let sum = s.sprint_summary(2);
        assert_eq!(sum.count, 3);
        assert_eq!(sum.recent.len(), 2);
        assert_eq!(sum.recent[0].words, 450);
        assert_eq!(sum.total_words, 830);
        assert_eq!(sum.best_words, Some(450));
        // The 2-minute burst (40 wpm) is too short to count as best pace.
        assert_eq!(sum.best_pace, Some(20.0));
    }

    #[test]
    fn range_history_buckets() {
        let d = |s: &str| NaiveDate::parse_from_str(s, "%Y-%m-%d").unwrap();
        let mut s = WritingStats::default();
        s.record_on(d("2026-01-30"), 100);
        s.record_on(d("2026-02-02"), 50); // a Monday
        s.record_on(d("2026-02-03"), -20);
        s.record_on(d("2026-03-15"), 400);
        s.note_totals(d("2026-01-30"), 1100, 1500);
        s.note_totals(d("2026-03-15"), 1530, 2000);
        assert_eq!(s.first_day(), Some(d("2026-01-30")));

        let days = s.range_history(d("2026-02-01"), d("2026-02-04"), Bucket::Day);
        assert_eq!(days.buckets.len(), 4);
        assert_eq!(days.buckets[1].written, 50);
        assert_eq!(days.buckets[2].written, -20);
        // Totals carry forward from before the range.
        assert_eq!(days.buckets[0].manuscript, Some(1100));
        assert_eq!((days.total_written, days.days_written), (30, 1));
        assert_eq!(days.best_day, Some((d("2026-02-02"), 50)));

        let weeks = s.range_history(d("2026-01-28"), d("2026-02-08"), Bucket::Week);
        // Wed 28 Jan .. Sun 1 Feb, then Mon 2 .. Sun 8 Feb.
        assert_eq!(weeks.buckets.len(), 2);
        assert_eq!(
            (weeks.buckets[0].start, weeks.buckets[0].end),
            (d("2026-01-28"), d("2026-02-01"))
        );
        assert_eq!(
            (weeks.buckets[0].written, weeks.buckets[1].written),
            (100, 30)
        );

        let months = s.range_history(d("2026-01-01"), d("2026-03-31"), Bucket::Month);
        let w: Vec<i64> = months.buckets.iter().map(|b| b.written).collect();
        assert_eq!(w, [100, 30, 400]);
        assert_eq!(months.buckets[2].manuscript, Some(1530));
        let years = s.range_history(d("2025-06-01"), d("2026-12-31"), Bucket::Year);
        assert_eq!(years.buckets.len(), 2);
        assert_eq!(years.buckets[0].manuscript, None);

        // Reversed dates are accepted; auto picks a size for the span.
        assert_eq!(
            s.range_history(d("2026-02-04"), d("2026-02-01"), Bucket::Day)
                .buckets
                .len(),
            4
        );
        assert_eq!(
            Bucket::parse("auto", d("2026-01-01"), d("2026-01-31")),
            Bucket::Day
        );
        assert_eq!(
            Bucket::parse("auto", d("2026-01-01"), d("2026-06-30")),
            Bucket::Week
        );
        assert_eq!(
            Bucket::parse("", d("2020-01-01"), d("2026-06-30")),
            Bucket::Year
        );
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
