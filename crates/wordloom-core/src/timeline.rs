//! Story timeline / Gantt engine.
//!
//! A timeline is a set of *tracks* (rows: a character, a plotline, a place,
//! a theme…) and *events* (bars) placed on an abstract story clock measured in
//! integer units (days by default). An event lives on one primary track but can
//! involve other tracks as participants, link to manuscript scenes, and depend
//! on other events finishing first. The engine reports scheduling problems:
//! a character in two overlapping events, or an event that starts before
//! something it depends on has finished.

use std::collections::{HashMap, HashSet};

use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::model::NodeId;
use crate::{Error, Result};

#[derive(Serialize, Deserialize, Clone, Copy, PartialEq, Eq, Debug, Default)]
#[serde(rename_all = "snake_case")]
pub enum TrackKind {
    #[default]
    Character,
    Plotline,
    Place,
    Theme,
    Custom,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Track {
    pub id: Uuid,
    pub name: String,
    #[serde(default)]
    pub kind: TrackKind,
    pub color: String,
    /// Binder item (usually a character sheet) this track represents.
    #[serde(default)]
    pub linked_node: Option<NodeId>,
    #[serde(default)]
    pub notes: String,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Event {
    pub id: Uuid,
    pub title: String,
    pub track: Uuid,
    pub start: i64,
    /// Length in timeline units; 0 makes the event a milestone.
    #[serde(default)]
    pub duration: i64,
    /// Other tracks involved in this event (e.g. characters present).
    #[serde(default)]
    pub participants: Vec<Uuid>,
    /// Manuscript scenes that dramatise this event.
    #[serde(default)]
    pub linked_nodes: Vec<NodeId>,
    /// Events that must finish before this one starts.
    #[serde(default)]
    pub depends_on: Vec<Uuid>,
    #[serde(default)]
    pub color: Option<String>,
    #[serde(default)]
    pub notes: String,
}

impl Event {
    pub fn end(&self) -> i64 {
        self.start + self.duration.max(0)
    }

    pub fn involves(&self, track: Uuid) -> bool {
        self.track == track || self.participants.contains(&track)
    }

    fn overlaps(&self, other: &Event) -> bool {
        self.duration > 0
            && other.duration > 0
            && self.start < other.end()
            && other.start < self.end()
    }
}

/// A vertical line across the chart, e.g. "Act II" or "The war ends".
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Marker {
    pub id: Uuid,
    pub at: i64,
    pub title: String,
    #[serde(default = "default_marker_color")]
    pub color: String,
}

fn default_marker_color() -> String {
    "#cc0000".into()
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Timeline {
    /// Human name for one unit on the clock: "Day", "Hour", "Year"…
    #[serde(default = "default_unit")]
    pub unit_name: String,
    /// When the unit is days, the real/in-world date of unit 0, so the ruler
    /// can show dates.
    #[serde(default)]
    pub calendar_start: Option<NaiveDate>,
    #[serde(default)]
    pub tracks: Vec<Track>,
    #[serde(default)]
    pub events: Vec<Event>,
    #[serde(default)]
    pub markers: Vec<Marker>,
}

fn default_unit() -> String {
    "Day".into()
}

impl Default for Timeline {
    fn default() -> Self {
        Self {
            unit_name: default_unit(),
            calendar_start: None,
            tracks: Vec::new(),
            events: Vec::new(),
            markers: Vec::new(),
        }
    }
}

#[derive(Serialize, Clone, Debug, PartialEq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Problem {
    /// The same track is busy in two overlapping events.
    Overlap { track: Uuid, a: Uuid, b: Uuid },
    /// `event` starts before `depends_on` ends.
    Dependency { event: Uuid, depends_on: Uuid },
}

pub const PALETTE: [&str; 10] = [
    "#4e79a7", "#f28e2b", "#e15759", "#76b7b2", "#59a14f", "#edc948", "#b07aa1", "#ff9da7",
    "#9c755f", "#bab0ac",
];

impl Timeline {
    pub fn next_color(&self) -> String {
        PALETTE[self.tracks.len() % PALETTE.len()].to_string()
    }

    pub fn track(&self, id: Uuid) -> Option<&Track> {
        self.tracks.iter().find(|t| t.id == id)
    }

    pub fn event(&self, id: Uuid) -> Option<&Event> {
        self.events.iter().find(|e| e.id == id)
    }

    pub fn add_track(&mut self, name: &str, kind: TrackKind) -> Uuid {
        let t = Track {
            id: Uuid::new_v4(),
            name: name.into(),
            kind,
            color: self.next_color(),
            linked_node: None,
            notes: String::new(),
        };
        let id = t.id;
        self.tracks.push(t);
        id
    }

    pub fn upsert_track(&mut self, t: Track) {
        match self.tracks.iter_mut().find(|x| x.id == t.id) {
            Some(x) => *x = t,
            None => self.tracks.push(t),
        }
    }

    /// Remove a track, its own events, and any participation in others.
    pub fn remove_track(&mut self, id: Uuid) {
        self.tracks.retain(|t| t.id != id);
        let gone: HashSet<Uuid> = self
            .events
            .iter()
            .filter(|e| e.track == id)
            .map(|e| e.id)
            .collect();
        self.events.retain(|e| e.track != id);
        for e in &mut self.events {
            e.participants.retain(|p| *p != id);
            e.depends_on.retain(|d| !gone.contains(d));
        }
    }

    pub fn move_track(&mut self, id: Uuid, delta: i32) {
        if let Some(i) = self.tracks.iter().position(|t| t.id == id) {
            let j = (i as i64 + delta as i64).clamp(0, self.tracks.len() as i64 - 1) as usize;
            let t = self.tracks.remove(i);
            self.tracks.insert(j, t);
        }
    }

    pub fn add_event(
        &mut self,
        title: &str,
        track: Uuid,
        start: i64,
        duration: i64,
    ) -> Result<Uuid> {
        let e = Event {
            id: Uuid::new_v4(),
            title: title.into(),
            track,
            start,
            duration: duration.max(0),
            participants: Vec::new(),
            linked_nodes: Vec::new(),
            depends_on: Vec::new(),
            color: None,
            notes: String::new(),
        };
        let id = e.id;
        self.upsert_event(e)?;
        Ok(id)
    }

    /// Insert or replace an event after validating track references and
    /// dependency acyclicity.
    pub fn upsert_event(&mut self, mut e: Event) -> Result<()> {
        if self.track(e.track).is_none() {
            return Err(Error::Invalid(
                "event must belong to an existing track".into(),
            ));
        }
        e.duration = e.duration.max(0);
        e.participants
            .retain(|p| *p != e.track && self.track(*p).is_some());
        dedup(&mut e.participants);
        dedup(&mut e.linked_nodes);
        e.depends_on
            .retain(|d| *d != e.id && self.event(*d).is_some());
        dedup(&mut e.depends_on);

        let old = self.events.iter().position(|x| x.id == e.id);
        let snapshot = old.map(|i| self.events[i].clone());
        match old {
            Some(i) => self.events[i] = e,
            None => self.events.push(e),
        }
        if self.has_cycle() {
            // Roll back.
            match (old, snapshot) {
                (Some(i), Some(s)) => self.events[i] = s,
                _ => {
                    self.events.pop();
                }
            }
            return Err(Error::Invalid(
                "that dependency would create a cycle".into(),
            ));
        }
        Ok(())
    }

    pub fn remove_event(&mut self, id: Uuid) {
        self.events.retain(|e| e.id != id);
        for e in &mut self.events {
            e.depends_on.retain(|d| *d != id);
        }
    }

    pub fn move_event(&mut self, id: Uuid, start: i64, duration: i64) -> Result<()> {
        let e = self
            .events
            .iter_mut()
            .find(|e| e.id == id)
            .ok_or_else(|| Error::Invalid("no such event".into()))?;
        e.start = start;
        e.duration = duration.max(0);
        Ok(())
    }

    /// Shift every event that (transitively) depends on `id` so none start
    /// before their prerequisites end. Returns how many events moved.
    pub fn cascade(&mut self, id: Uuid) -> usize {
        let mut moved = 0;
        let mut queue = vec![id];
        while let Some(cur) = queue.pop() {
            let end = match self.event(cur) {
                Some(e) => e.end(),
                None => continue,
            };
            for e in self
                .events
                .iter_mut()
                .filter(|e| e.depends_on.contains(&cur))
            {
                if e.start < end {
                    e.start = end;
                    moved += 1;
                }
                queue.push(e.id);
            }
        }
        moved
    }

    pub fn add_marker(&mut self, at: i64, title: &str) -> Uuid {
        let m = Marker {
            id: Uuid::new_v4(),
            at,
            title: title.into(),
            color: default_marker_color(),
        };
        let id = m.id;
        self.markers.push(m);
        id
    }

    pub fn remove_marker(&mut self, id: Uuid) {
        self.markers.retain(|m| m.id != id);
    }

    fn has_cycle(&self) -> bool {
        let deps: HashMap<Uuid, &Vec<Uuid>> =
            self.events.iter().map(|e| (e.id, &e.depends_on)).collect();
        // 0 = unvisited, 1 = on stack, 2 = done
        let mut state: HashMap<Uuid, u8> = HashMap::new();
        fn visit(n: Uuid, deps: &HashMap<Uuid, &Vec<Uuid>>, st: &mut HashMap<Uuid, u8>) -> bool {
            match st.get(&n) {
                Some(1) => return true,
                Some(2) => return false,
                _ => {}
            }
            st.insert(n, 1);
            if let Some(ds) = deps.get(&n) {
                for d in ds.iter() {
                    if visit(*d, deps, st) {
                        return true;
                    }
                }
            }
            st.insert(n, 2);
            false
        }
        self.events.iter().any(|e| visit(e.id, &deps, &mut state))
    }

    /// Scheduling problems worth flagging on the chart.
    pub fn problems(&self) -> Vec<Problem> {
        let mut out = Vec::new();
        for t in self
            .tracks
            .iter()
            .filter(|t| t.kind == TrackKind::Character)
        {
            let mut evs: Vec<&Event> = self.events.iter().filter(|e| e.involves(t.id)).collect();
            evs.sort_by_key(|e| e.start);
            for (i, a) in evs.iter().enumerate() {
                for b in &evs[i + 1..] {
                    if b.start >= a.end() {
                        break;
                    }
                    if a.overlaps(b) {
                        out.push(Problem::Overlap {
                            track: t.id,
                            a: a.id,
                            b: b.id,
                        });
                    }
                }
            }
        }
        for e in &self.events {
            for d in &e.depends_on {
                if let Some(pre) = self.event(*d) {
                    if e.start < pre.end() {
                        out.push(Problem::Dependency {
                            event: e.id,
                            depends_on: *d,
                        });
                    }
                }
            }
        }
        out
    }

    /// (first start, last end) over all events and markers.
    pub fn range(&self) -> Option<(i64, i64)> {
        let starts = self
            .events
            .iter()
            .map(|e| e.start)
            .chain(self.markers.iter().map(|m| m.at));
        let ends = self
            .events
            .iter()
            .map(|e| e.end())
            .chain(self.markers.iter().map(|m| m.at));
        Some((starts.min()?, ends.max()?))
    }

    /// Linked scenes in story-chronological order (by the earliest event that
    /// references them), for comparing against manuscript order.
    pub fn chronology(&self) -> Vec<(NodeId, i64)> {
        let mut first: HashMap<NodeId, i64> = HashMap::new();
        for e in &self.events {
            for n in &e.linked_nodes {
                let v = first.entry(*n).or_insert(e.start);
                *v = (*v).min(e.start);
            }
        }
        let mut v: Vec<_> = first.into_iter().collect();
        v.sort_by_key(|(id, t)| (*t, *id));
        v
    }

    pub fn events_for_node(&self, node: NodeId) -> Vec<&Event> {
        self.events
            .iter()
            .filter(|e| e.linked_nodes.contains(&node))
            .collect()
    }

    /// Drop references to a binder item that no longer exists.
    pub fn forget_node(&mut self, node: NodeId) {
        for e in &mut self.events {
            e.linked_nodes.retain(|n| *n != node);
        }
        for t in &mut self.tracks {
            if t.linked_node == Some(node) {
                t.linked_node = None;
            }
        }
    }
}

fn dedup<T: PartialEq + Copy>(v: &mut Vec<T>) {
    let mut out: Vec<T> = Vec::with_capacity(v.len());
    for x in v.iter() {
        if !out.contains(x) {
            out.push(*x);
        }
    }
    *v = out;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn overlaps_and_dependencies() {
        let mut t = Timeline::default();
        let alice = t.add_track("Alice", TrackKind::Character);
        let bob = t.add_track("Bob", TrackKind::Character);
        let plot = t.add_track("Heist", TrackKind::Plotline);
        let a = t.add_event("Training", alice, 0, 5).unwrap();
        let b = t.add_event("Recon", plot, 3, 4).unwrap();
        // Alice also takes part in the recon -> overlap on Alice's row.
        let mut ev = t.event(b).unwrap().clone();
        ev.participants = vec![alice, bob, bob, plot];
        t.upsert_event(ev).unwrap();
        assert_eq!(t.event(b).unwrap().participants, vec![alice, bob]);
        let probs = t.problems();
        assert_eq!(probs, vec![Problem::Overlap { track: alice, a, b }]);

        // Recon depends on training: dependency violation until cascaded.
        let mut ev = t.event(b).unwrap().clone();
        ev.depends_on = vec![a];
        t.upsert_event(ev).unwrap();
        assert!(t.problems().contains(&Problem::Dependency {
            event: b,
            depends_on: a
        }));
        assert_eq!(t.cascade(a), 1);
        assert_eq!(t.event(b).unwrap().start, 5);
        assert!(t.problems().is_empty());
        assert_eq!(t.range(), Some((0, 9)));
    }

    #[test]
    fn rejects_cycles() {
        let mut t = Timeline::default();
        let tr = t.add_track("X", TrackKind::Plotline);
        let a = t.add_event("A", tr, 0, 1).unwrap();
        let b = t.add_event("B", tr, 1, 1).unwrap();
        let mut eb = t.event(b).unwrap().clone();
        eb.depends_on = vec![a];
        t.upsert_event(eb).unwrap();
        let mut ea = t.event(a).unwrap().clone();
        ea.depends_on = vec![b];
        assert!(t.upsert_event(ea).is_err());
        assert!(t.event(a).unwrap().depends_on.is_empty(), "rolled back");
    }

    #[test]
    fn removing_track_cleans_up() {
        let mut t = Timeline::default();
        let x = t.add_track("X", TrackKind::Character);
        let y = t.add_track("Y", TrackKind::Character);
        let ex = t.add_event("ex", x, 0, 1).unwrap();
        let ey = t.add_event("ey", y, 2, 1).unwrap();
        let mut e = t.event(ey).unwrap().clone();
        e.participants = vec![x];
        e.depends_on = vec![ex];
        t.upsert_event(e).unwrap();
        t.remove_track(x);
        let e = t.event(ey).unwrap();
        assert!(e.participants.is_empty() && e.depends_on.is_empty());
        assert_eq!(t.events.len(), 1);
    }

    #[test]
    fn chronology_orders_by_story_time() {
        let mut t = Timeline::default();
        let tr = t.add_track("X", TrackKind::Plotline);
        let (n1, n2) = (Uuid::new_v4(), Uuid::new_v4());
        let late = t.add_event("late", tr, 10, 1).unwrap();
        let early = t.add_event("early", tr, 1, 1).unwrap();
        for (ev, n) in [(late, n1), (early, n2)] {
            let mut e = t.event(ev).unwrap().clone();
            e.linked_nodes.push(n);
            t.upsert_event(e).unwrap();
        }
        assert_eq!(t.chronology(), vec![(n2, 1), (n1, 10)]);
        t.forget_node(n1);
        assert_eq!(t.chronology().len(), 1);
    }
}
