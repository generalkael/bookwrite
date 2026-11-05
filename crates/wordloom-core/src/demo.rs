//! A small sample project that shows off the binder, metadata and timeline.

use std::path::Path;

use crate::model::{NodeKind, RootRole};
use crate::timeline::TrackKind;
use crate::{Result, Session};

pub fn create(parent: &Path) -> Result<Session> {
    let mut s = Session::create(parent, "The Lighthouse Keeper (Sample)", "Wordloom")?;
    let p = &mut s.project;
    let ms = p.root(RootRole::Manuscript);
    // Remove the starter chapter.
    let starter = p.nodes[&ms].children.clone();
    for c in starter {
        p.trash(c)?;
    }
    p.empty_trash();

    let labels: Vec<_> = p.labels.iter().map(|l| l.id).collect();
    let statuses: Vec<_> = p.statuses.iter().map(|x| x.id).collect();

    let chapters = [
        (
            "The Storm",
            vec![
                ("Arrival", "Mara reaches the island as the storm breaks.",
                 "The ferry left her on the jetty with a single bag and a letter she had read so many times the folds had gone soft.\n\nAbove her the lighthouse turned, patient and indifferent, sweeping the dark water."),
                ("The Keeper", "Old Tobias refuses to let her in.",
                 "\"No one sent for you,\" Tobias said, filling the doorway.\n\nMara held up the letter. The rain made the ink run."),
            ],
        ),
        (
            "The Log",
            vec![
                ("Night Watch", "Mara finds the keeper's log and a missing week.",
                 "The pages for the week of the wreck had been cut out cleanly, with a blade."),
                ("The Week Before", "Flashback: the night of the wreck.",
                 "The *Alba* came in too fast, lights dark, and Tobias watched it happen."),
            ],
        ),
        (
            "The Return",
            vec![("Confession", "Tobias tells the truth.", "")],
        ),
    ];
    let mut scene_ids = Vec::new();
    for (ci, (title, scenes)) in chapters.iter().enumerate() {
        let ch = p.add_node(ms, None, NodeKind::Folder, title)?;
        for (si, (st, syn, text)) in scenes.iter().enumerate() {
            let id = p.add_node(ch, None, NodeKind::Text, st)?;
            let n = p.node_mut(id)?;
            n.synopsis = syn.to_string();
            n.label = labels.get((ci + si) % labels.len()).copied();
            n.status = statuses.get(ci.min(statuses.len() - 1)).copied();
            n.target_words = Some(1500);
            if !text.is_empty() {
                p.set_text(id, text.to_string())?;
            }
            scene_ids.push(id);
        }
    }
    p.stats.manuscript_target = Some(80_000);

    let chars = p.root(RootRole::Characters);
    for (name, role, goal) in [
        (
            "Mara Quinn",
            "Protagonist",
            "Learn what happened to her father",
        ),
        (
            "Tobias Wren",
            "Antagonist / mentor",
            "Keep the secret of the wreck",
        ),
        (
            "Ilse Varga",
            "Ferry captain",
            "Protect the island's livelihood",
        ),
    ] {
        let id = p.add_node(chars, None, NodeKind::Character, name)?;
        let n = p.node_mut(id)?;
        n.fields.insert("Role".into(), role.into());
        n.fields.insert("Goal".into(), goal.into());
    }
    let places = p.root(RootRole::Places);
    let lh = p.add_node(places, None, NodeKind::Place, "Skerry Light")?;
    p.node_mut(lh)?
        .fields
        .insert("Atmosphere".into(), "Salt, brass, endless wind".into());

    let research = p.root(RootRole::Research);
    let r = p.add_node(
        research,
        None,
        NodeKind::Research,
        "Lighthouse operation, 1890s",
    )?;
    p.set_text(
        r,
        "Fresnel lenses; clockwork rotation wound every few hours; logbook kept nightly.".into(),
    )?;

    // Timeline: tracks from the cast, plus a plotline.
    s.sync_tracks();
    s.project.timeline.calendar_start = chrono::NaiveDate::from_ymd_opt(1893, 10, 2);
    let t = &mut s.project.timeline;
    let mara = t.tracks[0].id;
    let tobias = t.tracks[1].id;
    let ilse = t.tracks[2].id;
    let mystery = t.add_track("The Wreck of the Alba", TrackKind::Plotline);

    let wreck = t.add_event("Wreck of the Alba", mystery, -8, 1)?;
    let cut = t.add_event("Log pages cut out", tobias, -7, 0)?;
    let ferry = t.add_event("Ferry crossing", ilse, 0, 1)?;
    let arrive = t.add_event("Mara arrives", mara, 1, 1)?;
    let watch = t.add_event("Night watch", mara, 3, 2)?;
    let confess = t.add_event("Confession", tobias, 6, 1)?;
    t.add_marker(0, "Act I");
    t.add_marker(5, "Act III");

    let link = |t: &mut crate::Timeline,
                ev,
                scene,
                parts: Vec<uuid::Uuid>,
                deps: Vec<uuid::Uuid>|
     -> Result<()> {
        let mut e = t.event(ev).unwrap().clone();
        if let Some(sc) = scene {
            e.linked_nodes.push(sc);
        }
        e.participants = parts;
        e.depends_on = deps;
        t.upsert_event(e)
    };
    link(t, wreck, Some(scene_ids[3]), vec![tobias], vec![])?;
    link(t, cut, None, vec![], vec![wreck])?;
    link(t, ferry, None, vec![mara], vec![])?;
    link(t, arrive, Some(scene_ids[0]), vec![], vec![ferry])?;
    link(t, watch, Some(scene_ids[2]), vec![tobias], vec![arrive])?;
    link(t, confess, Some(scene_ids[4]), vec![mara], vec![watch])?;
    // Tobias's second scene overlaps the night watch: shows conflict detection.
    let keeper = t.add_event("Tobias tends the light", tobias, 1, 3)?;
    link(t, keeper, Some(scene_ids[1]), vec![], vec![])?;

    s.save()?;
    Ok(s)
}

#[cfg(test)]
mod tests {
    #[test]
    fn demo_builds_and_reloads() {
        let tmp = tempfile::tempdir().unwrap();
        let s = super::create(tmp.path()).unwrap();
        s.project.validate().unwrap();
        assert_eq!(s.project.timeline.tracks.len(), 5);
        assert!(!s.project.timeline.problems().is_empty());
        let again = crate::Session::open(&s.dir).unwrap();
        assert_eq!(again.project.timeline.events.len(), 7);
    }
}
