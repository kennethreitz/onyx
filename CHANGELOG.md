# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- ⌘-drag notes and folders in the file tree to move them into a folder, or into the vault root (drop on the empty area). The drop target highlights and a collapsed folder expands on hover. Multi-selections move together. A folder can’t be moved into itself or its descendants, and a name collision shows an error. Plain drag does not move files.

### Changed
- Rename is inline in the file tree, like Finder. The context menu, File ▸ Rename Note…, the command palette, Return on a selected row, and New Folder all edit the row name in place (the stem, without `.md`). Enter commits, Esc or an empty or unchanged name cancels, clicking away commits, and a collision or illegal character shows an error without leaving the edit. If the sidebar is hidden, the old prompt still appears. Wikilinks, open tabs, and git still follow the rename.

## [0.1.4] - 2026-11-21

### Changed
- The left sidebar is always docked. The pin button, left-edge hover peek, and auto-hide overlay are gone; ⌘K still shows or hides it.
- The bottom bar has a quiet sidebar-toned fill and a hairline, with smaller icons that settle until you hover. Word count and sync status stay put.

### Fixed
- Highlights (`==like this==`) stay on the words in the typeset reader. A wrapped mark no longer paints a full-width yellow band into the margins.

### Documented
- Preliminary Dataview support: `dataview` blocks in the reader run TABLE (including WITHOUT ID) with AS columns, and LIST; FROM a folder or `#tag` with OR and `-` exclusion; WHERE with comparisons, AND/OR, `contains()`, `choice()`, `default()`; SORT; and LIMIT. Inline queries, DataviewJS, TASK, CALENDAR, and GROUP BY are not supported yet; those queries show an error box.

## [0.1.3] - 2026-11-21

### Added
- Show Log in Settings ▸ Sync (Git and Obsidian Sync) opens the Sync Log and closes Settings so the panel is visible.
- New Folder in the command palette, File menu (⇧⌘N), the sidebar folder and empty-area menus, and a quiet button next to New Note. Creates “Untitled Folder” (then 2, 3, …) in the selected or right-clicked folder, reveals it, and offers a name.
- Export a sidebar selection or a folder as one typeset PDF, with a table of contents, folder section pages, and each note starting on a new page.
- Show Sync Log in the command palette: a panel of recent Git and Obsidian Sync activity (timestamp, source, event, detail), kept in a ring of the last 500 events and written to a plain-text log per vault. Esc closes it; Copy and Reveal in Finder sit in the header; clicking the footer sync badges opens it too.
- In-app Bases editing: add, remove, and reorder columns; rename or add a table or cards view; edit a filter from a popover. Writes are atomic and undoable with ⌘Z, and comments and unknown keys are kept.
- Summaries row on table views: Count, Sum, Average, Min, Max, Earliest, Latest, Unique, Empty, Filled.
- Richer Bases formulas: date durations, `.format()`, `.relative()`, plus list, number, and string methods.
- Esc in the editor returns to reading view when nothing else is open. Settings ▸ Editor, on by default.
- Split layout is remembered per vault: sizes, axis, and what's in each pane.
- Universal release builds for Apple silicon and Intel (`make release`). `make app` still builds just for your Mac.

### Changed
- README trimmed; guides moved into `docs/`, including `DEVELOP.md` and `DESIGN.md`.

### Removed
- Rhymepad support.

### Fixed
- Folders can be collapsed again. Clicking the disclosure chevron always toggles expansion; clicking the folder row toggles too, and still opens an index note when there is one. Collapsing a folder that contains the open note no longer snaps it back open.
- Opening a folder note no longer doubles the last breadcrumb (e.g. Life / Family / Projects / Projects). The folder and its index note merge into one final crumb; earlier crumbs and ordinary notes are unchanged.
- A new Untitled note is named from its first heading (or first line) when you save (⌘S) or leave it, and ⌘N uses the folder selected in the file tree. The file was already written as `Untitled.md`, so the note appeared in the editor but didn't land under a real name in the sidebar.
- The atlas graph can no longer be zoomed out to a speck. Pinch, scroll, and fit zoom are clamped at half the fitted view; the existing maximum is unchanged.
- ⌘-click and ⇧-click in the file tree actually change the selection. The earlier multi-select code never saw the modifier keys: SwiftUI's tap gesture often skips a ⌘-click, and the handler read `NSEvent.modifierFlags` after the event had ended.


## [0.1.2] - 2026-11-20

### Added
- Obsidian Bases: open `.base` files as table, cards, or list views, with filters, formulas, sorting, groupBy, a view switcher, and live refresh. Fenced `base` blocks in notes render too.

## [0.1.1] - 2026-11-20

### Added
- New app icon: an onyx crystal with a note graph at the center.
- Auto-updates from GitHub Releases, from Onyx ▸ Check for Updates… or Settings ▸ Updates.
- Resizable split panes: drag the divider; double-click it to even them out.
- Settings split into toolbar-tab pages: General, Editor, Reading, Graph, Sync, and Updates.
- Graph and atlas open as an overlay on the current pane, closed with Esc.

### Changed
- Reading defaults to ragged-right. Justification is opt-in in Settings.
- Epigraphs sit left-aligned with the text.
- Callout titles keep their case.
- README split into a user guide and `DEVELOP.md`.

### Fixed
- A freshly split reader could stay blank until the pane had a size.

## [0.1.0] - 2026-11-20

First public release.

### Added
- Typeset reading: small caps, collision-free sidenotes, hyphenation, and Settings for typeface and page style.
- Export as PDF and Print, with margin notes and a running head.
- Graph as a pane or atlas, with hover graph cards.
- Hover page previews and backlinks in the reading view.
- Find and replace (⌘F / ⌥⌘F).
- Editable Kanban boards with collapsible lanes, compatible with obsidian-kanban.
- JSON Canvas boards, open and editable.
- `partOf::` and `related::` inline fields.
- Optional Obsidian Sync and continuous git (auto-commit, pull --rebase, push).
- Link rewriting on rename or move, including standard Markdown links and embeds.
- Sidebar sorting and ⌘-click multi-select.
- Quick switcher, split panes, back/forward navigation, and a command palette.
- Daily notes, wikilinks, and search.

[Unreleased]: https://github.com/kennethreitz/onyx/compare/v0.1.4...HEAD
[0.1.4]: https://github.com/kennethreitz/onyx/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/kennethreitz/onyx/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/kennethreitz/onyx/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/kennethreitz/onyx/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/kennethreitz/onyx/releases/tag/v0.1.0
