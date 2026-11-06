# Changelog

Notable changes to Wordloom. Each entry lands in the same commit as the change it describes.

## Unreleased

### Added
- **Project-wide undo and redo.** ↶/↷ on the toolbar, Edit ▸ Undo/Redo, and Ctrl+Z / Ctrl+Shift+Z
  outside text boxes reverse binder moves, renames, trash and empty trash, replace-all, metadata,
  labels, targets, file imports and every timeline edit. The menu names the step. Typing keeps
  the editor's own undo. Up to 200 steps per session.
- **EPUB and DOCX export**, built in. EPUB 3 has one file per chapter and a table of contents;
  DOCX uses named styles and starts each chapter on a new page. Both preview as formatted text
  in the Compile dialog. Pandoc and Calibre are no longer needed.
- **Split editor.** Keep one document open beside the main view (◫ Split, Ctrl+\, or *Open in
  Split Editor* in the binder). ⇄ swaps the panes. The same document can be open in both.
- **Research files.** Import images and PDFs (File ▸ Import File…, Ctrl+Shift+I, or drop files on
  the binder). Images show with fit and zoom; PDFs page by page, fitted to the pane width. Other
  types open in the default app. Needs Qt PDF for the PDF viewer.
- **Snapshot comparison.** *Compare…* on the Snapshots tab shows a snapshot side by side with the
  current text or another snapshot, with paragraphs aligned and changed words highlighted.
- **Styled Markdown editing.** The editor shows headings, bold, italic, quotes and scene breaks
  styled as you type, with faded markers; documents stay plain Markdown. A format bar and Ctrl+B /
  Ctrl+I toggle the markup. View ▸ Styled Markdown switches it off. Emphasis may span lines of a
  paragraph, as in compile.
- **Relationship map.** A new Relations view (Ctrl+6) with draggable character cards and labelled,
  directed relationships with notes. Undoable; relationships are removed when a character is
  deleted for good. The Details panel lists a character's relationships.
- **Timeline swim lanes.** *Lanes* groups tracks by kind under collapsible headers.
- The sample project includes an imported map and an earlier-draft snapshot.
- **Reading mode** (❦ Read, Ctrl+7): the manuscript or the selected chapter as a read-only book
  page, from the same compile step as export, with its own text size and column width. A new
  project shows a hint instead of an empty page.
- **Word-target progress in the binder.** Documents and folders with a word target show a small
  progress bar (green when reached) with the count on hover.
- **Writing sprints** (Ctrl+Shift+R): timed sessions with an optional word goal, a status-bar
  countdown with a live word count, pause / finish / cancel, and a saved history with bests.
- **Word count history.** The project now also records its manuscript and project word totals for
  each day. A Word Count History window (click the goal ring, or Ctrl+Shift+H) charts words written
  or running totals by day, week, month or year, with Daily / Weekly / Monthly / 90 days / Yearly /
  Lifetime presets or any custom date range, plus range totals, average and best day.
- **Spell checking.** Misspellings are marked in red as you type (View ▸ Check Spelling, F7);
  right-click for suggestions or *Add to Dictionary*. Character, place and track names are always
  accepted. Uses the system's Hunspell dictionary, or a bundled US English one.
- **Name generator** (Project ▸ Name Generator…, Ctrl+Shift+G): real-world and fantasy styles,
  by gender, with one-click *Add as Character*.
- **Daily goal ring.** The status bar shows today's progress toward the session target as a ring
  that turns green (with a one-time notice) at the goal; clicking it opens Writing Statistics.
- **Find & replace in a document.** Ctrl+F / Ctrl+H open a find bar in the editor with a match
  count, next / previous, whole-word (default) and match-case options, Replace and Replace All;
  composite folder views search every part, and Ctrl+Z undoes replacements.
- **Inline comments.** Leave yourself a note in the text, `{>> like this <<}`: Edit ▸ Insert
  Comment (Ctrl+Alt+M) or { } on the format bar puts one at the caret. Comments are shown
  highlighted, and left out of word counts, compile, reading mode and the Markdown preview. The
  Details panel's Notes tab lists the comments in the item (and the items under it); click one to
  jump to it in the editor.
- **Faster with big books.** The editor no longer lays out what's selected while another view is
  showing: picking the Manuscript on the corkboard of a 168,000-word novel took nearly 4 seconds
  and now takes a few milliseconds, as does opening a chapter from the reader.
- `wordloom --bench=DIR` times every view on a generated novel-sized project.
- The editor shares one right-click menu between all the documents it shows, instead of building a
  menu per document: a folder of 200 scenes opens about 20% faster.
- A long composite (a folder of many scenes, or the whole manuscript) shows its first parts at
  once and adds the rest a few at a time in the background, instead of freezing the window: the
  200-scene manuscript appears in under 0.1 s instead of 3.5 s.
