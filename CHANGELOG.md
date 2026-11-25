# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Double-click a folder circle in the atlas to zoom and pan so that circle fills the view, with a little margin (about 0.3s ease). Double-click empty background, or press Esc, to animate back to the whole vault. Esc still closes the atlas when everything is already in view. Single-click is unchanged (click a region to enter it, click a note to focus it); a double-click does not also fire the single-click.
- `make install` builds the universal (arm64 + x86_64) app and installs it to `/Applications/Onyx.app`. A running Onyx is asked to quit first (it saves; never force-killed), the new bundle is copied with `ditto` beside the old one and swapped in so the code signature is kept, and the installed version and architectures are printed. `INSTALL_DIR` / `DESTDIR` choose another location (quitting only happens for the real `/Applications`), `NO_QUIT=1` skips it, `RELAUNCH=1` reopens Onyx if it was running, and `make uninstall` removes the app. It replaces the old native-only `cp -R` target.
- `make install ONE_ARCH=1` (or `make install-native`) is the same install, but builds only this machine's architecture (`uname -m`) in release config, so it is faster than a universal binary. `ARCH=arm64` or `ARCH=x86_64` selects the slice, alone or with `ONE_ARCH=1`.

### Changed
- Atlas folder circles keep a clear gap between their edges, so neighbors no longer overlap or sit on top of each other. Very large folders use a compressed size scale (a soft cap on radius) so they don't swallow the canvas, and small ones such as Home keep a minimum size and stay visibly separate. Cluster titles and note-count labels sit inside their own circle. The view still fits the whole atlas after layout, and the layout is deterministic from one open to the next.
- The vault's home note is shown in semibold in the file tree. The path is the Obsidian Homepage plugin's note when that's set, otherwise `Home.md` at the vault root. If that note is a folder note, the folder row is bold, since the file itself is hidden.

### Fixed
- Wide tables in the reader no longer crush a column to a single character or wrap dates at the hyphen. Each wrapping column keeps a minimum of 8em and wraps on words (including long wikilink titles); dates, numbers, and other short unbreakable cells stay on one line. A table whose column minimums fit the measure stays in the measure and wraps prose there — it does not bleed or force a long description onto one line. Only when the minimums exceed the measure may it use a little of the pane on either side, and it then scrolls horizontally inside its own container rather than overflowing or clipping. A 4px always-visible, low-contrast scrollbar appears when (and only when) the wrap actually overflows. Booktabs rules and Latin Modern are unchanged. The editor is source Markdown, so this is the reader (and hover previews that use it).
- Mermaid diagrams get the same extra room, but only when the SVG is naturally wider than the measure: up to 8rem of the pane on each side (with a 1.2rem gutter at the edge). A figure that is only modestly wider than that bled width (up to about 25%) is scaled down to fit it; a wider one stays at its natural size and scrolls, with the same thin scrollbar and a soft right-edge fade, instead of clipping mid-shape with no cue that there is more. Small diagrams are not upscaled or stretched.

## [0.1.15] - 2026-11-25

### Changed
- ⌘I in the editor (and from the Format menu / command palette) toggles italic: a selection is wrapped in `*…*`, or unwrapped if it is already wrapped in `*` or `_`. With no selection, it inserts `**` with the caret in between; a second press inside an empty pair removes it. ⌘B already toggled bold the same way (`**` / `__`) and still does; both are one undo step and are not intercepted during IME composition. The inspector moved to ⌥⌘I (the macOS Inspector convention), which still works while the editor has focus.

## [0.1.14] - 2026-11-23

### Added
- Numbered lists are renumbered automatically after Return, Tab / Shift-Tab (and the Indent / Outdent / Delete Line commands), and after Backspace, Delete, or cut that leaves items out of sequence. The list's starting number and delimiter (`.` or `)`) are kept, nested lists are numbered on their own, and a blank line (or a non-list line) ends the contiguous list, so two lists separated by a blank stay independent. Inside a fenced code block or frontmatter nothing is rewritten. The caret moves if a nearby number grows (9 → 10), and the fix is the same undo step as the edit that caused it. Follows `smartIndentList` like the rest of list continuation.

