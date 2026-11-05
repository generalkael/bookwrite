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
                 "The pages for the week of the wreck had been cut out cleanly, with a blade.\n\nOnly one line survived on the stub:\n\n> *2nd Oct. Light failed at three bells. Not my doing.*\n\nShe read it twice. **Not my doing.** Then whose?"),
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

    // An imported image, to show off the file viewer.
    let files = s.dir.join(crate::storage::FILES_DIR);
    std::fs::create_dir_all(&files)?;
    std::fs::write(files.join("skerry-map.svg"), MAP_SVG)?;
    let map = p.add_node(research, None, NodeKind::Research, "Map of the Skerry")?;
    p.node_mut(map)?.file = Some("skerry-map.svg".into());
    p.node_mut(map)?.synopsis =
        "Sketch map: the light, the jetty, and where the Alba struck.".into();

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

    // Relationships for the map.
    let cast: Vec<_> = s.project.nodes[&s.project.root(RootRole::Characters)]
        .children
        .clone();
    if let [mara, tobias, ilse] = cast[..] {
        let r = &mut s.project.relations;
        let a = r.add(mara, tobias, "distrusts")?;
        r.update(
            a,
            "distrusts",
            "He knows what the letter means and won't say.",
        )?;
        r.add(tobias, ilse, "shares a secret with")?;
        r.add(ilse, mara, "older sister of")?;
        r.place(mara, 120.0, 220.0);
        r.place(tobias, 420.0, 90.0);
        r.place(ilse, 460.0, 330.0);
    }

    // An earlier draft of the opening, to show snapshot comparison.
    crate::storage::take_snapshot(
        &s.dir,
        scene_ids[0],
        "First draft",
        "The ferry left her on the jetty with a bag and a letter.\n\nThe lighthouse turned above her, sweeping the water.\n\nShe wondered if anyone was expecting her.",
    )?;

    s.save()?;
    Ok(s)
}

const MAP_SVG: &str = r##"<svg xmlns="http://www.w3.org/2000/svg" width="800" height="560" viewBox="0 0 800 560">
<rect width="800" height="560" fill="#cfdde3"/>
<g fill="none" stroke="#9fb8c2" stroke-width="1.5">
<path d="M0 470 Q200 440 400 480 T800 460"/><path d="M0 100 Q220 70 420 110 T800 90"/>
</g>
<path d="M250 170 C320 110 470 120 540 170 C610 220 600 330 520 380 C450 425 330 420 270 360 C210 300 200 220 250 170 Z" fill="#e8dfc6" stroke="#7a6a4f" stroke-width="3"/>
<path d="M300 250 C340 220 420 230 450 270" fill="none" stroke="#b5a37c" stroke-width="2" stroke-dasharray="6 5"/>
<circle cx="470" cy="200" r="14" fill="#b8462e" stroke="#4a2a1d" stroke-width="3"/>
<path d="M470 200 L640 120 L640 160 Z" fill="#f4d35e" opacity="0.6"/>
<rect x="268" y="330" width="60" height="10" fill="#7a6a4f" transform="rotate(-20 298 335)"/>
<path d="M660 360 l14 -14 m0 14 l-14 -14" stroke="#4a2a1d" stroke-width="4"/>
<g font-family="Georgia, serif" fill="#3b3224">
<text x="400" y="60" font-size="30" text-anchor="middle">The Skerry</text>
<text x="492" y="232" font-size="18">Skerry Light</text>
<text x="210" y="380" font-size="18">jetty</text>
<text x="667" y="398" font-size="18" font-style="italic" text-anchor="middle">wreck of the Alba</text>
<text x="400" y="530" font-size="14" text-anchor="middle" font-style="italic">sketched from the keeper's log, 1893</text>
</g>
</svg>
"##;

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
