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
- **Read Aloud** — the current note or your selection, from the command palette, with macOS voices
- **Record Audio** — record a voice memo into the current note (`![[Recording ….m4a]]` in your attachments folder) with an automatic on-device transcript below it
- **Custom shortcuts** — every bindable command in Settings ▸ Shortcuts; click a row to record a new combination
- **PDF and print** — a note as a book page, with margin notes and a running head; or a folder or selection as one typeset book, with a table of contents
- **Graph and atlas** — travel by clicking nodes, or zoom out over the whole vault
- **`partOf::` relationships** — an ancestry path in the title bar, a parts tree and link-valued fields in the inspector, field and note completion after `key::`, and a hierarchy-only graph
- **Canvas, Kanban, and Bases** — Obsidian boards and `.base` views, in place. Edit columns, views, filters, and formulas; table views have a summaries row
- **Wikilinks, daily notes, folders, and search** — the usual, without the chrome. New notes with ⌘N, new folders with ⇧⌘N. Open Random Note is in the command palette and the Go menu
- **Obsidian Sync and git** — optional, and only if you ask. A Sync Log is in the command palette, the footer badges, and Settings ▸ Sync
- **Preliminary Dataview support** — `dataview` blocks in the reader for TABLE, LIST, TASK, GROUP BY, and FLATTEN; unsupported queries show an error box

## Preliminary Dataview support

`dataview` code blocks run in the typeset reader.

Supported: TABLE (including WITHOUT ID) with AS columns, LIST, and TASK (grouped by file, with checkboxes that toggle the source note); FROM a folder or `#tag` with OR and `-` exclusion; WHERE with comparisons, AND/OR, and the function library below; SORT; LIMIT; GROUP BY (with `rows`); FLATTEN. Implicit `file.*` fields: name, path, folder, link, ctime, mtime, cday, mday, tags, etags, inlinks, outlinks, aliases, tasks, size, day. Dates and durations (`date(today)`, `dur()`, date comparisons and math). Functions: length, lower, upper, round, min/max/sum, join, link, dateformat, regexmatch, replace, startswith/endswith, filter/map, any/all, nonnull, number, string, striptime, choice, default, contains/icontains, econtains. Inline `key:: value` fields are queried like frontmatter.

Not yet supported: inline queries, DataviewJS, and CALENDAR. Unsupported queries show an error box.

## Download

The latest build is on the [releases page](https://github.com/kennethreitz/onyx/releases/latest). Unzip it and drag `Onyx.app` to `/Applications`.

This build is not notarized, so the first launch needs System Settings ▸ Privacy & Security ▸ **Open Anyway**. It updates itself from v0.1.1 on. Requires macOS 14 (Sonoma) or later, on Apple silicon or Intel.

## Docs

- [Reading](docs/reading.md) — typography, sidenotes, PDF and print
- [Graph and atlas](docs/graph.md)
- [Bases](docs/bases.md)
- [Canvas and Kanban](docs/boards.md)
- [Getting around](docs/navigation.md)
- [Sync](docs/sync.md)
- [Keyboard shortcuts](docs/shortcuts.md)
- [Compatibility and privacy](docs/compatibility.md)
- [Building from source](docs/DEVELOP.md)
- [Changelog](CHANGELOG.md)

## License

Onyx is licensed under the [GNU Affero General Public License v3.0](LICENSE).
