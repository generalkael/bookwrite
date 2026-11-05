# Wordloom

A writing studio for novels and other long-form work, built in **Rust** with a **Qt 6 / QML** interface.
Wordloom is organised around the same ideas as Scrivener (a binder, index cards, an outliner,
snapshots, compile) without copying it, and adds a **story-timeline Gantt chart** for plotting
characters, events and plotlines in time.

It runs on Linux today. The code is written to build unchanged on Windows and macOS, since Qt and
Rust both support those platforms. CI currently builds Linux only: Windows CI is paused
until the Linux version is complete (it passed when last enabled), and macOS CI waits on a Qt
version that supports the macOS 26 SDK.

## Features

| Area | What you get |
|---|---|
| **Binder** | A project tree with fixed sections (Manuscript, Characters, Places, Research, Notes, Trash). Drag and drop, inline rename (F2), keyboard moves (Ctrl+↑/↓ to move, Ctrl+←/→ to outdent/indent), duplicate, split at cursor, merge, convert type, trash/empty trash. |
| **Editor** | A distraction-light paper page with adjustable font size and page width, Markdown preview, and typewriter scrolling. **Composite mode**: select a folder and every document inside it appears as one continuous manuscript you can edit, with each part saving separately. |
| **Focus mode** | F11 hides everything except the page. |
| **Corkboard** | Index cards with label colour strips, status stamps and word counts. Edit titles and synopses on the card, resize cards, reorder them from the context menu. |
| **Outliner** | A table of the whole subtree: synopsis, label, status, words, target and progress, all editable in place. |
| **Inspector** | Synopsis, label, status, keywords, word target, include-in-compile, **character sheets / place sheets / scene facts** (custom fields), document notes, snapshots, and the timeline events linked to the item. |
| **Undo & redo** | Project-wide: ↶/↷ on the toolbar and Edit ▸ Undo/Redo (Ctrl+Z / Ctrl+Shift+Z when you're not typing in a text box) reverse binder moves, renames, trash and empty trash, replace-all, metadata, labels, targets, and every timeline edit. The menu names the step (“Undo Move Event”). Typing has the editor's own undo, so undoing an old change never throws away text written since. Up to 200 steps per session. |
| **Snapshots** | Named versions per document. Restoring one first saves the current text as a snapshot, so you can't lose work that way. |
| **Search & replace** | Searches titles, text, synopses, notes and keywords across the project, with snippets. Replace-all works across every document. |
| **Compile** | Exports the manuscript to Markdown, print-styled HTML, or plain text, with a live preview. Options cover the title page, chapter headings and numbering, scene headings, and the scene separator. |
| **Statistics & targets** | Word counts for the manuscript and the whole project, words written today, writing streak, reading time, a 30-day history chart, a manuscript target with deadline (and the words per day needed to hit it), and a daily session target. |
| **Labels & statuses** | Editable lists with colours. |
| **Themes** | Follows the system light/dark setting, or you can force either one. |

### The timeline (Gantt)

- **Tracks** are rows: characters, plotlines, places, themes, or anything else. **⟳ Sync Cast**
  creates a track for every character and place in the binder and keeps the names in step.
- **Events** are bars on a story clock measured in whole units ("Day" by default; it can be Hour,
  Year, Chapter, and so on). Set a day-0 date and the ruler shows calendar dates. An event with
  length 0 is a **milestone**.
- **Participants**: an event sits on one track but can involve others. It shows as an outlined
  "ghost" bar on each participant's row, so you can see where everyone is at any moment.
- **Dependencies** ("happens after") are drawn as arrows. With **Cascade** on, moving an event
  pushes the events that depend on it later.
- **Conflict detection** marks a character who is in two overlapping events, or an event that
  starts before something it depends on has finished. The ⚠ button lists every problem in plain
  language.
- **Scene links**: link events to manuscript scenes, or right-click an event and choose **Write
  This Scene** to create the scene. The **Chronology** panel lists scenes in story order next to
  their manuscript position and flags (↺) the ones told out of sequence.
- **Markers** draw vertical lines for act breaks or turning points.
- Drag a bar to move it, drag its right edge to change its length, double-click it to edit, and
  double-click an empty spot on a row to add an event there. Ctrl+scroll zooms around the cursor,
  and **Fit** shows the whole timeline.

## Building

You need Rust (stable), Qt 6.5 or later with Qt Quick / Quick Controls 2 / Qt Shapes, and a C++
compiler. The build finds Qt through `qmake`. If it isn't on your `PATH`, set `QMAKE=/path/to/qmake6`.

```sh
cargo run --release -p wordloom                    # start
cargo run --release -p wordloom -- path/to/Book.wordloom   # open a project
cargo test --workspace                             # core test-suite (no Qt needed at runtime)
```

**Linux:** install your distribution's Qt 6 packages (Arch: `qt6-base qt6-declarative`; Debian/Ubuntu:
`qt6-base-dev qt6-declarative-dev qml6-module-qtquick-controls qml6-module-qtquick-dialogs
qml6-module-qtquick-layouts qml6-module-qtquick-shapes qml6-module-qtcore`).