## [0.1.13] - 2026-11-23

### Changed
- Clicking the current note name in the title bar no longer copies its wikilink, and the brief “copied” label is gone. The name is plain text. Folder and ancestor crumbs still navigate, and the `class:` tag is unchanged. Copy Wikilink (⇧⌘L) and Copy File Path remain in the command palette and menus.

## [0.1.12] - 2026-11-23

### Added
- Smart pairs in the editor, like Obsidian's Auto pair brackets and Auto pair Markdown syntax. Typing `(`, `[`, `{`, or a quote (`"`, `'`, `` ` ``) inserts the closer with the caret in between; `[[` becomes `[[|]]` and still works with wikilink autocomplete. Quotes do not pair mid-word, so `don't` is left alone. With a selection, those and `*` `_` `~` `=` wrap the text (type `*` twice for `**bold**`) and keep the inner selection. Typing the closer when it is already the next character steps over it. Backspace in an empty pair deletes both. Markdown markers are not auto-paired without a selection, and are left alone inside fenced code. Each action is one undo step, and IME composition is not intercepted. Honors `autoPairBrackets` and `autoPairMarkdown` in `.obsidian/app.json` (on when missing), also in Settings ▸ Editor.

## [0.1.11] - 2026-11-23

### Fixed
- ⌘⌫ in the editor (and in any text field) is once again the standard Mac delete-to-beginning-of-line, or it deletes the selection if there is one. It had been bound to Delete Note…, so typing it tried to trash the whole note. ⌘⌫ still deletes the selected file(s) when the file tree has focus, like Finder, after a confirm. ⌥⌫ was not bound and still deletes the previous word. Delete Note… has no default shortcut (File menu and command palette still have it); Settings ▸ Shortcuts treats ⌘⌫ and ⌥⌫ as reserved, and will not put them on a menu item.

## [0.1.10] - 2026-11-23

### Added
- Return in a list continues it: the same `-` / `*` / `+` bullet, the next number (`1.` / `1)`), or a new unchecked task (`- [ ]`, even after `- [x]`). Indent is kept, and a blockquoted list keeps its `> ` prefix. Return in the middle of an item splits the text onto the new item. Return on an empty item ends the list, or outdents one level if it’s nested, the way Obsidian does. Shift-Return inserts a plain newline. Tab and Shift-Tab indent and outdent list items. It is one undo step, and it does not fire during IME composition, inside a fenced code block, or in frontmatter. Honors `smartIndentList` in `.obsidian/app.json` (on when the key is missing), also in Settings ▸ Editor.

## [0.1.9] - 2026-11-23

