<p align="center">
  <img src="docs/hero.png" alt="Onyx: the atlas view of a vault, regions colored and typeset" width="100%">
</p>

<h1 align="center">Onyx</h1>

<p align="center"><b>Notes, typeset.</b><br>
A native macOS notes app for plain Markdown. Obsidian-compatible, quiet by design.</p>

---

Onyx opens to your words and nothing else. It edits like iA Writer and reads like a typeset
paper, in Latin Modern with justified, hyphenated text. Underneath it's just
a folder of `.md` files: your Obsidian vault opens as-is, and Obsidian (and Obsidian Sync) can
keep working right alongside it.

## Philosophy

- **The page is the interface.** No toolbars, tabs or sidebars until you ask for them. Every
  panel is one keystroke away, and <kbd>Esc</kbd> puts it back.
- **Typeset reading.** Reading view looks like a paper you'd want to print: the Reitz LaTeX
  theme, with Tufte-style sidenotes, proper footnotes, tables and callouts.
- **Your files stay yours.** Plain Markdown on disk, frontmatter, `[[wikilinks]]`, tags and
  attachments. No database, no lock-in, no account. Saves are atomic and conflict-aware, so
  sync tools and other editors stay safe.

## Features

<p align="center"><img src="docs/reader.png" alt="Reading view: a note typeset in Latin Modern" width="85%"></p>

- **Obsidian vaults, as they are**: wikilinks with aliases and headings, embeds, frontmatter
  properties, nested tags, folder notes, `%%comments%%`, callouts, footnotes, Mermaid.
- **Two modes, one keystroke**: a calm Plex Mono editor with live Markdown styling, and a
  typeset reader. <kbd>⌘↩</kbd> flips between them and saves.
- **A graph worth opening**: the *focus graph* puts the current note at the center with its
  links around it, and you travel by clicking. The *atlas* zooms out to your whole vault as
  colored regions (folders or tags) that open into sub-regions and notes as you zoom.
  Filters by folder, tag and recency; orphans on demand.
- **Git, continuously**: if your vault is a git repo, Onyx commits as you write (naming the notes), pulls and pushes in the background, never force-pushes, and keeps both versions on a conflict. A tiny footer glyph shows synced / syncing / offline / conflict.
- **Obsidian Sync, optional**: off by default and opt-in per vault. In Settings ▸ Obsidian Sync, sign in to your Obsidian account (2FA supported), pick a remote vault, enter its encryption password, preview what the first sync will do, then connect. Onyx speaks Obsidian's end-to-end encrypted sync protocol and merges Markdown the way Obsidian does. The first sync never deletes on either side, large deletions pause for confirmation, and credentials live in the macOS Keychain. Unofficial and still new: try it on a throwaway vault first. If you'd rather not, Obsidian's official [`obsidian-headless`](https://www.npmjs.com/package/obsidian-headless) CLI (`npx obsidian-headless`) can keep a folder in sync while Onyx simply edits the files. Protocol notes are in [docs/obsidian-sync-protocol.md](docs/obsidian-sync-protocol.md).
- **Built in, not bolted on**: daily notes, backlinks, outline, properties, bookmarks, recent
  files, search, a quick switcher and a command palette, Dataview-style `TABLE`/`LIST`
  queries, Kanban boards, git status and commit, and RhymePad highlighting for verse.
- **A quick switcher that gets you**: ⌘O ranks exact > prefix > initials > substring > fuzzy,
  ignores accents, matches folders and aliases ("hebrew aleph", "hl", "resume" → Résumé),
  highlights what matched, opens in a split with ⌘↩ and creates with ⇧↩.
- **Split panes**: <kbd>⌘D</kbd> side by side, <kbd>⇧⌘D</kbd> stacked, up to four, divided by a
  hairline. Each pane keeps its own note and its own read/edit mode; the title path follows
  the focused one.
- **Quiet chrome**: a whisper of a title path (click a folder to reveal it and open its folder
  note), an auto-dimming footer with word count, a sidebar and inspector you can drag as narrow
  as 140pt (double-click the edge to reset), and a
  focus mode that leaves only text.
- **Light, dark or auto**, set in <kbd>⌘,</kbd> along with text size and line measure.

<p align="center">
  <img src="docs/focus-graph.png" alt="Focus graph centered on a note" width="49%">
  <img src="docs/title-path.png" alt="Title path revealing a folder in the sidebar" width="49%">
</p>

## Keys

| Key | Does |
| --- | --- |
| <kbd>⌘O</kbd> | Quick switcher: find or create a note (⌘↩ opens in a split, ⇧↩ creates) |
| <kbd>⌘P</kbd> · <kbd>⇧⌘P</kbd> | Command palette |
| <kbd>⌘K</kbd> | Show or hide the sidebar (opens on Files) |
| <kbd>⇧⌘F</kbd> | Search the vault |
| <kbd>⌘I</kbd> | Inspector: outline, backlinks, properties |
| <kbd>⌘G</kbd> · <kbd>⇧⌘G</kbd> | Focus graph · atlas |
| <kbd>⌘↩</kbd> | Read ⇄ edit, and save (also <kbd>⌘E</kbd>) |
| <kbd>⌘T</kbd> · <kbd>⌘\\</kbd> | Today's daily note |
| <kbd>⌘D</kbd> · <kbd>⇧⌘D</kbd> | Split side by side · stacked |
| <kbd>⌘W</kbd> | Close the focused pane (the window, when there's one pane) |
| <kbd>⌃⇥</kbd> · <kbd>⌃⇧⇥</kbd> | Next / previous pane (or just click one) |
| <kbd>⌘[</kbd> · <kbd>⌘]</kbd> | Back / forward (per pane; mouse buttons and swipe too) |
| <kbd>⌥⌘[</kbd> · <kbd>⌥⌘]</kbd> | Previous / next daily note |
| <kbd>⌘⌫</kbd> | Delete note (to the Trash, after a confirm; also right-click any file) |
| <kbd>⇧⌘M</kbd> | Move note to… a folder (fuzzy; type a new name to create one). Rename from File or right-click |
| <kbd>⌘N</kbd> | New note |
| <kbd>⌃⌘F</kbd> | Focus mode: just the text |
| <kbd>⌘,</kbd> | Settings |
| <kbd>Esc</kbd> | Put away whatever's on top |

Every command is also in the menu bar with its shortcut.

## Build and run

Requires macOS 14+ and Swift 5.10 (Xcode 15.3 or newer).

```sh
make run                       # build Onyx.app and open your vault (last opened, else ~/Notes)
make run VAULT=~/path/to/vault # or any folder of Markdown
make run-test                  # open the disposable test copy (/tmp/onyx-vault), never ~/Notes
make test                      # core + reader tests
make install                   # copy Onyx.app to /Applications
```

The app is a SwiftPM package: `OnyxCore` (vault index, parsing, link resolution, Dataview-lite,
graph layout) and `Onyx` (SwiftUI + AppKit, with a WKWebView reader). Design notes live in
[DESIGN.md](DESIGN.md).

## Status

Early, and moving fast. It is tested against a real vault of a few thousand notes, but expect
rough edges. Back up your vault (or point Onyx at a copy) while it settles.

## License

Onyx is licensed under the [GNU Affero General Public License v3.0](LICENSE).
