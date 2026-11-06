# Wordloom

A writing studio for novels and other long-form work, built in **Rust** with a **Qt 6 / QML** interface.
Wordloom is organised around the same ideas as Scrivener (a binder, index cards, an outliner,
snapshots, compile) without copying it, and adds a **story-timeline Gantt chart** for plotting
characters, events and plotlines in time.

It runs on Linux today. The code is written to build unchanged on Windows and macOS, since Qt and
Rust both support those platforms. CI currently builds Linux only: Windows CI is paused
until the Linux version is complete (it passed when last enabled), and macOS CI waits on a Qt
version that supports the macOS 26 SDK.

![Wordloom's editor with styled Markdown, the binder and the Details panel](docs/screenshots/editor.png)

More screenshots: [timeline](docs/screenshots/timeline.png) ·
[relationship map](docs/screenshots/relations.png) · [corkboard](docs/screenshots/corkboard.png) ·
[split editor](docs/screenshots/split.png).

## Features

| Area | What you get |
|---|---|
| **Binder** | A project tree with fixed sections (Manuscript, Characters, Places, Research, Notes, Trash). Drag and drop, inline rename (F2), keyboard moves (Ctrl+↑/↓ to move, Ctrl+←/→ to outdent/indent), duplicate, split at cursor, merge, convert type, trash/empty trash. Clicking a document opens it in the editor; clicking a folder with no text of its own shows its contents on the corkboard. Items with a word target (set in the Details panel) show a small progress bar, green once reached; hover it for the numbers. |
| **Editor** | A distraction-light paper page that fills the window (or a fixed column width: ⇔ cycles Fit, 560 … 1100 px), adjustable font size, Markdown preview, and typewriter scrolling. The page scrolls to keep the caret in view as you type. In a narrow pane the editor's view and format buttons move into a ⋯ menu. **Styled Markdown**: headings, **bold**, *italic*, block quotes and scene breaks are shown styled as you type, with their Markdown markers faded, while the file on disk stays plain Markdown. The format bar (B, I, H, “, * * *, { } for a comment) and Ctrl+B / Ctrl+I add or remove the markers for you (Ctrl+Z undoes them), and View ▸ Styled Markdown turns styling off. **Composite mode**: select a folder and every document inside it appears as one continuous manuscript you can edit, with each part saving separately. **Split editor** (◫ or Ctrl+\\, or *Open in Split Editor* in the binder): keep one document beside the main view while you work elsewhere; ⇄ swaps the two. The same document can be open in both panes. Picking an item in the binder (or with Go to…) opens it in whichever pane you were last typing in, marked by a thin accent line on that pane's header; the binder highlight, the Details panel, the word count and commands like Snapshot and Duplicate follow that pane's document. |
| **Appearances** | Select a character or place and the Details panel shows **Appears in**: every manuscript document that mentions it, with how many times, in manuscript order. Click one to open it with the name in the find bar (F3 steps through the mentions). Wordloom looks for the title, the first name of a multi-word name (“Mara” for “Mara Quinn”) and the names in the *Also known as* field (comma-separated), as whole words with matching case, so “Rose” isn't found in “rose from her chair”. Text in comments doesn't count. |
| **Inline comments** | Notes to yourself inside the text, written `{>> like this <<}`. Edit ▸ Insert Comment (Ctrl+Alt+M) or { } on the format bar adds one at the caret. They're highlighted in the editor and left out of word counts, compile, reading mode and the preview, so you can leave “check this date” right where it matters. The Details panel's Notes tab lists every comment in the item (or the folder's items); click one to jump to it. |
| **Repeated words** | View ▸ Highlight Repeated Words tints a word in soft blue when it's used again within about 40 words in the same paragraph (“she climbed toward the lamp room, and the lamp room…”), so echoes stand out while you revise. Both uses are marked. Words shorter than four letters, common words (“that”, “said”, “would”, “through”), capitalised words (names, sentence starts) and text inside comments are ignored; case and curly or straight apostrophes don't matter. It updates as you type and is off by default. |
| **Current-line highlight** | View ▸ Highlight Current Line shows a bar across the page behind the line you're typing on, following the caret (on the line as wrapped on screen). Choose its colour in View ▸ Line Highlight Colour: amber, blue, green, rose or grey, or *Custom Colour…* for any colour and transparency. The presets are translucent, so they work in light and dark themes. |
| **Name completion** | Start typing a character's or place's name with a capital letter (“Tob”) and the editor offers the names it could be (“Tobias”, “Tobias Wren”) just under the caret. Tab takes the highlighted one, ↑ ↓ choose another, Esc (or just carrying on typing) dismisses them. It knows titles, first names and the *Also known as* field, and completes names of more than one word (“Mara Q” → “Mara Quinn”). View ▸ Complete Names turns it off. |
| **Smart punctuation** | As you type, "quotes" become “curly quotes”, apostrophes become ’, `--` becomes an em dash — and `...` an ellipsis …, as in a typeset book. Whether a quote opens or closes depends on what's around it, so “Wait—” closes properly. A line of dashes (a scene break) and text inside comments are left as typed. View ▸ Smart Punctuation turns it off; Edit ▸ Convert to Smart Punctuation converts a whole document you pasted or imported (Ctrl+Z undoes it). |
| **Focus mode** | F11 hides everything except the page. |
| **Reading mode** | ❦ Read (Ctrl+7) shows the whole manuscript, or just the selected chapter, as a read-only book page: title page, centred chapter headings, scene breaks and book-style indents, built from the same compile step as export. Adjust the text size and column width, page with Page Up / Down or Space, and double-click (or *Edit*) to go back to writing. |
| **Corkboard** | Index cards with label colour strips, status stamps and word counts. Edit titles and synopses on the card, resize cards, reorder them from the context menu. |
| **Outliner** | A table of the whole subtree: synopsis, label, status, words, target and progress, all editable in place. See [Using the outliner](#using-the-outliner). |
| **Details panel** | The right-hand panel (Show/Hide Details, Ctrl+Alt+I): synopsis, label, status, keywords, word target, include-in-compile, **character sheets / place sheets / scene facts** (custom fields), document notes and inline comments, snapshots, and the timeline events linked to the item. |
| **Undo & redo** | Project-wide: ↶/↷ on the toolbar and Edit ▸ Undo/Redo (Ctrl+Z / Ctrl+Shift+Z when you're not typing in a text box) reverse binder moves, renames, trash and empty trash, replace-all, metadata, labels, targets, and every timeline edit. The menu names the step (“Undo Move Event”). Typing has the editor's own undo, so undoing an old change never throws away text written since. Up to 200 steps per session. |
| **Relationship map** | ◇ Relations (Ctrl+6) shows every character as a card you can drag around, with labelled arrows for how they relate (“Mara *distrusts* Tobias”). Add a relationship from the toolbar or a card's right-click menu, and click a label to edit it, add notes, swap its direction or delete it. The Details panel lists each character's relationships. |
| **Spell checking** | Misspelled words are marked in red as you type (View ▸ Check Spelling, F7). Right-click one for suggestions or *Add to Dictionary*. The names of your characters, places and timeline tracks are always accepted. Wordloom uses your system's Hunspell dictionary for your language (`/usr/share/hunspell`), or a built-in US English one; added words are kept in `~/.config/wordloom/dictionary.txt`. |
| **Writing sprints** | Project ▸ Writing Sprint… (Ctrl+Shift+R): pick a length (5–60 minutes or your own) and an optional word goal, and write. The status bar counts down and shows words written so far; pause, finish early or cancel from the sprint window. Finished sprints are kept in the project, with your totals, best sprint and best pace. |
| **Text analysis** | Project ▸ Text Analysis… (Ctrl+Shift+A) looks at the whole manuscript or the selected item for habits worth a look when revising: your **most used words** (common words like “the” and “said” left out), **repeated three-word phrases** (“turned to look”), **-ly adverbs**, the **longest sentences**, the average sentence length, and how much of the text is **dialogue**. Click a word or phrase to search the project for it, or a long sentence to open its document there. Comments and Markdown markers are ignored, and the word total matches Writing Statistics. |
| **Name generator** | Project ▸ Name Generator… (Ctrl+Shift+G) suggests character names in English, Irish & Scottish, Nordic, Slavic, Italian/Spanish/French or invented fantasy styles, feminine, masculine or either. Each name has *Add as Character*. |
| **Import Manuscript** | File ▸ Import Manuscript… brings in a book you've already written, from Word (.docx), Markdown or plain text, and opens it on the corkboard. Chapters start at headings (Word's *Heading 1*, Markdown `#`) or lines like “Chapter 12”, “CHAPTER TWELVE: The Wreck”, “Part II” or “Prologue”; scenes start at *Heading 2* (which becomes the scene's title) or at scene breaks (`* * *`, `#`, `~`, `---`). Each chapter becomes a folder of scene documents inside a folder named after the book, italics and bold are kept, and text before the first chapter goes in *Front Matter*. Word's heading styles are recognised in any language. Edit ▸ Undo removes the whole import. |
| **Research files** | Import images and PDFs (File ▸ Import File…, or drop files on the binder). They're copied into the project and shown in the editor: images with fit / zoom, PDFs page by page. Other file types open in your default app. |
| **Snapshots** | Named versions per document. Restoring one first saves the current text as a snapshot, so you can't lose work that way. **Compare…** shows a snapshot side by side with the current text (or another snapshot): paragraphs line up, changed words are highlighted, and a count shows words added and removed. |
| **Backups** | Saves happen automatically, with rolling copies of the project file inside the project. **File ▸ Back Up to Zip…** packs the whole project into one dated `.zip`, and **File ▸ Automatic Backups…** can do that every time a project closes, into a folder of your choice, skipping unchanged projects and keeping the newest 10 (see [Project format](#project-format)). |
| **Go to…** | Ctrl+P opens a quick switcher: type part of an item's title, or just some of its letters in order (“nght wtch” finds Night Watch), use ↑ ↓, and press Enter to open it. It finds items inside collapsed folders and in every section (trashed items come last), and opens the binder down to the item. With nothing typed it lists the items you changed most recently. |
| **Search & replace** | Searches titles, text, synopses, notes and keywords across the project, with snippets. Replace-all works across every document. **In one document**: Ctrl+F opens a find bar in the editor and Ctrl+H adds replace, with next / previous (Enter, Shift+Enter, F3), a match count, *Whole words* (on by default, so “the” leaves “then” alone) and *Match case*. In a folder's composite view it searches every part; Ctrl+Z undoes replacements. |
| **Compile** | Exports the manuscript to EPUB (with a table of contents, one file per chapter), DOCX (named styles, chapters on new pages), **PDF**, Markdown, print-styled HTML, or plain text, with a live preview. No Pandoc, Calibre or LaTeX needed. PDF comes in two styles: **Book** (title page, justified text, chapters on new pages, page numbers) and **Manuscript**, the standard format for submitting to agents and editors: double spaced in Courier or Times, your contact details and “about 80,000 words” on the title page, each chapter a third of the way down a new page, “Surname / TITLE / page” at the top right of every page, and END at the close. Choose US Letter or A4; your contact details are remembered for next time. Options cover the title page, chapter headings and numbering, scene headings, and the scene separator. |
| **Story bible** | File ▸ Export Story Bible… writes every character and place into one document to share with an editor or co-writer, or to start the next book in a series: Word (.docx), web page (.html), Markdown or plain text, chosen by the file type. Each entry has its synopsis, custom fields (*Role*, *Goal*, …), sheet text, notes, relationships from the relationship map (“Mara Quinn *distrusts* Tobias Wren”) and the scenes it appears in, with how often. Folders inside Characters or Places become sub-headings; items in the Trash are left out. |
| **Statistics & targets** | Word counts for the manuscript and the whole project, words written today, writing streak, reading time, a 30-day history chart, a manuscript target with deadline (and the words per day needed to hit it), and a daily session target. A ring in the status bar fills as you write today and turns green, with a notice, when you reach the goal. **Word Count History** (click the ring, Project ▸ Word Count History…, or Ctrl+Shift+H) opens a window charting words written per day, week, month or year, or the manuscript / project total as a line. Presets: Daily (30 days), Weekly (26 weeks), Monthly (24 months), 90 days, Yearly and Lifetime; or pick your own From / To dates and grouping, and step the range with ‹ ›. It shows words written in the range, days written, the daily average and your best day, with the daily goal as a dashed line. |
| **Labels & statuses** | Editable lists with colours. |
| **Themes** | Follows the system light/dark setting, or you can force either one. |

### Using the outliner

The outliner shows a part of your book as a table, one row per item, so you can plan it, see its
shape and update it without opening each scene.

**Opening it.** Select a folder in the binder (a chapter, a part, or the Manuscript itself), then
click **☰ Outliner** on the toolbar, choose View ▸ Outliner, or press **Ctrl+3**. The table lists
everything inside that folder, at every level: sub-folders are bold, and each level is indented a
step further. While the outliner is showing, clicking another folder in the binder switches the
table to that folder. Clicking a document opens it in the editor. The Characters, Places,
Research and Notes sections work the same way.

**The columns:**

| Column | What it shows | How to change it |
|---|---|---|
| Title | The item's name and type icon | Double-click to open the item in the editor. Rename and reorder in the binder (F2, Ctrl+↑ ↓). |
| Synopsis | The one-line summary, the same text as the corkboard card and the Details panel | Click and type. It's saved when you press Enter or click elsewhere. |
| Label | The item's label (e.g. a POV character or plot thread) | Pick from the list; *No Label* clears it. |
| Status | Where the item stands (To Do, First Draft, Revised…) | Pick from the list; *No Status* clears it. |
| Words | Words in the item **plus everything inside it**, so a chapter shows the whole chapter | Updates as you write. |
| Target | The item's word target | Type a number and press Enter; clear it (or type 0) to remove the target. |
| Progress | A bar from 0 to the target (full once you reach it) | Shown only for items with a target. |

Labels and statuses, and their colours, are edited in File ▸ Project Settings…. Every change made
in the outliner can be undone with Edit ▸ Undo (“Undo Edit Synopsis”, “Undo Set Word Target”).

**Planning a book with it:**

1. In the binder, make a folder per chapter (+ Folder) and an empty document per scene you have in
   mind (+ Document). Titles can be rough.
2. Select the Manuscript and press Ctrl+3. Go down the Synopsis column writing one line per scene:
   what happens and why it matters.
3. Give scenes (or whole chapters) a Target, and set each Status to *To Do*.
4. Use Label for whatever you want to track across the book, such as point of view or subplot.
   Its colour shows on corkboard cards and as a dot on binder rows, so you can see the balance at a
   glance.
5. As you draft, the Words and Progress columns fill in. Change Status as scenes move from first
   draft to revised. Double-click any title to jump in and write.

The **corkboard** (Ctrl+2) shows the same synopses, labels and statuses as index cards for one
folder at a time; right-click a card to move it earlier or later. The outliner is better for
seeing the whole book at once.

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
- **Lanes** groups the tracks into swim lanes by kind (Characters, Places, Plotlines, Themes,
  Other). Click a lane's header to collapse it; ▴/▾ then move a track within its lane.
- Drag a bar to move it, drag its right edge to change its length, double-click it to edit, and
  double-click an empty spot on a row to add an event there. Ctrl+scroll zooms around the cursor,
  and **Fit** shows the whole timeline.

## Installing on Linux

Every push to `main` builds two packages. Download them from the artifacts of the latest
[CI run](https://github.com/generalkael/wordloom/actions/workflows/ci.yml).

**AppImage:** a single file that runs on most distributions from Ubuntu 22.04 on. It bundles Qt,
including the PDF viewer and Wayland and X11 support.

```sh
chmod +x Wordloom-x86_64.AppImage
./Wordloom-x86_64.AppImage
```

**Flatpak:** runs on the KDE runtime from Flathub, which `flatpak` installs for you, and shows up
in your app launcher. The sandbox can read and write your home folder, where projects live.

```sh
flatpak install --user Wordloom.flatpak
flatpak run io.github.generalkael.Wordloom
```

To build them yourself, run `packaging/linux/build-appimage.sh` (it downloads linuxdeploy into
`.appimage-tools/`), or
`flatpak-builder --user --install --install-deps-from=flathub --force-clean build-dir packaging/flatpak/io.github.generalkael.Wordloom.yml`.
The desktop entry, icon and AppStream metadata are in `packaging/linux/` and use the app ID
`io.github.generalkael.Wordloom`.

The Flatpak build is offline, as Flathub requires: every crate is listed with its checksum in
`packaging/flatpak/cargo-sources.json`. After changing `Cargo.lock`, regenerate it with
`packaging/flatpak/cargo-sources.py`; CI fails if it is out of date.

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
qml6-module-qtquick-layouts qml6-module-qtquick-shapes qml6-module-qtcore`). The PDF viewer also
needs Qt PDF (Arch: `qt6-webengine`; Debian/Ubuntu: `qml6-module-qtquick-pdf`); without it, PDFs
open in your default app instead.

**Windows:** install Qt 6 with the online installer (MSVC kit), then set
`QMAKE=C:\Qt\6.x.x\msvc2022_64\bin\qmake.exe`. After building, run `windeployqt --qmldir crates/wordloom-app/qml target\release\wordloom.exe` to bundle the Qt libraries.

**macOS:** `brew install qt` (or use the Qt installer), then `macdeployqt` to bundle the libraries.

To try it out, click **Explore the Sample** on the start screen. It creates a short sample novel
in `~/Documents/Wordloom` with chapters, characters, labels, an imported map in Research, a
snapshot of an earlier draft to compare, a relationship map, and a timeline that includes
dependencies and a deliberate conflict.

## Keyboard shortcuts

Ctrl is ⌘ on macOS.

| Action | Keys |
|---|---|
| New project / open / save | Ctrl+N (start screen) · Ctrl+O · Ctrl+S |
| New document / new folder | Ctrl+N · Ctrl+Shift+N |
| Duplicate · split at cursor · merge with next | Ctrl+D · Ctrl+K · Ctrl+Shift+M |
| Undo / redo project changes (outside text boxes) | Ctrl+Z · Ctrl+Shift+Z |
| Import file into Research | Ctrl+Shift+I |
| Take snapshot | Ctrl+5 |
| Compile / export | Ctrl+Shift+E |
| Go to an item by name | Ctrl+P |
| Find in project · writing statistics | Ctrl+Shift+F · Ctrl+Shift+T |
| Name generator | Ctrl+Shift+G |
| Word count history | Ctrl+Shift+H |
| Writing sprint | Ctrl+Shift+R |
| Text analysis | Ctrl+Shift+A |
| Spell checking on / off | F7 |
| Find · replace in the open document (next / previous: F3 · Shift+F3) | Ctrl+F · Ctrl+H |
| Editor · corkboard · outliner · timeline | Ctrl+1 · Ctrl+2 · Ctrl+3 · Ctrl+4 |
| Relationship map · reading mode | Ctrl+6 · Ctrl+7 |
| Split editor on / off | Ctrl+\\ |
| Focus mode (leave with Esc) | F11 |
| Show / hide the Details panel | Ctrl+Alt+I |
| Bold · italic (in the editor) | Ctrl+B · Ctrl+I |
| Insert an inline comment | Ctrl+Alt+M |
| Larger / smaller editor text | Ctrl++ · Ctrl+− |
| Zoom an image in the viewer | Ctrl+scroll |
| **Binder:** move between items · expand/collapse | ↑ ↓ · → ← |
| **Binder:** move item up/down · indent/outdent | Ctrl+↑ ↓ · Ctrl+→ ← |
| **Binder:** open · rename · move to trash | Enter · F2 · Delete |

## Project format

A project is a folder, `Title.wordloom/`. Apart from files you import, it is all plain text, so it
works with git, Dropbox and diff tools, and you can still read it without Wordloom:

```
Title.wordloom/
  project.json          binder tree, metadata, labels, statuses, timeline, relationships, stats
                        (incl. words written per day, daily word totals and sprints)
  content/<uuid>.md     one Markdown file per document that has text
  snapshots/<uuid>.json saved versions of a document
  files/<uuid>.<ext>    imported research files (images, PDFs, …), copied in unchanged
  backups/              rolling copies of project.json (one per 10 minutes, last 20 kept)
  autobackup.txt        what the last automatic zip backup held (see below)
  .wordloom.lock        present while the project is open (add it to .gitignore if you use git)
```

**File ▸ Back Up to Zip…** packs the whole project into one `.zip` file (named like
`Title backup 2026-11-05 1430.zip`) in a folder you choose, such as a USB stick or a cloud
folder; Wordloom remembers the folder for next time. Unzip it to get the `Title.wordloom/`
folder back and open that. The lock and the `backups/` folder are left out; entries are stored
uncompressed, so the zip is about the size of the project.

**File ▸ Automatic Backups…** does this for you every time a project closes (Close Project,
opening or creating another project, or quitting). Turn on *Back up to a zip file whenever a
project is closed*, choose the folder (it starts as `Documents/Wordloom Backups`) and how many to
keep (10 by default). The zips are named `Title autobackup 2026-11-06 1730.zip`. If nothing has
changed since the last automatic backup to that folder, no new zip is made. Once there are more
than the number kept, the oldest of that project's automatic backups are deleted. Nothing else in
the folder is touched, including zips made with Back Up to Zip. *Back Up Now* makes one
immediately. The project folder's `autobackup.txt` records what the last backup held.

Imported files are not deleted when their item is trashed or the trash is emptied, so undo and
duplicates can always find them. To reclaim space, use **File ▸ Clean Up Unused Files…**: it
deletes only files that no item (in the Trash or not) and no undo or redo step refers to. **Save As** copies `files/` and `snapshots/` to the new project.

Your preferences (light/dark, editor font size, page width, styled Markdown, smart punctuation, name completion, line highlight and its colour, repeated-word highlighting, the backup folders and automatic-backup settings, which panels are
shown, timeline lanes and the window size) are remembered between runs in
`~/.config/Wordloom/Wordloom.conf` (in the Flatpak, under `~/.var/app/io.github.generalkael.Wordloom/`).
They are per user, not stored in projects.

If you open a project that is already open in another Wordloom, in another window or on
another computer sharing the folder through Dropbox or Syncthing, Wordloom warns you first,
because two copies saving in turn would overwrite each other's changes. A lock left behind by a
crash is ignored.

If `project.json` is ever damaged (cut short, or a bad hand edit), opening the project offers
**Restore from Backup**: Wordloom puts the newest backup that loads in its place, keeps the damaged
file as `project.json.damaged-<time>`, and gives documents written since that backup a binder entry
again in a *Recovered after restore* folder, so no text is lost.

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
    storage.rs     bundle format, atomic writes, backups, zip backup and its fingerprint, snapshots, imported files
    analysis.rs    text analysis: word and phrase frequency, sentences, adverbs, dialogue
    mentions.rs    where a character or place is mentioned in the manuscript
    comments.rs    inline {>> comments <<}: finding, listing, stripping for counts and compile
    compile.rs     manuscript → Markdown / HTML / plain text
    print.rs       manuscript → paged HTML for PDF (book and submission-manuscript styles)
    epub.rs        EPUB 3 package
    docx.rs        Word document
    zip.rs         minimal zip writer for EPUB and DOCX
    search.rs      search & case-insensitive replace
    goto.rs        Go to…: ranking binder items by title
    import.rs      Import Manuscript: .docx / Markdown / text → chapters and scenes
    smart.rs       smart quotes, dashes and ellipses
    bible.rs       the story bible: characters and places as one document
    repeats.rs     repeated words nearby in a paragraph (the editor's echo tint)
    relations.rs   character relationships and map positions
    names.rs       character name generator (name lists + fantasy syllables)
    spell.rs       spell checking (spellbook + Hunspell dictionaries; dict/ holds the built-in en_US)
    diff.rs        side-by-side snapshot comparison (paragraphs, then words)
    stats.rs       word counting, targets, daily history, streaks
    history.rs     project-wide undo/redo (structure snapshots + text diffs)
    session.rs     an open project + its JSON-shaped API
    api.rs         call(method, argsJson) dispatcher used by the UI
    demo.rs        the sample project
  wordloom-app/    the Qt front end
    src/controller.rs  one cxx-qt QObject (QML singleton `Wordloom`) wrapping api::App
    src/styler.*       C++ QSyntaxHighlighter for styled Markdown, spelling and repeats (MarkdownStyler in QML)
    src/pdfexport.*    C++ PDF writer (QPdfWriter): title page, running header, page numbers
    qml/*.qml          all views and dialogs
```

The UI talks to Rust through a single invokable, `Wordloom.call(method, argsJson)`, which the
`Api` QML singleton wraps. Any call that changes data bumps a `revision` property, and each view
re-queries what it shows when that happens. This keeps the FFI surface tiny: adding a feature is
a Rust method, one line in `api.rs`, and some QML.

Developer aid: `wordloom PROJECT --screenshots=DIR` opens each view and dialog in turn, saves a
PNG of each, and quits. It also works headless with `QT_QPA_PLATFORM=offscreen`.

`wordloom --sample=DIR --selftest` drives the real UI through checks for bugs fixed in the past
(editor scrolling and sizing, binder selection, formatting, inline comments, line highlight, repeated words, name completion, smart punctuation, appearances, Go to, find & replace, text analysis, PDF export, story bible, import, zip backup, automatic backup, spelling, view order,
the history window, sprints), prints PASS / FAIL lines and exits non-zero on failure. CI runs it
on every push. Add a step to `qml/SelfTest.qml` when you fix a UI bug. Both developer modes keep
their own preferences and recent-projects list.

## Roadmap

- Packaged installers for Windows (MSI) and macOS (DMG); the Linux AppImage and Flatpak are done
- Flathub submission: the manifest and metadata are ready; what's left is opening the submission
  pull request on flathub/flathub

## License

Wordloom is released under the [MIT License](LICENSE).

The built-in US English dictionary (`crates/wordloom-core/dict/`) comes from
[SCOWL](https://wordlist.aspell.net) and is © Kevin Atkinson and others under the permissive terms
in `crates/wordloom-core/dict/COPYRIGHT-en_US.txt`. Spell checking uses the
[spellbook](https://crates.io/crates/spellbook) crate (MPL-2.0). Reading Word files uses
[miniz_oxide](https://crates.io/crates/miniz_oxide) (MIT / Apache-2.0 / Zlib).
