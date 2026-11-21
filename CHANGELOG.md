# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- In-app Bases editing: add, remove, and reorder columns; rename or add a table or cards view; edit a filter from a popover. Writes are atomic and undoable with ⌘Z, and comments and unknown keys are kept.
- Summaries row on table views: Count, Sum, Average, Min, Max, Earliest, Latest, Unique, Empty, Filled.
- Richer Bases formulas: date durations, `.format()`, `.relative()`, plus list, number, and string methods.
- Esc in the editor returns to reading view when nothing else is open. Settings ▸ Editor, on by default.
- Split layout is remembered per vault: sizes, axis, and what's in each pane.
- Universal release builds for Apple silicon and Intel (`make release`). `make app` still builds just for your Mac.

### Changed
- README trimmed; guides moved into `docs/`, including `DEVELOP.md`.

### Removed
- Rhymepad support.

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

[Unreleased]: https://github.com/kennethreitz/onyx/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/kennethreitz/onyx/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/kennethreitz/onyx/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/kennethreitz/onyx/releases/tag/v0.1.0
