# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Note composer, matching Obsidian’s core plugin: Merge Current File With Another File…, Extract Current Selection…, and Extract This Heading…. They’re in the command palette, the Edit menu, and (for the extract commands) the editor’s context menu, and they’re bindable in Settings ▸ Shortcuts, with no default shortcut. Merge asks first, then appends or prepends the open note’s body to a note you pick in the quick switcher, combines frontmatter (target scalars win, lists are unioned), rewrites wikilinks and Markdown links and embeds across the vault so they point at the target, and moves the source to the Trash. Extract writes the selection, or the heading section around the caret, to a new note (or appends it to an existing one), and replaces the original with a link, an embed, or nothing — that’s one undo step in the editor. A selection that starts with a heading offers that heading as the name. Settings ▸ Editor has confirm-before-merge, append vs prepend, where new notes land, and whether to open the extracted note.

## [0.1.6] - 2026-11-21

### Added
- Dataview `GROUP BY` (with `rows`) and `FLATTEN`, implicit `file.*` fields (name, path, folder, link, ctime, mtime, cday, mday, tags, etags, inlinks, outlinks, aliases, tasks, size, day), dates and durations (`date(today)`, `dur()`, date comparisons and math), and a broader function library: length, lower, upper, round, min/max/sum, join, link, dateformat, regexmatch, replace, startswith/endswith, filter/map, any/all, nonnull, number, string, striptime, choice, default, contains/icontains, econtains. Inline `key:: value` fields are queried like frontmatter.
- Dataview TASK queries: tasks from matching notes, grouped by file, with WHERE on completed, text, due, and similar fields. Clicking a checkbox toggles `[ ]` / `[x]` in the source note through the normal write path, so git and Obsidian Sync see the change.
- Dataview inline queries: `` `= expr` `` in the typeset reader evaluates against the current note (`this`, `file.*`, and the rest of the function library) and renders the value in place. `` `$= ` `` is reserved for DataviewJS and shows a small inline error until that lands. Bad expressions also fail inline, without breaking the page.
- Dataview CALENDAR queries: a month grid with a dot for each matching note on that date (from `file.day`, a date field, or any date expression). Months between the first and last result are kept; clicking a dot opens the note.
- DataviewJS: ````dataviewjs```` blocks and `` `$= ` `` inline queries run in a JavaScriptCore sandbox with a `dv` API subset backed by the vault index (`dv.pages`, `dv.current`, `dv.page`, `dv.table` / `list` / `taskList` / `paragraph` / `header` / `span` / `el`, `dv.date`, and array `where` / `sortBy` / `groupBy` / `map` / `limit`). No network and no file writes. Errors use the existing error box.
- Open Random Note in the command palette and the Go menu. It opens a random Markdown note from the vault in the current pane, skipping the one you’re on when it can. Hidden files and ignored folders stay out, the same as the rest of the index. No default shortcut; assign one in Settings ▸ Shortcuts.
- Record Audio in the command palette and the Note menu (bindable in Settings ▸ Shortcuts). It toggles recording from the microphone to `Recording YYYY-MM-DD HH-mm-ss.m4a` (AAC) in Obsidian’s attachment folder, shows a quiet footer chip with elapsed time and stop, then inserts `![[Recording ….m4a]]` at the cursor. A transcript is generated on-device (SpeechAnalyzer/SpeechTranscriber on macOS 26+, else SFSpeechRecognizer with on-device recognition in ~50 s chunks) and added below the embed as a `> [!transcript]` callout while the chip reads “Transcribing…”. Settings ▸ Reading has a toggle for automatic transcripts (on by default). The app bundle now declares microphone and speech-recognition usage descriptions.
- `partOf` direction in the focus graph: a small chevron on each hierarchy spoke points from the part to its parent, and Filter ▸ Hierarchy only (partOf) narrows the focus graph to parents and parts, two levels out. The setting is remembered.
- Field completion in the editor. Typing a word and a colon at the start of a line (`part:`) offers the field keys the vault already uses, most used first, and picking one writes `partOf:: `. After `partOf:: `, `related:: `, or any key used with a `[[link]]` elsewhere, the `[[` note list appears and writes `[[Note]]` (comma lists work). It uses the same quiet popup as `[[`, inserts nothing until you pick, and Esc closes it for that line.
- A `partOf::` ancestry path in the title bar. A note with a parent reads `Medication › SSRI › Sertraline` there instead of its folders (so the two never repeat), and each ancestor opens on click. With several parents the first is followed and a faint +N menu lists the others; a loop stops where it repeats. Notes without `partOf` keep the folder path.
- A quiet `class:` tag after the note name in the title bar, from frontmatter `class:` (e.g. `Medication`). It opens the class note when one exists.
- Richer relationships in the inspector’s Backlinks tab (⌘I). Parts is now a collapsible tree (a chevron opens a part’s own parts; the header counts every descendant; a note that loops back is marked ↻), Siblings sit folded under their count, and any other field whose values are links (`treats:: [[Anxiety]]`, `seeAlso:: [[X]]`) gets its own group by key, with a “key · from” group for notes that point here with that key.
- Obsidian's core commands in the command palette, a new Format menu, and Settings ▸ Shortcuts. Format: toggle bold (⌘B), italic, strikethrough, highlight, inline code, and `%%comment%%` (⌘/); insert wikilink or Markdown link; headings 1–6; toggle bullet, numbered, checklist, and blockquote; cycle checkbox (⌘L); indent and outdent; insert callout, code block, table, horizontal rule, current date, and current time; move line up or down, duplicate line, and delete line. Each edit is one undo step, and running a format command from the reader switches to editing first. Navigate: Yesterday’s and Tomorrow’s Daily Note, Jump to Heading… (a palette of the note's headings), and Reveal in Sidebar. File: Duplicate Note, Copy File Path, Open in Default App, and Open Settings…. Pane: New Note in New Pane. View: Zoom In (⌘=), Zoom Out (⌘-), and Actual Size (⌘0) for the editor and reader text. Edit: Search Vault for Selection and Toggle Spellcheck. Save, Open Vault…, Find, Find and Replace, Graph in a Pane, Previous Pane, and Show Shortcut Hints, which were only in the menus, are now in the palette too. Italic and Insert Markdown Link have no default, because ⌘I and ⌘K already open the inspector and sidebar. The full list is in docs/commands.md.
- Markdown linter in the style of Obsidian Linter (docs/linter.md). **Lint Current Note** is in the command palette and the Note menu and runs as one undoable edit that keeps the caret on its line. **Lint All Notes in Folder…**, also on a folder's right-click menu as Lint Notes in Folder…, shows how many notes would change before it writes anything. It skips notes open in a pane and any file that changed since the preview. **Lint on save** is optional and off by default. It runs on ⌘S, Save and Read, Esc, and when you switch notes, never on the typing autosave. Settings ▸ Linter has a toggle for each rule. Rules that are on by default: trim trailing whitespace (keeping two-space hard breaks), collapse blank lines, a single trailing newline, blank lines around headings, a space after `#`, a consistent `-` list marker, blank lines around code blocks, and normalized checkboxes. Rules that are off by default: heading increments, tidy frontmatter keys, and an `updated:`/`modified:` timestamp. The linter never touches fenced code, math, `%%`/HTML comments, callouts and blockquotes, inline-field lines (`partOf::`), wikilinks, inline code, or frontmatter values. Linting twice gives the same result as linting once.