### Added
- Image sizes in embeds, Obsidian-style ([docs](docs/attachments.md#image-size)): `![[photo.png|300]]` (width, height in proportion), `![[photo.png|300x200]]`, `![[photo.png|caption|300]]`, and Markdown `![300](img.png)` / `![alt|300x200](https://…)`. Video embeds take a width too. Images never grow past the text column. Before, only a bare `|300` on a wikilink worked, and the height was ignored.
- Drag to resize images in the reader: hover an embed for a corner grip, drag to resize with the aspect ratio kept (a live width label shows the size), and let go to write the width into that exact embed, so the same image elsewhere in the note is left alone. Double-click the grip to remove the size. Alt text, `#heading` parts, and table `\|` escaping are kept. It saves through the normal path, as one undo step when the editor holds the note. A plain click still opens the image viewer.
- Renaming or moving any file keeps every link to it working: attachments (images, audio, PDFs, anything), notes, canvases, and whole folders ([docs](docs/attachments.md#renaming-and-moving)). It works from sidebar rename, drag and Move to…, the new **Rename…** button in the attachment viewer header, and Command Palette ▸ Rename File… (was Rename Note…).
  - Rewritten: `[[name]]`, `![[name]]`, `[[name|alias]]`, `[[name#heading]]`, `![[img.png|300]]` (suffixes kept), path and relative wikilinks, Markdown links and embeds (`%20` kept), frontmatter and field links, and canvas file cards. Code, `%%comments%%`, `.obsidian`, and excluded files are left alone.
  - Bare-name links stay bare while the name is still unique. Otherwise they become a path in the vault's New link format.
  - Follows Obsidian's **Automatically update internal links** (`alwaysUpdateLinks`), now in Settings ▸ Files & Links. When it's off or unset, Onyx asks "Update N links in M files?" with Update, Don't Update, and Always Update. A multi-file move asks once.

### Fixed
- The footer's Read Aloud pause and stop controls slid sideways when you hovered the bar to click them: hover expands the word count with character and backlink counts, and that width change (animated with the rest of the footer) shoved the chip. The count now reserves the expanded width, the Reading/Paused label and speaker icon keep a fixed width, and a toast no longer shares the bar's layout. Pause and stop stay put, with 22-pt hit targets.
- A bare `[[Name]]` link no longer silently starts pointing at a different note after a move. That could happen when its note moved away from a same-named neighbor, or when another file with that name moved to the vault root. Onyx now writes the path it needs.
- Renaming the attachment open in the viewer keeps it open, instead of showing "This file is gone".
- Relative wikilinks (`[[../Note]]`, written by Obsidian's relative link format) resolve.
- Renaming or moving a file no longer risks dropping the last second of typing in the open note when that note's links get rewritten.
- The update window showed GitHub release notes as raw Markdown. They now render as formatted text: section labels, nested lists, bold, italic, inline code, and clickable links. Relative links such as `[docs](docs/obsidian-settings.md)` open the file at that tag on GitHub.
- Closing the last window with ⌘W or the red button no longer quits Onyx. The app stays running with no windows; click the Dock icon or choose File ▸ New Window to restore the vault window with the previous notes and layout. Closing still saves unsaved notes and the split layout. Obsidian Sync and git autocommit keep running. Reading aloud, audio and video playback, and an in-progress recording stop (the recording is saved). ⌘Q still quits, and launching a second packaged Onyx still asks the running copy to quit and save first.



## [0.1.8] - 2026-11-23

### Added
- Obsidian's core settings are editable in Onyx's Settings, and they write to the vault's own `.obsidian` files so Obsidian and Onyx stay in sync ([docs](docs/obsidian-settings.md)).
  - **Files & Links** (`app.json`): default location for new notes, new link format, Use [[Wikilinks]], default location for new attachments (vault folder, same folder, a subfolder under the current folder, or a named folder), default view, and excluded files.
  - **Daily Notes** (`daily-notes.json`, `templates.json`): date format with a live preview, new file location, template file, open daily note on startup, and the Templates folder, date format, and time format.
  - Only changed keys are written. Unknown keys keep their order and exact text. Writes are atomic, a missing file is created, and invalid JSON is left alone. Changes from Obsidian or Sync are picked up live. Folder and file fields have a picker limited to the vault, and typed paths are checked.
- Onyx now honors more of Obsidian's settings:
  - The daily-note date `format` is a moment.js format, including `/` for dated folders. Before, it was always `YYYY-MM-DD`.
  - The daily-note `template` is used, with `{{date}}`, `{{title}}`, `{{time}}`, and `{{date:FORMAT}}` filled in. An empty template keeps Onyx's built-in daily note.
  - `autorun` opens today's note when the vault opens.
  - Templates' `dateFormat` and `timeFormat` set what Insert Current Date and Insert Current Time insert.
  - `newFileLocation` and `newFileFolderPath` decide where ⌘N, the quick switcher's create, and unresolved-link clicks put new notes. With no setting, Onyx's old behavior stays.
- Attachments open in the pane, like notes ([docs](docs/attachments.md#opening-attachments)). Click an embed or link in the reader, ⌘-click `[[file]]`, `![[file]]` or `[text](file)` in the editor, or open the file from the sidebar, the quick switcher (attachments are listed by full file name), Recent, a canvas, or a base. ⌘[ (or the header's back chevron) goes back to the note. Before, they opened in another app or did nothing.
  - **Audio**: Onyx's own player. It has a waveform scrubber (click or drag to seek), elapsed and remaining time, play/pause (Space), 15-second skips (← →), speed from 0.75× to 2× (remembered, pitch kept), and volume. When Record Audio left a transcript under the embed, the player shows it with a link back to that note. Playback stops when you leave the file. It plays m4a, mp3, aac, wav, aiff, caf, flac, and 3gp. Formats AVFoundation can't play (Ogg, Opus) get a file card instead.
  - **Images**: fit to the pane by default (never enlarged past 100%), zoom in/out from the header or by pinching, actual size, drag to pan, and double-click to switch between fit and actual size. GIFs animate. The header shows pixel dimensions.
  - **PDFs**: PDFKit with continuous pages, page n / N with previous and next, zoom and fit-width, and find (↩ next match, ⇧↩ previous, highlighting every hit).
  - **Video**: AVKit's player, with duration and dimensions in the header.
  - **Anything else**: a file card with its icon, type, size and date, plus Open in Default App and Reveal in Finder.
  - Every file view's header shows the file's kind and size, the notes that link to it, Open in Default App, and Reveal in Finder.
- Reader audio embeds are a quiet one-line player in Onyx's chrome scales, replacing WebKit's default control: play/pause, a hairline progress track you click to seek, time, and the file name, which opens the full player. Starting one embed pauses the others. Video and PDF embeds get the same "name ↗" link to their viewer, and clicking an embedded image opens it in the image viewer. Markdown embeds of audio, video and PDFs (`![](clip.mp3)`) render as players and PDFs too, where before they showed a broken image.
- Drag, drop, and paste attachments into the editor, as in Obsidian ([docs](docs/attachments.md)).
  - What you can add:
    - files from Finder, several at once;
    - images dragged from a browser, Photos, or Mail;
    - an image on the clipboard, saved as `Pasted image YYYYMMDDHHmmss.png`;
    - files copied in Finder.
  - Each file is copied into the folder set by `.obsidian/app.json`'s `attachmentFolderPath`: the vault root, `./`, `./sub`, or a fixed folder. A taken name gets a number (`photo 1.png`).
  - The link goes in at the drop point and honors `useMarkdownLinks` and `newLinkFormat` (shortest, relative, or absolute). Images, audio, video, and PDFs are embedded with `!`. Notes and other files are linked.
  - Files already in the vault aren't copied. A ⌘-drag from the sidebar, or a Finder drag of a file inside the vault, inserts a link to the existing file.

### Changed
- Launching a second packaged Onyx (another build, `open -n`, or a worktree app with the same bundle identifier) now asks the running copy to quit first. That copy saves unsaved notes and session state, then exits; the new copy waits for it (up to 10 seconds) before restoring the window and vault, and never force-kills it. Set `ONYX_ALLOW_MULTIPLE=1` (or the hidden default `onyx.allowMultipleInstances`) to keep both. Test hooks (`make run-test`, `make dev`, `scripts/shoot.sh`, and the usual `ONYX_*` screenshot and self-test variables) skip this so a test launch cannot close a running Onyx. Unpackaged `swift run` binaries are left alone. See [DEVELOP.md](docs/DEVELOP.md#one-running-onyx).
- The title-bar graph button (and ⌘G, the footer graph icon, and the command palette) is a toggle: click it again while the graph overlay is open to close it and return to the note. Shift-click or ⇧⌘G still opens the atlas, and closes it if the atlas is already showing. The title-bar button stays marked while the graph is open.

### Fixed
- The Graph tab in Settings showed no icon: it used `point.3.connected.trianglepath`, which is not an SF Symbol. It now uses `point.3.connected.trianglepath.dotted`, the same icon as the title-bar graph button.
- Markdown image embeds (`![](…)`) in the reader resolve as Obsidian resolves them: next to the note, then from the vault root, then by name. Before, they only worked relative to the note.

## [0.1.7] - 2026-11-23

### Performance
- Faster everywhere on a large vault. Timings below are from `onyx-bench` against a copy of a 2,561-note vault (release build, best of 5, Apple silicon). Results are the same as before: search hits, backlinks, Dataview rows, the ⌘O ranking, and every note's parsed links, fields, and headings were diffed old against new on that vault, and they match.
  - Saving a note no longer reindexes the whole vault. Only that note's links, tags, and relations are swapped out: 141 → 2.7 ms per autosave. The file-watcher echo of the save is 117 → 2.8 ms, and 50 files changed one at a time (a sync burst) is 3.2 s → 0.19 s.
  - Onyx's own saves are no longer read back from disk and republished when the watcher sees them. That saves a second index rebuild and a sidebar and ⌘O refresh after every pause in typing.
  - Cold vault open is 395 → 197 ms. Fence, heading, and inline-field parsing are 2–3× faster, and links resolve in parallel.
  - Full-text search is 333 → 62 ms for “consciousness”, 444 → 26 ms for “the”, and 433 → 90 ms for two terms.
  - Inspector backlinks on the most-linked note are 65 → 45 ms, and unlinked mentions are 77 → 11 ms.
  - Dataview: `WHERE type = "alter"` over the vault is 1,163 → 2.3 ms (date formatters were being rebuilt for every value), `LIST FROM … WHERE` is 137 → 0.4 ms, and `TASK` is 267 → 19 ms.
  - The ⌘O index rebuild is 46 → 28 ms. Sidebar date sorting is 28 → 17 ms.
  - Typing in long notes (30,000+ characters) restyles only the edited lines unless the edit changes a fence, comment, inline code, footnote, or frontmatter: 164 → 58 ms per keystroke in a 300 KB clipping, including layout. The word count and the inspector outline and properties follow long notes about 300 ms after typing stops. Short notes are unchanged.
- `onyx-bench` (`swift run -c release onyx-bench <vault copy>`) times all of the above, and docs/performance.md covers running it and checking that a speedup changes nothing.

### Added
- Folding for headings and nested lists, in the editor and the reader. Hover a heading, or a list item with nested items, and a quiet chevron shows in the margin. A folded line shows a small ⋯ pill. Folding is display only: TextKit hides the glyphs and the note text never changes, so save, sync, find and replace, undo, copy, and completion all see the whole note. The caret steps over folds. Find, Jump to Heading, the outline, `#heading` links, and undo open the folds they land in. Any edit that would change hidden text opens the fold first. Editing a folded heading keeps it folded, and deleting the heading unfolds it. Commands are in View ▸ Folding, the palette, and Settings ▸ Shortcuts: Fold Section ⌥⌘←, Unfold Section ⌥⌘→, Toggle Fold, Fold All Headings and Lists ⌥⇧⌘←, and Unfold All ⌥⇧⌘→. Folds are saved per note on this Mac, shared between the editor and the reader, and follow renames. Settings ▸ Editor ▸ Folding has Fold headings and Fold indent switches, both on by default. Details are in [docs/folding.md](docs/folding.md).
- Note composer, matching Obsidian’s core plugin: Merge Current File With Another File…, Extract Current Selection…, and Extract This Heading…. They’re in the command palette, the Edit menu, and (for the extract commands) the editor’s context menu, and they’re bindable in Settings ▸ Shortcuts, with no default shortcut. Merge asks first, then appends or prepends the open note’s body to a note you pick in the quick switcher, combines frontmatter (target scalars win, lists are unioned), rewrites wikilinks and Markdown links and embeds across the vault so they point at the target, and moves the source to the Trash. Extract writes the selection, or the heading section around the caret, to a new note (or appends it to an existing one), and replaces the original with a link, an embed, or nothing — that’s one undo step in the editor. A selection that starts with a heading offers that heading as the name. Settings ▸ Editor has confirm-before-merge, append vs prepend, where new notes land, and whether to open the extracted note.
- The rest of the DataviewJS API in the JavaScriptCore sandbox: `dv.io.load` / `csv` / `normalize` (vault-relative reads only), `dv.view` (loads `view.js` and optional `view.css` from a vault path), `dv.query` / `tryQuery` / `queryMarkdown` / `tryQueryMarkdown`, `dv.execute` / `executeJs`, `dv.evaluate` / `tryEvaluate`, plus `pagePaths`, `array` / `isArray`, `fileLink` / `sectionLink` / `blockLink`, `duration`, `compare` / `equal`, `clone`, `parse`, and `markdownTable` / `markdownList` / `markdownTaskList`. Async calls return Promises and can be `await`ed. There is still no network and no file writing; paths cannot escape the vault.
- Dataview `FROM` sources for links: `[[Note]]` and `incoming([[Note]])` (pages that link to a note), `outgoing([[Note]])` (pages a note links to), and `[[]]` / `[[#]]` for the current file. `AND` / `OR` / `-` exclusion and parentheses work across folders, tags, and link sources.

### Polish
- Command palette and quick switcher: the selected row is an inset, rounded wash instead of a full-width bar, rows get a soft hover, and shortcuts are drawn as quiet keycaps (⇧ ⌘ P), as are the ↩ / ⌘↩ / ⇧↩ / esc hints underneath. The first-run hints card and the “Nothing open” page use the same keycaps.
- Empty states share one voice: a line of italic serif plus a hint of what fills it (outline, linked and unlinked mentions, properties, recent, bookmarks, source control). Search shows a hint before you type and “Nothing matches” when nothing does, instead of a bare “0 results”.
- The sidebar search field shows a slate focus ring; tag rows get the same hover wash as note rows, with tabular counts.
- Reduce Motion is respected everywhere: panel and overlay springs become short dissolves, slides and scale-ins become fades, the reader drops its lift-in and smooth heading scrolls.
- Conflicts, refused drops, sync errors, find with no matches, and the recording dot use inked amber and madder tints from the palette instead of system orange and red.
- Chrome labels (counts, hints, section labels) are a shade darker in light mode so they clear ~4:1 on paper; editor syntax stays exactly as faint as before.
- Reader: finer link underlines that skip descenders and fade on hover, a visible keyboard focus ring on links, `<kbd>` drawn as a small keycap, superscripts and subscripts no longer open up their line in plain (non-typeset) reading, and dark-mode selection matches the editor.
- Under the hood: one spacing scale, four corner radii, a chrome type scale, and named motion curves in `Theme.swift` (see docs/DESIGN.md ▸ Scales).

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

[Unreleased]: https://github.com/kennethreitz/onyx/compare/v0.1.15...HEAD
[0.1.15]: https://github.com/kennethreitz/onyx/compare/v0.1.14...v0.1.15
[0.1.14]: https://github.com/kennethreitz/onyx/compare/v0.1.13...v0.1.14
[0.1.13]: https://github.com/kennethreitz/onyx/compare/v0.1.12...v0.1.13
[0.1.12]: https://github.com/kennethreitz/onyx/compare/v0.1.11...v0.1.12
[0.1.11]: https://github.com/kennethreitz/onyx/compare/v0.1.10...v0.1.11
[0.1.10]: https://github.com/kennethreitz/onyx/compare/v0.1.9...v0.1.10
[0.1.9]: https://github.com/kennethreitz/onyx/compare/v0.1.8...v0.1.9
[0.1.8]: https://github.com/kennethreitz/onyx/compare/v0.1.7...v0.1.8
[0.1.7]: https://github.com/kennethreitz/onyx/compare/v0.1.6...v0.1.7
[0.1.6]: https://github.com/kennethreitz/onyx/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/kennethreitz/onyx/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/kennethreitz/onyx/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/kennethreitz/onyx/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/kennethreitz/onyx/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/kennethreitz/onyx/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/kennethreitz/onyx/releases/tag/v0.1.0
