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
- **File ▸ Clean Up Unused Files…** deletes imported files no item, Trash item or undo step uses.
- Keyboard shortcut reference in the README.
- **Linux AppImage**, built and smoke-tested by CI on every push to `main`
  (`packaging/linux/build-appimage.sh`), with a desktop entry, icon and AppStream metadata.
- **Flatpak** (`packaging/flatpak/`), on the KDE 6.11 runtime, built and smoke-tested by CI. The
  app reports its desktop file name (`io.github.generalkael.Wordloom`), so Wayland docks show the
  right icon. The build is offline with vendored crates (`cargo-sources.json`, generated from
  `Cargo.lock`), as Flathub requires, and the AppStream metadata has screenshots.

### Fixed
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
- CI builds Linux only for now; Windows and macOS builds are paused. A newer push cancels the CI run it
  supersedes.
