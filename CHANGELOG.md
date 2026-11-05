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
- The sample project includes an imported map.
- Keyboard shortcut reference in the README.

### Fixed
- **Save As** now copies snapshots (and imported files) to the new project instead of leaving
  them behind.

### Changed
- CI builds Linux only for now; Windows and macOS builds are paused.
