<p align="center">
  <img src="docs/logo.png" alt="Onyx" width="128">
</p>

<h1 align="center">Onyx</h1>

<p align="center"><b>Notes, typeset.</b><br>
A native Mac app for your Obsidian vault, typeset like a book.</p>

<p align="center">
  <img src="docs/hero.png" alt="Onyx: a typeset typography note beside its focus graph" width="100%">
</p>

---

- **Typeset reading** — small caps, collision-free sidenotes, hyphenation, `$` / `$$` math, the page as a book
- **Linter** — tidy Markdown like Obsidian Linter: one undoable edit for the current note, a preview before linting a folder, and optional lint on save ([docs](docs/linter.md))
- **Read Aloud** — the current note or your selection, from the command palette, with macOS voices
- **Drag, drop, and paste attachments.** Drop files from Finder, drop images from a browser, or paste a screenshot. Each one is copied to your attachments folder and linked as `![[…]]`, following Obsidian's Files and links settings ([docs](docs/attachments.md))
- **Attachments open in place** — click an image, PDF, audio file, or video and it opens in the pane: an image viewer with zoom and pan, PDFKit with find, a native audio player with a waveform, speed control, and your Record Audio transcript, and AVKit for video. ⌘[ goes back ([docs](docs/attachments.md#opening-attachments))
- **Image sizes** — `![[photo.png|300]]`, `|300x200`, and `![alt|300](…)` size images the way Obsidian does, and in the reader you can drag an image's corner to resize it; the new width is written into that embed ([docs](docs/attachments.md#image-size))
- **Record Audio** — record a voice memo into the current note (`![[Recording ….m4a]]` in your attachments folder) with an automatic on-device transcript below it
- **Custom shortcuts** — every bindable command in Settings ▸ Shortcuts; click a row to record a new combination
- **Obsidian’s core commands** — formatting, headings, lists and checkboxes, move/duplicate/delete line, jump to heading, duplicate note, zoom, spellcheck, and more, all in the command palette ([list](docs/commands.md)). Return in a list starts the next item (or ends the list on an empty item); Tab / Shift-Tab indent and outdent list items. Typing a bracket or quote inserts its closer (`[[` becomes `[[|]]`); a selection can be wrapped with those or with `*` `_` `~` `=`
- **Folding** — fold a heading’s section or a nested list from a quiet margin chevron, in the editor and the reader. Folds are display only, remembered per note, and open themselves when Find, the outline, or a link lands inside ([docs](docs/folding.md))
- **Note composer** — merge two notes (links follow, the source goes to the Trash), or extract a selection or heading into a new note, or append it to one you pick. Settings ▸ Editor
- **PDF and print** — a note as a book page, with margin notes and a running head; or a folder or selection as one typeset book, with a table of contents
- **Graph and atlas** — travel by clicking nodes, or zoom out over the whole vault
- **`partOf::` relationships** — an ancestry path in the title bar, a parts tree and link-valued fields in the inspector, field and note completion after `key::`, and a hierarchy-only graph
- **Canvas, Kanban, and Bases** — Obsidian boards and `.base` views, in place. Edit columns, views, filters, and formulas; table views have a summaries row
- **Obsidian's core settings, in Onyx** — Settings ▸ Files & Links (new-note and attachment locations, link format, wikilinks, excluded files) and Settings ▸ Daily Notes (date format, folder, template, open on startup, Templates date and time formats). They read and write the vault's own `.obsidian` files, so Obsidian stays in sync ([docs](docs/obsidian-settings.md))
- **Wikilinks, daily notes, folders, and search** — the usual, without the chrome. New notes with ⌘N, new folders with ⇧⌘N. Open Random Note is in the command palette and the Go menu
- **Obsidian Sync and git** — optional, and only if you ask. A Sync Log is in the command palette, the footer badges, and Settings ▸ Sync
- **Dataview** — `dataview` and `dataviewjs` blocks in the reader, plus `= expr` and `$=` inline queries; unsupported queries show an error box

## Dataview

`dataview` and `dataviewjs` code blocks run in the typeset reader.

Supported: TABLE (including WITHOUT ID) with AS columns, LIST, and TASK (grouped by file, with checkboxes that toggle the source note); CALENDAR month grids; inline `` `= expr` `` and `` `$= ` `` queries; FROM a folder, `#tag`, or `[[Note]]` / `outgoing([[Note]])` / `incoming([[Note]])` with AND, OR, and `-` exclusion; WHERE with comparisons, AND/OR, and the function library below; SORT; LIMIT; GROUP BY (with `rows`); FLATTEN. Implicit `file.*` fields: name, path, folder, link, ctime, mtime, cday, mday, tags, etags, inlinks, outlinks, aliases, tasks, size, day. Dates and durations (`date(today)`, `dur()`, date comparisons and math). Functions: length, lower, upper, round, min/max/sum, join, link, dateformat, regexmatch, replace, startswith/endswith, filter/map, any/all, nonnull, number, string, striptime, choice, default, contains/icontains, econtains. Inline `key:: value` fields are queried like frontmatter.

DataviewJS (`dataviewjs` blocks and `` `$= ` ``) runs in a JavaScriptCore sandbox with a `dv` API backed by the vault index: `dv.pages(source)`, `dv.pagePaths`, `dv.current()`, `dv.page()`, `dv.table` / `list` / `taskList` / `paragraph` / `header` / `span` / `el`, `dv.date` / `duration`, `dv.io` (`load`, `csv`, `normalize`), `dv.view`, `dv.query` / `tryQuery` / `queryMarkdown` / `tryQueryMarkdown`, `dv.execute` / `executeJs`, `dv.evaluate` / `tryEvaluate`, links (`fileLink`, `sectionLink`, `blockLink`), markdown helpers, and array helpers (`where`, `sortBy`, `groupBy`, `map`, `limit`). Async calls return Promises. There is no network and no file writing; `dv.io` and `dv.view` can only read paths inside the vault. Unsupported queries show an error box.

## Download

The latest build is on the [releases page](https://github.com/kennethreitz/onyx/releases/latest). Unzip it and drag `Onyx.app` to `/Applications`.

This build is not notarized, so the first launch needs System Settings ▸ Privacy & Security ▸ **Open Anyway**. It updates itself from v0.1.1 on. Requires macOS 14 (Sonoma) or later, on Apple silicon or Intel.

Opening a second copy of Onyx (a newly built app, `open -n`, or another folder with the same app) quits the one that's already running, after it saves. Set `ONYX_ALLOW_MULTIPLE=1` if you want both to stay open.

## Docs

- [Reading](docs/reading.md) — typography, sidenotes, PDF and print
- [Graph and atlas](docs/graph.md)
- [Bases](docs/bases.md)
- [Canvas and Kanban](docs/boards.md)
- [Getting around](docs/navigation.md)
- [Attachments](docs/attachments.md): drag, drop, paste, the file viewers, and image sizes
- [Sync](docs/sync.md)
- [Linter](docs/linter.md)
- [Keyboard shortcuts](docs/shortcuts.md)
- [Commands](docs/commands.md)
- [Compatibility and privacy](docs/compatibility.md)
- [Building from source](docs/DEVELOP.md)
- [Performance](docs/performance.md) — benchmarking against a copy of your vault
- [Changelog](CHANGELOG.md)

## License

Onyx is licensed under the [GNU Affero General Public License v3.0](LICENSE).
