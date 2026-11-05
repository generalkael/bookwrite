//! Character relationships, drawn as a map.
//!
//! A relationship links two binder items (normally characters) with a short
//! label such as "sisters" or "rivals", read from `from` to `to`. The map
//! also remembers where the user placed each character.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::model::NodeId;
use crate::{Error, Result};

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Relationship {
    pub id: Uuid,
    pub from: NodeId,
    pub to: NodeId,
    pub label: String,
    #[serde(default)]
    pub notes: String,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Default)]
pub struct Relations {
    #[serde(default)]
    pub links: Vec<Relationship>,
    /// Where each item sits on the map (map units, origin top-left).
    #[serde(default)]
    pub positions: BTreeMap<NodeId, [f64; 2]>,
}

impl Relations {
    pub fn add(&mut self, from: NodeId, to: NodeId, label: &str) -> Result<Uuid> {
        if from == to {
            return Err(Error::Invalid(
                "a relationship needs two different people".into(),
            ));
        }
        let id = Uuid::new_v4();
        self.links.push(Relationship {
            id,
            from,
            to,
            label: label.trim().to_string(),
            notes: String::new(),
        });
        Ok(id)
    }

    pub fn update(&mut self, id: Uuid, label: &str, notes: &str) -> Result<()> {
        let r = self
            .links
            .iter_mut()
            .find(|r| r.id == id)
            .ok_or_else(|| Error::Invalid("no such relationship".into()))?;
        r.label = label.trim().to_string();
        r.notes = notes.to_string();
        Ok(())
    }

    /// Swap which side the label reads from ("A mentors B" → "B mentors A").
    pub fn reverse(&mut self, id: Uuid) -> Result<()> {
        let r = self
            .links
            .iter_mut()
            .find(|r| r.id == id)
            .ok_or_else(|| Error::Invalid("no such relationship".into()))?;
        std::mem::swap(&mut r.from, &mut r.to);
        Ok(())
    }

    pub fn remove(&mut self, id: Uuid) {
        self.links.retain(|r| r.id != id);
    }

    pub fn place(&mut self, node: NodeId, x: f64, y: f64) {
        if x.is_finite() && y.is_finite() {
            self.positions.insert(node, [x, y]);
        }
    }

    /// Drop everything about an item that has been deleted for good.
    pub fn forget_node(&mut self, node: NodeId) {
        self.links.retain(|r| r.from != node && r.to != node);
        self.positions.remove(&node);
    }

    pub fn for_node(&self, node: NodeId) -> impl Iterator<Item = &Relationship> {
        self.links
            .iter()
            .filter(move |r| r.from == node || r.to == node)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn add_update_reverse_forget() {
        let (a, b, c) = (Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4());
        let mut r = Relations::default();
        assert!(r.add(a, a, "self").is_err());
        let ab = r.add(a, b, " sisters ").unwrap();
        let bc = r.add(b, c, "rivals").unwrap();
        assert_eq!(r.links[0].label, "sisters");
        r.update(ab, "half-sisters", "Same father").unwrap();
        assert_eq!(r.links[0].notes, "Same father");
        r.reverse(ab).unwrap();
        assert_eq!((r.links[0].from, r.links[0].to), (b, a));
        assert_eq!(r.for_node(b).count(), 2);
        r.place(c, 10.0, 20.0);
        r.place(c, f64::NAN, 0.0);
        assert_eq!(r.positions[&c], [10.0, 20.0]);
        r.forget_node(c);
        assert!(r.positions.is_empty());
        assert_eq!(r.links.len(), 1);
        r.remove(ab);
        assert!(r.links.is_empty());
        assert!(r.update(bc, "x", "").is_err());
    }
}
