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
- **Web clipper** — a Clip to Onyx Safari extension and Share menu item built into the app, a bookmarklet for any browser, or File ▸ Clip Web Page… (⇧⌘K), saves the readable article (Mozilla Readability) or just your selection as a Markdown note in Clippings, with Obsidian Web Clipper-style frontmatter, the class and tags your other clippings use, and images downloaded into your attachment folder ([docs](docs/web-clipper.md))
- **Attachments open in place** — click an image, PDF, audio file, or video and it opens in the pane: an image viewer with zoom and pan, PDFKit with find, a native audio player with a waveform, speed control, and your Record Audio transcript, and AVKit for video. ⌘[ goes back ([docs](docs/attachments.md#opening-attachments))
- **Image sizes** — `![[photo.png|300]]`, `|300x200`, and `![alt|300](…)` size images the way Obsidian does, and in the reader you can drag an image's corner to resize it; the new width is written into that embed ([docs](docs/attachments.md#image-size))
- **Record Audio** — record a voice memo into the current note (`![[Recording ….m4a]]` in your attachments folder) with an automatic on-device transcript below it
- **Custom shortcuts** — every bindable command in Settings ▸ Shortcuts; click a row to record a new combination
- **Obsidian’s core commands** — formatting, headings, lists and checkboxes, move/duplicate/delete line, jump to heading, duplicate note, zoom, spellcheck, and more, all in the command palette ([list](docs/commands.md)). ⌘B and ⌘I toggle bold and italic; the inspector is ⌥⌘I. Return in a list starts the next item (or ends the list on an empty item) and renumbers following numbered items; Tab / Shift-Tab indent and outdent list items, and renumber both levels. Typing a bracket or quote inserts its closer (`[[` becomes `[[|]]`); a selection can be wrapped with those or with `*` `_` `~` `=`
- **Folding** — fold a heading’s section or a nested list from a quiet margin chevron, in the editor and the reader. Folds are display only, remembered per note, and open themselves when Find, the outline, or a link lands inside ([docs](docs/folding.md))
- **Note composer** — merge two notes (links follow, the source goes to the Trash), or extract a selection or heading into a new note, or append it to one you pick. Settings ▸ Editor
- **PDF and print** — a note as a book page, with margin notes and a running head; or a folder or selection as one typeset book, with a table of contents. Contents rows and in-note heading links are clickable, and the PDF has an outline of the contents and headings.
- **Graph and atlas** — travel by clicking nodes, or zoom out over the whole vault
- **`partOf::` relationships** — an ancestry path in the title bar, a parts tree and link-valued fields in the inspector, field and note completion after `key::`, and a hierarchy-only graph
- **Canvas, Kanban, and Bases** — Obsidian boards and `.base` views, in place. Edit columns, views, filters, and formulas; table views have a summaries row
- **Obsidian's core settings, in Onyx** — Settings ▸ Files & Links (new-note and attachment locations, link format, wikilinks, excluded files) and Settings ▸ Daily Notes (date format, folder, template, open on startup, Templates date and time formats). They read and write the vault's own `.obsidian` files, so Obsidian stays in sync ([docs](docs/obsidian-settings.md))
- **Wikilinks, daily notes, folders, and search** — the usual, without the chrome. New notes with ⌘N, new folders with ⇧⌘N. Search the vault with ⇧⌘F; replace across it with ⌥⇧⌘F (preview, then replace selected or all, with undo). Open Random Note is in the command palette and the Go menu
- **Obsidian Sync and git** — optional, and only if you ask. A Sync Log is in the command palette, the footer badges, and Settings ▸ Sync. The git sidebar has a History tab for earlier versions of the current note.
- **Dataview** — `dataview` and `dataviewjs` blocks in the reader, plus `= expr` and `$=` inline queries; unsupported queries show an error box

## Dataview

`dataview` and `dataviewjs` code blocks run in the typeset reader.

Supported: TABLE (including WITHOUT ID) with AS columns, LIST, and TASK (grouped by file, with checkboxes that toggle the source note); CALENDAR month grids; inline `` `= expr` `` and `` `$= ` `` queries; FROM a folder, `#tag`, or `[[Note]]` / `outgoing([[Note]])` / `incoming([[Note]])` with AND, OR, and `-` exclusion; WHERE with comparisons, AND/OR, and the function library below; SORT; LIMIT; GROUP BY (with `rows`); FLATTEN. Implicit `file.*` fields: name, path, folder, link, ctime, mtime, cday, mday, tags, etags, inlinks, outlinks, aliases, tasks, size, day. Dates and durations (`date(today)`, `dur()`, date comparisons and math). Functions: length, lower, upper, round, min/max/sum, join, link, dateformat, regexmatch, replace, startswith/endswith, filter/map, any/all, nonnull, number, string, striptime, choice, default, contains/icontains, econtains. Inline `key:: value` fields are queried like frontmatter.

DataviewJS (`dataviewjs` blocks and `` `$= ` ``) runs in a JavaScriptCore sandbox with a `dv` API backed by the vault index: `dv.pages(source)`, `dv.pagePaths`, `dv.current()`, `dv.page()`, `dv.table` / `list` / `taskList` / `paragraph` / `header` / `span` / `el`, `dv.date` / `duration`, `dv.io` (`load`, `csv`, `normalize`), `dv.view`, `dv.query` / `tryQuery` / `queryMarkdown` / `tryQueryMarkdown`, `dv.execute` / `executeJs`, `dv.evaluate` / `tryEvaluate`, links (`fileLink`, `sectionLink`, `blockLink`), markdown helpers, and array helpers (`where`, `sortBy`, `groupBy`, `map`, `limit`). Async calls return Promises. There is no network and no file writing; `dv.io` and `dv.view` can only read paths inside the vault. Unsupported queries show an error box.

## Download

The latest build is on the [releases page](https://github.com/kennethreitz/onyx/releases/latest). Unzip it and drag `Onyx.app` to `/Applications`.

This build is not notarized, so the first launch needs System Settings ▸ Privacy & Security ▸ **Open Anyway**. It updates itself from v0.1.1 on. Requires macOS 14 (Sonoma) or later, on Apple silicon or Intel.

Opening a second copy of Onyx (a newly built app, `open -n`, or another folder with the same app) quits the one that's already running, after it saves. Set `ONYX_ALLOW_MULTIPLE=1` if you want both to stay open.

## Build from source

```sh
git clone https://github.com/kennethreitz/onyx && cd onyx
make install            # universal (Apple silicon + Intel) build into /Applications/Onyx.app
make install ONE_ARCH=1 # this machine's architecture only (faster); also `make install-native`
make install ARCH=arm64 # one slice (arm64 or x86_64)
```

`make install` builds the same universal app as `make release` (without the zip), asks a running Onyx to quit (it saves first; never force-killed), swaps the new app in with `ditto` so the signature is kept, then prints the installed version and architectures. `make install ONE_ARCH=1` or `make install-native` does the same install for only this machine's architecture; `ARCH=arm64` or `ARCH=x86_64` selects the slice. `INSTALL_DIR=~/Applications` (or `DESTDIR`) installs elsewhere, `NO_QUIT=1` skips quitting, `RELAUNCH=1` reopens Onyx if it was running, and `make uninstall` removes it. Details and other targets are in [Building from source](docs/DEVELOP.md).

## Docs

- [Reading](docs/reading.md) — typography, sidenotes, PDF and print
- [Graph and atlas](docs/graph.md)
- [Bases](docs/bases.md)
- [Canvas and Kanban](docs/boards.md)
- [Getting around](docs/navigation.md)
- [Attachments](docs/attachments.md): drag, drop, paste, the file viewers, and image sizes
- [Web clipper](docs/web-clipper.md): the bookmarklet, Clip Web Page…, templates, and `onyx://clip`
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

## Third-party code

- **Readability.js** 0.6.0 by Mozilla — Apache License 2.0 ([`Resources/web/clipper/LICENSE-Readability.md`](Resources/web/clipper/LICENSE-Readability.md)), used by the [web clipper](docs/web-clipper.md).

## Fonts

The bundled typefaces keep their own licenses, which are compatible with this AGPL distribution:

- **Latin Modern** — GUST Font License ([`Resources/fonts/licenses/GUST-FONT-LICENSE.txt`](Resources/fonts/licenses/GUST-FONT-LICENSE.txt))
- **ET Book** — MIT ([`Resources/fonts/licenses/ET-Book-MIT.txt`](Resources/fonts/licenses/ET-Book-MIT.txt))
- **IBM Plex Mono** — SIL Open Font License 1.1 ([`Resources/fonts/licenses/IBM-Plex-OFL.txt`](Resources/fonts/licenses/IBM-Plex-OFL.txt))
- **OpenDyslexic** — SIL Open Font License 1.1, with Reserved Font Name OpenDyslexic, by Abbie Gonzalez ([opendyslexic.org](https://opendyslexic.org), [source](https://github.com/antijingoist/opendyslexic)). License: [`Resources/fonts/licenses/OpenDyslexic-OFL.txt`](Resources/fonts/licenses/OpenDyslexic-OFL.txt). A typeset reading style in Settings ▸ Reading, next to Latin Modern and ET Book.