- **Restore from Zip Backup.** File ▸ Restore from Zip Backup… unpacks a backup into a folder you
  choose (beside, never over, an existing copy) and opens it.
- **Corkboard keyboard control.** Arrows, Home and End move a highlight between cards; Enter
  opens a card (a folder's cards, or a document in the editor); Backspace goes up a folder;
  Ctrl+arrows move the card; Delete trashes it.
- **Spelling language.** View ▸ Spelling Language lists the installed Hunspell dictionaries by
  name and switches between them (or back to *Automatic*); the choice is remembered. Dictionaries
  in `~/.local/share/hunspell` are found too, including from the Flatpak.
- **Project templates.** File ▸ New Project… offers Blank, Novel (three acts of chapters with
  guiding synopses, protagonist, antagonist, setting, premise note), Short Story (five scenes) and
  Non-fiction (front matter, chapters of sections, back matter, outline and sources notes).
- **Footnotes.** Edit ▸ Insert Footnote (Ctrl+Alt+F), or Markdown's `[^label]` with a
  `[^label]: note` paragraph in the same document. Compile numbers them through the book: real
  footnotes in Word, linked superscripts and a Notes section in HTML and EPUB, a Notes chapter in
  PDF, `[^n]` in Markdown and `[n]` in plain text. The editor fades references and greys notes.
- **Drag and drop on the corkboard.** Drag a card by any part that isn't text to move it before or
  after another card (a bar marks the spot), or onto the middle of a folder card to move it
  inside. Undo puts it back. Dragging across a card's text still selects the text.
- **Outliner filter.** Filter… (title, synopsis, keywords, custom fields), a label and a status
  narrow the outline; matches are shown under their (dimmed) folders, with a count of matches and
  words. ✕ or Esc clears it.
- **Outliner: folding and more columns.** Folders fold with ▸ / ▾ (or Collapse All / Expand
  All). Columns ▾ adds Keywords and any custom field used below the item (POV, Setting, Time…)
  as editable columns, remembered between runs. A line under the table counts items and words.
  When the table is wider than the pane it scrolls sideways instead of cutting off the Target and
  Progress columns.
- `--screenshots=DIR --dark` takes the screenshot tour in the dark theme.
- README: a *Using the outliner* guide (opening it, every column, planning a book with it).
- **Story bible export.** File ▸ Export Story Bible… writes all characters and places into one
  Word, HTML, Markdown or plain-text document: synopsis, custom fields, sheet text, notes,
  relationships and the scenes each appears in. Trashed items are left out.
- **Repeated-word highlighting.** View ▸ Highlight Repeated Words tints both uses of a word
  repeated within about 40 words in one paragraph (“the lamp room, and the lamp room”). Short and
  common words, capitalised words and comments are skipped. Off by default.
- **Automatic backups.** File ▸ Automatic Backups… can zip the project into a folder you choose
  (another drive or a synced cloud folder) every time it closes: Close Project, opening or
  creating another project, or quitting. A project that hasn't changed since its last automatic
  backup isn't zipped again, and only the newest N (10 by default) of each project's
  `Title autobackup YYYY-MM-DD HHMM.zip` files are kept. Other files in the folder are never
  deleted. *Back Up Now* makes one straight away. Off until you turn it on.
- **Current-line highlight.** View ▸ Highlight Current Line puts a bar behind the line you're
  typing on (the visual line, when a paragraph wraps). View ▸ Line Highlight Colour offers
  amber, blue, green, rose and grey presets, or *Custom Colour…* with transparency. Both are
  remembered.
- **Name completion.** Type the start of a character's or place's name (“Tob”) and the editor
  offers the full name (“Tobias”, “Tobias Wren”) under the caret: Tab takes it, ↑ ↓ choose, Esc
  dismisses. Names include first names and *Also known as*. View ▸ Complete Names turns it off.
- **Import Manuscript** (File ▸ Import Manuscript…): bring in a whole book from Word (.docx),
  Markdown or plain text. It becomes a folder in the Manuscript with a folder per chapter and a
  document per scene, split at headings, “Chapter 12” / “Prologue” lines and scene breaks, with
  italics and bold kept. One Undo removes it again.
- **Smart punctuation.** As you type, straight quotes become “curly” ones and apostrophes ’, two
  hyphens become an em dash — and three dots an ellipsis …; a line of dashes (a scene break) and
  text in comments stay as typed. View ▸ Smart Punctuation turns it off. Edit ▸ Convert to Smart
  Punctuation converts a whole document, e.g. pasted text (Ctrl+Z undoes it).
- **Go to…** (Project ▸ Go to…, Ctrl+P): type part of any item's title, even with its letters
  spread out (“nght wtch”), and press Enter to open it. Items inside collapsed folders are found
  too, and their folders open in the binder. With nothing typed, it lists your recent changes.
- **PDF export**, in two styles. *Book*: a title page, justified text with book-style indents,
  each chapter on a new page, and page numbers. *Manuscript*: standard submission format, double
  spaced in Courier or Times, with your contact details and “about N words” on the title page,
  chapters a third of the way down a new page, “Surname / TITLE / page” at the top of each page,
  and END at the close. Letter or A4; fonts are embedded.
- **Text Analysis** (Project ▸ Text Analysis…, Ctrl+Shift+A), for the whole manuscript or the
  selected item: your most used words (leaving out common ones), repeated three-word phrases, -ly
  adverbs, the longest sentences, average sentence length and the share of dialogue. Click a word
  or phrase to search the project for it, or a long sentence to open it in the editor.
- **Where characters and places appear.** Select a character or place and the Details panel lists
  the manuscript documents that mention it, with a count; click one to open it with the name in
  the find bar. Names are matched as whole words with matching case: the title, a first name
  (“Mara” for “Mara Quinn”), and anything in the new *Also known as* field.
- **File ▸ Back Up to Zip…** saves the whole project (documents, snapshots, imported files) as
  one `.zip`, named with the date and time, in the folder you used last time. Unzip it to get the
  `Title.wordloom` folder back. The lock and the rolling `project.json` backups are left out.
- **File ▸ Clean Up Unused Files…** deletes imported files no item, Trash item or undo step uses.
- Keyboard shortcut reference in the README.
- **Linux AppImage**, built and smoke-tested by CI on every push to `main`
  (`packaging/linux/build-appimage.sh`), with a desktop entry, icon and AppStream metadata.
- **Flatpak** (`packaging/flatpak/`), on the KDE 6.11 runtime, built and smoke-tested by CI. The
  app reports its desktop file name (`io.github.generalkael.Wordloom`), so Wayland docks show the
  right icon. The build is offline with vendored crates (`cargo-sources.json`, generated from
  `Cargo.lock`), as Flathub requires, and the AppStream metadata has screenshots.

### Fixed
- **Split editor follows focus.** Picking a document in the binder always replaced the main
  editor's document, even while you were writing in the split editor. It now opens in the pane
  you were last typing in (shown by an accent line on its header), and the binder highlight,
  Details panel, word count and item commands follow that pane.
- The Details panel no longer logs an error when the selected item has just been deleted.
- **Ordinals aren't misspellings.** Spell checking no longer marks the letters in “2nd” or “10km”.
- **Word Count History in a forced theme.** Its date boxes and menus followed the system colours,
  so with Dark forced on a light desktop they were light with unreadable light text. Esc now
  closes the window.
- **Preferences are remembered.** Light/dark, editor font size, page width, styled Markdown,
  panel visibility, timeline lanes and window size used to reset on every start. The app also
  shuts QML down properly on exit so the last change is saved.
- The screenshot tour (`--screenshots=DIR`) keeps its own preferences and recent-projects list.
- **Narrow windows.** The editor header no longer overflows (less-used buttons fold into a ⋯
  menu), the split editor opens at half the space and fits beside the Details panel in a 1000 px
  window, and narrow pages use smaller margins.
- **Clicking a document opens the editor.** After a folder had switched to the corkboard (or from
  the outliner), selecting a document in it kept showing the corkboard.
- **Editor page resizes with the window.** It fills the editor pane by default (⇔ still offers fixed
  widths) and is always at least as tall as the pane; it used to stay 720 px wide and 640 px tall.
- **Editor scrolls while you type.** Typing past the bottom of the pane now scrolls to keep the
  caret visible (previously only typewriter mode did).
- **Save As** now copies snapshots (and imported files) to the new project instead of leaving
  them behind.
- **Ctrl+N** no longer clashes between New Project and New Document: it is New Project on the
  start screen and New Document once a project is open.

### Changed
- The **Inspector** is now called the **Details** panel (toolbar: Show/Hide Details; View ▸ Show
  Details, still Ctrl+Alt+I).
- Binder, corkboard, outliner, editor and timeline icons are bundled SVGs instead of emoji, so they
  look the same everywhere. Emoji showed as empty boxes where the system's emoji font couldn't be
  drawn, including in the AppImage. Toolbar "＋" and "⎙" symbols became a plain "+" and text for the
  same reason.
- **Warning when a project is already open elsewhere.** A lock file marks an open project; opening it
  a second time (another window, another Flatpak instance, or another computer sharing the folder)
  asks first. The lock is refreshed every two minutes while open; locks left by a crash are ignored.
- **Restore a damaged project.** If `project.json` can't be read, Wordloom says so plainly and offers
  to restore the newest working backup, keeping the damaged file and recovering documents written
  since the backup into a *Recovered after restore* folder.
- `wordloom --sample=DIR --selftest` runs UI regression checks (editor scrolling and sizing,
  binder selection, formatting, find & replace, spelling, view order, history window, sprints);
  CI runs it on every push.
- CI builds Linux only for now; Windows and macOS builds are paused. A newer push cancels the CI run it
  supersedes.