### Changed
- Spellcheck is back on in the editor by default. Turn it off in Settings ▸ Editor or with Toggle Spellcheck.

### Fixed
- Embedded audio and video in the reader answer byte-range requests, so WebKit can play and seek them.

## [0.1.5] - 2026-11-21

### Added
- Customizable keyboard shortcuts in Settings ▸ Shortcuts. Every bindable command is listed by group with its current shortcut; click a row to record a new combination, or Clear / Reset that row, or Reset All. A conflict with another command, or a reserved system combination such as ⌘Q, shows a warning so you can reassign or cancel. Overrides persist in UserDefaults, and the menu bar and command palette use the live bindings. Text-editing keys are left alone.
- Read Aloud in the command palette and the Note menu, using the Mac’s system voices (AVSpeechSynthesizer). It speaks the selection if there is one, otherwise the current note, with frontmatter, comments, code blocks, URLs, and Markdown markup stripped so the voice reads prose (wikilinks speak the alias or name). Pause/Resume Reading and Stop Reading are in the same places; a quiet “Reading” chip in the footer (and in focus mode) has pause and stop controls. Voice and Rate live in Settings ▸ Reading. Reading stops when you switch notes.
- `$inline$` and `$$display$$` math in the typeset reader, including multi-line `$$` blocks, PDF, and print. KaTeX is bundled (offline, MIT). Currency like `$5 and $10`, escaped `\$`, and dollars inside code are left alone; bad TeX shows an inline error. The editor still shows the source.
- ⌘-drag notes and folders in the file tree to move them into a folder, or into the vault root (drop on the empty area). The drop target highlights and a collapsed folder expands on hover. Multi-selections move together. A folder can’t be moved into itself or its descendants, and a name collision shows an error. Plain drag does not move files.

### Changed
- Rename is inline in the file tree, like Finder. The context menu, File ▸ Rename Note…, the command palette, Return on a selected row, and New Folder all edit the row name in place (the stem, without `.md`). Enter commits, Esc or an empty or unchanged name cancels, clicking away commits, and a collision or illegal character shows an error without leaving the edit. If the sidebar is hidden, the old prompt still appears. Wikilinks, open tabs, and git still follow the rename.

### Fixed
- The ⌘-drag preview is a compact row (icon, name, and a count badge for a multi-selection) in the sidebar’s font and colors, sized for Retina, instead of a stretched black label.
- A wrapped `==highlight==` no longer leaves a full-width band in the margins. `box-decoration-break: clone` was already set, but a `border-radius` still made WKWebView paint one unbroken box behind the per-word tint, in both light and dark themes.

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

[Unreleased]: https://github.com/kennethreitz/onyx/compare/v0.1.6...HEAD
[0.1.6]: https://github.com/kennethreitz/onyx/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/kennethreitz/onyx/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/kennethreitz/onyx/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/kennethreitz/onyx/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/kennethreitz/onyx/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/kennethreitz/onyx/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/kennethreitz/onyx/releases/tag/v0.1.0