**Windows:** install Qt 6 with the online installer (MSVC kit), then set
`QMAKE=C:\Qt\6.x.x\msvc2022_64\bin\qmake.exe`. After building, run `windeployqt --qmldir crates/wordloom-app/qml target\release\wordloom.exe` to bundle the Qt libraries.

**macOS:** `brew install qt` (or use the Qt installer), then `macdeployqt` to bundle the libraries.

To try it out, click **Explore the Sample** on the start screen. It creates a short sample novel
in `~/Documents/Wordloom` with chapters, characters, labels, and a timeline that includes
dependencies and a deliberate conflict.

## Project format

A project is a folder, `Title.wordloom/`, made only of plain text, so it works with git, Dropbox
and diff tools, and you can still read it without Wordloom:

```
Title.wordloom/
  project.json          binder tree, metadata, labels, statuses, timeline, stats
  content/<uuid>.md     one Markdown file per document that has text
  snapshots/<uuid>.json saved versions of a document
  backups/              rolling copies of project.json (one per 10 minutes, last 20 kept)
```

Every write goes to a temporary file that is then renamed into place, so a crash can't leave a
file half-written. Wordloom autosaves every 15 seconds while there are unsaved changes, and
saves again when it closes.

## Architecture

```
crates/
  wordloom-core/   pure Rust, no Qt: all behaviour, fully unit-tested
    model.rs       binder arena (flat map + ordered children), tree operations, metadata
    timeline.rs    Gantt engine: tracks, events, participants, dependencies,
                   cycle rejection, cascade, conflict detection, chronology
    storage.rs     bundle format, atomic writes, backups, snapshots
    compile.rs     manuscript → Markdown / HTML / plain text
    search.rs      search & case-insensitive replace
    stats.rs       word counting, targets, daily history, streaks
    history.rs     project-wide undo/redo (structure snapshots + text diffs)
    session.rs     an open project + its JSON-shaped API
    api.rs         call(method, argsJson) dispatcher used by the UI
    demo.rs        the sample project
  wordloom-app/    the Qt front end
    src/controller.rs  one cxx-qt QObject (QML singleton `Wordloom`) wrapping api::App
    qml/*.qml          all views and dialogs
```

The UI talks to Rust through a single invokable, `Wordloom.call(method, argsJson)`, which the
`Api` QML singleton wraps. Any call that changes data bumps a `revision` property, and each view
re-queries what it shows when that happens. This keeps the FFI surface tiny: adding a feature is
a Rust method, one line in `api.rs`, and some QML.

Developer aid: `wordloom PROJECT --screenshots=DIR` opens each view and dialog in turn, saves a
PNG of each, and quits. It also works headless with `QT_QPA_PLATFORM=offscreen`.

## Roadmap

- EPUB and DOCX export built in (today: HTML, then Pandoc or Calibre)
- Rich-text styling (today: plain text with Markdown)
- Side-by-side comparison of snapshots
- Split editor (two documents at once), and an image/PDF viewer for research files
- A relationship map of characters, and swim-lane grouping on the timeline
- Packaged installers (AppImage/Flatpak, MSI, DMG)

## License

Wordloom is released under the [MIT License](LICENSE).
