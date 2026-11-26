# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- The left sidebar has an Outline tab after Files, sharing the same pane and behaviour as the inspector Outline tabs (current-note outline, click-to-scroll with the landing offset, scroll-spy, auto-collapse, closing graph mode on click, and index-heading dedupe). The selected sidebar tab is remembered. Command Palette ▸ Outline in Sidebar opens it; the inspector Outline stays on <kbd>⌥⌘1</kbd> ([docs](docs/navigation.md)).
- The iOS app (`ios` branch only) has a vault file tree as its primary Files tab (the same `FileNode` / `TreeSort` / `FolderTreeClick` models as the Mac sidebar): folders before notes in the vault's sort order, disclosure triangles whose expanded state is remembered per vault, the open note highlighted with its ancestors revealed, new note / new folder / rename (with optional link updates) / delete with confirmation, and pull-to-refresh. Searching that tab still uses the flat note list. Bookmarks, Tags, Outline, and Find stay in the sidebar. It works for a picked folder and for a sync-only Obsidian Sync vault ([docs](docs/IOS.md#screens-added-after-the-first-cut)).
- The iOS app (`ios` branch only) can open a sync-only Obsidian Sync vault: Connect Obsidian Sync Vault (in the empty state and the Vault menu) signs in with the Keychain (2FA when asked), lists your remote vaults, checks the end-to-end password, creates a local copy inside the app (`Application Support/Onyx/Vaults/<name>`), pulls it down, and keeps it synced while Onyx is open, with a short grace period after you leave the app. A toolbar icon shows the sync status, and Manage Sync has Sync Now, Pause, Disconnect (keeps the copy), Reconnect, and Delete Local Copy (confirmed first). It's the same OnyxSync engine as the Mac, which now builds for iOS ([docs](docs/IOS.md#shared-obsidian-sync-onyxsync)).
- Sync-only vaults: keep an Obsidian Sync vault in Onyx without picking a folder. **Connect Obsidian Sync Vault…** (welcome screen, File menu, and Settings ▸ General ▸ Vault ▸ Sync-only Vault…) signs in (Keychain, 2FA when asked), lists your remote vaults, checks the end-to-end password, creates a local copy in `~/Library/Application Support/Onyx/Vaults/<name>`, pulls everything down, and keeps it synced with the usual footer status. Sync-only vaults are listed with Open, Reveal in Finder, and Delete Local Copy… (confirmed first; deletes only this Mac's copy, never the remote vault). Disconnect keeps the copy for a later reconnect, which reuses it and never deletes on either side. The library and its delete safeguards are in OnyxCore and the connect flow in OnyxSync, tested against the fake sync server; OnyxSync now builds for iOS too ([docs](docs/sync.md#sync-only-vaults)).

### Fixed
- The footer status bar no longer reserves a wide gap for character and backlink counts that only appeared on hover, so a narrower window no longer showed just “370 words” beside a stretch of empty space. Sync, git, and reading chips stay grouped with the counts on the right, with even spacing. As the bar tightens, the counts shrink in priority order — words, then backlinks, then characters — using compact forms (“2,117 chars”, “2 links”, “370w”) before dropping an item. A tooltip always shows the full counts; clicking the counts cycles auto-fit, words, characters, and backlinks ([docs](docs/DESIGN.md)).
- Outline scroll-spy lagged one section behind when a heading sat at the top of the view with a tall table below it (as on Connection Map: “Strongest Pairs” visible, “The Network” still highlighted). The spy compared the heading’s border-box against the landing line plus 1px, so a heading whose 2em top margin was still on screen had not yet “reached” the line. It now uses the margin-box and 2px of slop: the active heading is the last one whose top is at or before the visible top plus the landing offset plus 2px, in both Outline tabs and in the editor. A heading already at the top of the view counts ([docs](docs/navigation.md)).
- Bookmarks in the macOS file sidebar open on a single click again (a note, heading, folder, search, URL, or graph, matching the bookmark's type; a group still toggles). ⌘-click opens a file or folder bookmark in a new split pane. Drag-to-reorder starts only after the pointer moves 4pt, and dropping a note onto Bookmarks still pins it. SwiftUI's `.draggable` had been swallowing the click, and leftover drag-pasteboard types on the drop overlay could steal a later click too.
- iOS (`ios` branch only): signing in to Obsidian Sync in the simulator failed with a raw error-domain message, and a second try said "Already logged in". `make ios` built the app unsigned, so it had no Keychain entitlement and storing the token failed with errSecMissingEntitlement (-34018) right after the server accepted the sign-in; the shared URLSession then kept that session's cookie. `make ios` now signs ad hoc (the Keychain works), the account uses the shared idempotent sign-in, and errors read as sentences.

- Obsidian Sync sign-in no longer wedges after a partial failure. Requests to Obsidian's API now keep no cookies (like the official CLI), so a session cookie from one attempt can't make the next one fail with "Already logged in"; that answer is also retried once from a clean state. A token Onyx already holds is checked (`/user/info`) and reused, and a stale one is signed out and cleared first. If the Keychain refuses the token after the server accepted it, Onyx keeps it for the session instead of failing. Builds with no Keychain access, like the unsigned simulator build (errSecMissingEntitlement), fall back to an owner-only, data-protected file under Application Support/Onyx/Secrets. Errors are shown as plain sentences, never raw error domains; the details go to the log (subsystem `org.kennethreitz.onyx`, category `sync`). Tested against the fake server.
- Clicking a heading in the Outline pane landed it under the title-path paper fade, so the first visible line was often the paragraph under the heading and the outline would then highlight the next section (and sometimes flap). The heading now lands about 20px below the visible top of the reader or editor (under the fade, and under any sticky header, accounting for pinch-zoom), and scroll-spy uses the same offset plus 1px of hysteresis. Auto-select is held until the click-scroll settles, and updating the outline highlight never scrolls the document ([docs](docs/navigation.md)).
- Scrolling a note highlighted the wrong Outline row when the note began with an H1. Body headings were numbered from zero after that title was lifted out, so scroll-spy (and click-to-jump) looked up a neighbour's id. Headings now keep their index in the full list; the active row is the last heading whose top is at or above the landing offset, in both Outline tabs and in the editor. Headings inside callouts, blockquotes, and embeds are ignored, matching the outline. Updating the highlight still does not scroll the document ([docs](docs/navigation.md)).
- Clicking an Outline heading or title row while graph mode is open closes the graph first, then jumps to the target, with the same click-scroll hold.

### Changed
- The inspector is always docked. The pin button and auto-hide overlay are gone; <kbd>⌥⌘I</kbd> still shows or hides it ([docs](docs/navigation.md)).
- In the vault-wide and folder Outline, a heading in a folder's index note is omitted when it only names a sibling subfolder or child note (case-insensitive, ignoring extra whitespace and markdown or wikilink markup, including a `[[wikilink]]` to the subfolder or its index). The folder or note row is kept; unique headings stay ([docs](docs/navigation.md)).
- The outline auto-collapses branches that are off the path of the current heading: only the ancestor chain and that heading's own children stay open. Top-level rows stay visible. A branch you expand by hand stays open until the path leaves it.
- In folder, neighbors, and vault scopes, a leading H1 is the note's title row and is not listed again as a child. In This note, that H1 is the root of the tree. Clicking the title row opens the note or scrolls to the top.
- The inspector keeps Outline as its first tab (<kbd>⌥⌘1</kbd>) and also shows the same Outline pane as the last tab. The selected inspector tab is remembered.

## [0.1.18] - 2026-11-25

### Added
- The iOS app (`ios` branch only) has a Tags tab with the same hierarchical tag tree as the Mac Tags pane, from OnyxCore: nested tags under disclosure chevrons (expansion remembered), counts that include nested tags with the exact count beside them, sort by name or count, a filter, Exact Matches Only, and the notes of the selected tag. Tapping a tag in the reader opens the Tags tab on it instead of a search.
- Groundwork for an iPhone and iPad app, on the `ios` branch only: `OnyxCore` compiles for iOS 17, `ReaderPayload` is shared, and `OnyxMobile` is a SwiftUI shell that opens a vault folder (document picker + security-scoped bookmark), lists and searches notes, jumps to today’s daily note, and renders one in the typeset WKWebView reader. See [docs/IOS.md](docs/IOS.md). Not a release.
- The iOS app (still the `ios` branch only) now has screens for today's Mac features, all backed by OnyxCore: a Bookmarks tab that reads and writes `.obsidian/bookmarks.json` (pin or unpin from a swipe or the note menu); an Outline with This note / Folder / Linked & partOf / Whole vault and lazy expansion; Backlinks plus unlinked mentions, with Link and Link all that write through the security-scoped vault folder; vault Find with a replace preview (and Replace selected, also writing through that folder); a Reading pane for Latin Modern, ET Book, and OpenDyslexic (same UserDefaults keys as the Mac app); and Version History, which tells you plainly that git isn't on iPhone rather than inventing a stand-in. The web clipper stays Mac-only (`HTMLToMarkdown` needs macOS `XMLDocument`). Not a release.
- The iOS app (`ios` branch only) has the Onyx icon, the same onyx crystal with its note graph as the Mac app: `Resources/AppIcon.icns` scaled to a full-bleed, opaque 1024px square in `Resources/iOS/Assets.xcassets` (one universal icon; Xcode makes the sizes), rendered by `swift scripts/make-ios-icon.swift`. It was a blank placeholder before. Not a release.
- Hierarchical tags, Obsidian-compatible. The Tags sidebar is a tree: `#parent/child/grandchild` nests under disclosure triangles (⌥-click opens a whole branch), expansion is remembered per vault, and each node counts the notes with that tag or any nested one, with the notes tagged exactly there shown faintly beside it when they differ. Sort by name or count, and filter tags by any part of their path. Clicking a tag lists its notes under the tree, including nested tags like Obsidian's `tag:#parent`, with an Exact option for only that tag. Right-click ▸ Rename… renames or moves a tag and its whole subtree across the vault, inline and in frontmatter `tags:` (inline lists, block lists, and plain values), skipping code. A sheet previews every changed line before writing and warns when two tags will merge. Undo Rename is in the sort menu. Drag a tag onto another to nest it there, or below the tree to make it top-level. Typing `#` in the editor (or a value in a frontmatter `tags:` list) completes tags by path segment: `#projects/` offers the children of `#projects`. Tags in the reader, ⌘-clicked tags in the editor, and the new tag chips in the inspector open the Tags pane on that tag. Tags compare case-insensitively, the tree uses the spelling seen most, and Unicode tags work (`#café`, `#📚`). The logic lives in OnyxCore with tests, and it stays fast on large vaults: the tree builds in about 3 ms for 2,600 notes, and rename previews run off the main thread ([docs](docs/tags.md)).
- The inspector Outline pane (<kbd>⌥⌘1</kbd>) can widen past the open note: a scope control at the top chooses This note, Folder, Linked & partOf, or Whole vault. Notes become top-level rows with their heading trees nested and collapsible; folders and `partOf` parents give the structure. Click a heading to open that note and jump there. The current section highlights while you scroll (reader or editor). Whole-vault mode walks the folder tree lazily — only expanded branches (and a note's headings once that note is opened) are built into the list — so it stays fast on a large vault. The path to the open note is expanded for you.
- The inspector's Backlinks tab (⌥⌘2) now opens a linked or unlinked mention at the matching line, and unlinked mentions — plain-text uses of the current note's title or aliases, case-insensitive and at word boundaries, skipping code, comments, and existing links — each have a Link action that turns that occurrence into a `[[wikilink]]`, plus Link all. A file that already links here can still show other unlinked mentions. The same unlinked list under a note in the reader is clickable (opens at that line) and has Link as well. Logic lives in OnyxCore.
- The git sidebar has a **History** tab for the current note: commits that touched the file (`git log --follow`), with date, author, and message. Choosing one opens a preview of that version against the current text (including unsaved edits). **Restore this version** puts the old text in the editor as an unsaved edit after a confirmation; it never runs `git reset` or `git checkout`. Vaults that are not git repositories get a quiet empty state. Version History is in the command palette and the View menu, and opens the git sidebar on that tab.
- Replace in Vault (⌥⇧⌘F; ⇧⌘H is already Homepage) previews matches across the vault, a folder, or the current note, with match case, whole word, regular expressions (including `$1` capture groups in the replacement), and an option to skip frontmatter. The preview is grouped by file, with per-match checkboxes and before/after highlighting. Replace Selected and Replace All confirm with counts, write notes atomically, update any open editor buffers, and offer a one-shot Undo Last Replace that restores the previous contents. The Search sidebar has a button to open the same panel, pre-filled from the current query. In-note find and replace (⌘F / ⌥⌘F) is unchanged.
- A Bookmarks section sits at the top of the file sidebar (collapse the header to tuck it away). Pin or unpin a note or folder from the context menu, the Note menu, the command palette, or ⌥⌘D, and drag a row to reorder. Groups from Obsidian stay groups; drop a bookmark onto a group to put it inside. Heading bookmarks (right-click a heading in the Outline) and folder bookmarks are first-class, and so are Obsidian search, URL, and graph bookmarks when they're already in the file. The list is stored in `.obsidian/bookmarks.json` in Obsidian's own format, including unknown fields and groups, so the two apps share it. Bookmarks that Onyx used to keep only in UserDefaults are merged in once.
- Drag a note onto the Bookmarks section — the bold Home item, a file-tree row, a search, recent, or backlinks result, or a vault file from Finder — to pin it. The drop target highlights and inserts at that position (onto a group to nest, onto the header or the empty area to append). A note that's already bookmarked is moved there instead of being added twice. Bookmark rows are still draggable to reorder. A plain drag from the file tree is a pin; ⌘-drag still moves files.
- Web clipper. A bookmarklet (Settings ▸ Files & Links ▸ Web Clipper ▸ Copy Bookmarklet, or [docs/web-clipper.md](docs/web-clipper.md)) works in Safari, Chrome, Arc, and Firefox: with nothing selected, Onyx fetches the page in an offscreen, cookie-less web view and keeps only the article (Mozilla Readability.js 0.6.0, Apache-2.0, bundled); with text selected, it clips just the selection as rendered in your browser, so pages behind a login work too. File ▸ Clip Web Page… (⇧⌘K, also in the palette) clips a URL from inside Onyx, prefilled from the clipboard. The article becomes Markdown (headings, emphasis, absolute links, nested and task lists, quotes, fenced code with its language, tables, highlights, captions, YouTube embeds; `$`, `*`, `[` and friends escaped), images stay on the web as hotlinks (`![alt](https://…)`: the largest `srcset` or `<picture>` candidate, lazy-load `data-src` and friends, made absolute; `data:` URIs and tracking pixels dropped; nothing is downloaded into the vault), and the note is saved in `Clippings/` named after the title, with Obsidian Web Clipper-style frontmatter (title, source, author, published, created, description, site, tags, class) and then opened. `class:` and `tags:` follow the clippings already in the folder (else `Source` and `clippings`). Settings: folder, class, tags, and a template note with `{{title}}`, `{{url}}`, `{{content}}` and friends. The app now registers the `onyx://` URL scheme; `onyx://clip?url=…&selection=…&folder=…` works from Shortcuts and scripts too. A Safari share extension isn't possible in the SwiftPM build yet.
- Clip to Onyx, a Safari Web Extension inside Onyx.app (`Contents/PlugIns/OnyxSafari.appex`): after Onyx has been opened once, turn it on in Safari ▸ Settings ▸ Extensions (Settings ▸ Files & Links ▸ Web Clipper ▸ Safari Extension… goes there). A toolbar button and Clip Page / Clip Selection / Clip Link context-menu items send the page, its metadata, and any selection to Onyx through the extension's native handler, which opens `onyx://clip` directly (no "open this app?" prompt), falling back to the `onyx://` link. Onyx also appears in the macOS Share menu (`OnyxShare.appex`) for links and text. Both are built by `scripts/build-extensions.sh` with `swiftc` from `scripts/bundle.sh` (universal for releases; `SKIP_EXTENSIONS=1` skips them), sandboxed, and signed before the app. Safari lists the extension only when Onyx is signed by an Apple Development or Developer ID certificate; with the default Onyx Local Signing it needs Safari's Allow unsigned extensions, which resets when Safari quits ([docs](docs/web-clipper.md#signing-why-the-extension-may-not-show-up)).

### Changed
- The History revision sheet defaults to Compare with latest (the chosen commit vs the current note, including unsaved edits). vs previous shows what that commit changed against the next-older version. The last-chosen mode is remembered. Long unchanged stretches collapse to an expandable “Show N unchanged lines” control, in both the rendered Diff and the Line diff. Opening History selects the most recent commit that touched the note. The sheet fills most of the window and the diffs use the full width, with a gutter of line numbers and +/- markers; lines wrap at the sheet edge and highlight bands span the row.
- Auto-commits and the Source Control commit box use a descriptive message generated on-device from the diff (no AI or network): note titles, headings added, removed, or retitled, tasks checked or added, frontmatter fields changed (skipping timestamps), links added, and the usual add / delete / rename / move. Several files become a short subject like “Edit 3 notes: X, Y, Z” with a body of per-file details. The subject stays at most 72 characters. The commit field is prefilled so you can edit it before Commit all.
- The Source Control sidebar opens on the History tab when a note is open (Status if no note is open or the vault isn't a git repository), and the Status / History switcher shares a single row with the branch name. Choosing a revision shows a rendered, reader-style diff by default: insertions on a green highlight, deletions struck through in red, word-level where practical, and the whole block for tables, fenced code, and mermaid. Line diff and a full preview of that version stay a click away; Restore is unchanged. Diff logic lives in OnyxCore.
- “Open in Obsidian” is hidden in menus unless you hold Option. In the Note menu and in note or file context menus it is a hidden alternate of Reveal in Finder, so the two swap while ⌥ is held. The command palette still lists it and is searchable as before. There is no toolbar or title-bar button for it.
- OpenDyslexic is a typeset reading style in the same Settings ▸ Reading typeface picker as Latin Modern (Reitz LaTeX) and ET Book (Tufte), not a separate toggle on top of those faces. It has its own page: all four bundled cuts (Regular, Bold, Italic, BoldItalic) with real weights and styles and no faux bold or italic; a size-adjust so the large x-height and wide glyphs sit closer to the other faces; a 1.65 line-height, slightly relaxed word spacing, no extra letter-spacing, and a measure capped at 60ch; no small caps, old-style figures, hyphenation, or justification (ragged left). Headings use a tighter scale, and sidenotes, captions, footnotes, and blockquotes follow. A lead-in is bold rather than small caps; drop caps are not used. The editor uses the same face (a slightly smaller body size, no added tracking). PDF export uses the same stylesheet, and running heads and folios are in OpenDyslexic, natural case. An existing `onyx.openDyslexic` toggle is migrated to this typeface (and typeset reading is turned on) then removed. Code, `pre`, and `kbd` stay monospace. The setting is still local to Onyx.

### Fixed
- The History revision sheet’s Line diff (and the rendered Diff and Version tabs) fill the sheet width instead of squeezing into a narrow column on the left with highlight bands that only covered the wrapped text. The sheet itself is larger and grows with the window.
- Clicking a folder in the file tree toggles it once and it stays that way when you let go. A follow-through drag (to pin the row to Bookmarks, or ⌘-drag to move it) still starts only after the pointer moves past a short threshold; the disclosure triangle and double-click are unchanged. The second toggle was a regression: the click already fired on mouse-down, then mouse-up fired it again.
- Tags are no longer picked up from `[[Note#Heading]]` and `[[#Heading]]` links, `[text](#anchor)` link targets, URLs, or inline code, and a trailing slash (`#a/b/`) is no longer part of the tag. `#Book` and `#book` are one tag in each note's tag list. Inline tags may use Unicode letters, marks, and emoji, in the index, the editor's highlighting, and the reader.
- The Clip to Onyx Safari extension shows the Onyx icon: the app icon (the onyx crystal with its note graph) in Safari ▸ Settings ▸ Extensions, and a monochrome crystal-and-graph outline for the toolbar button that Safari tints to match light and dark toolbars (the full-color icon rendered there as a blank grey square). Both extensions also carry the app icon in their bundles, for the Extensions list and the Share menu. Icons are rendered from `Resources/AppIcon.icns` by `scripts/make-extension-icons.swift` and committed.
- Clip to Onyx has a keyboard shortcut that doesn't clash with Safari: ⌃⇧O (Control-Shift-O) clips the current page, like the toolbar button. ⇧⌘R stays Safari's Reader. Change it in Safari ▸ Settings ▸ Extensions.
- Wide Mermaid figures in the reader no longer start scrolled to the middle, clip the left edge, or draw the overflow fade across the middle of the diagram. A scrolling wrap starts at `scrollLeft` 0 so every node is reachable (a figure that fits is still centered). Edge fades and the custom scrollbar are pinned to the visible container edges and appear only on the side that still has hidden content; the 4px track sits in padding below the figure instead of covering it. Bleed stays symmetric and is limited to the room actually visible in the pane, so a sidenote shift cannot hide the figure under the sidebar. Very wide trees still scale to the bled width, but only while labels stay at least about 13px (was 11px); wider than that they scroll at that floor. The lightbox control is a real button (⤢) and stays hidden until you hover the figure.
- Wikilinks in Markdown tables and in Dataview string cells match Obsidian: a `|` inside `[[...]]` — escaped or not — does not split the cell, `\|` is the alias separator, every `[[...]]` in a cell is its own link, and a link in parentheses (`Third Eye ([[Ajna]])`) renders as a link. Dataview field text that contains wikilinks is handed to the reader's inline tokenizer. The editor is source Markdown (live preview uses the same reader).

## [0.1.17] - 2026-11-25

### Added
- Table of contents rows in a folder or selection PDF are clickable and jump to that note or folder page. In-note heading links (`[[#Heading]]` and Markdown `#heading`) do the same in a single-note export and inside a book. The PDF also gets an outline (bookmarks): the contents for a book, with each note's headings nested under it, or just the headings of a single note. External links were already kept. Heading jumps follow the laid-out positions; a heading that WebKit moved to the next page to avoid a break may land a little early or late.

## [0.1.16] - 2026-11-25

### Added
- Right-click a folder in the file tree that has no folder note for **New Index Here**, just after New Note Here. It creates `<Folder>/<Folder>.md` (the same convention Onyx already uses to hide the folder note, underline the folder row, and merge the title path), seeds a modest template (`class: Index` or the class already used by other folder notes, a title, a short placeholder, wikilinks to the folder's current notes and subfolders, and `partOf::` to the parent folder's index when there is one), and opens it in the editor. One file creation. The item is hidden once the folder has an index.
- Double-click a Mermaid diagram (or a wide, horizontally scrolling table) in the reader to open a full-window lightbox in the page: a dimmed, theme-aware backdrop, the figure fitted to the window (upscaling is allowed here), pinch or scroll to zoom, and drag to pan. Esc, a click on the backdrop, or the close button dismisses it with a short fade (~0.2s). Hovering shows a zoom-in cursor and a small expand icon. Double-click does not select label text. Single-click on a linked image still opens the attachment viewer.
- Double-click a folder circle in the atlas to zoom and pan so that circle fills the view, with a little margin (about 0.3s ease). Double-click empty background, or press Esc, to animate back to the whole vault. Esc still closes the atlas when everything is already in view. Single-click is unchanged (click a region to enter it, click a note to focus it); a double-click does not also fire the single-click.
- `make install` builds the universal (arm64 + x86_64) app and installs it to `/Applications/Onyx.app`. A running Onyx is asked to quit first (it saves; never force-killed), the new bundle is copied with `ditto` beside the old one and swapped in so the code signature is kept, and the installed version and architectures are printed. `INSTALL_DIR` / `DESTDIR` choose another location (quitting only happens for the real `/Applications`), `NO_QUIT=1` skips it, `RELAUNCH=1` reopens Onyx if it was running, and `make uninstall` removes the app. It replaces the old native-only `cp -R` target.
- `make install ONE_ARCH=1` (or `make install-native`) is the same install, but builds only this machine's architecture (`uname -m`) in release config, so it is faster than a universal binary. `ARCH=arm64` or `ARCH=x86_64` selects the slice, alone or with `ONE_ARCH=1`.
- Holding ⌘ by itself for two seconds shows the first-run shortcut hint sheet, as long as an Onyx window is key. Releasing ⌘ fades it away. Another key or a click during the hold cancels the timer, so ordinary ⌘ shortcuts never trigger it, and Esc dismisses the sheet. It does not fire during IME composition or while a modal or sheet is up, and the listed shortcuts follow the current Settings ▸ Shortcuts bindings. There is a toggle in that pane (on by default).
- Settings ▸ Reading has an OpenDyslexic option, next to the Latin Modern / ET Book (Tufte) typeface picker, off by default. When it is on, the reader and the editor use the OpenDyslexic typeface (SIL OFL, from [opendyslexic.org](https://opendyslexic.org)), with a little extra line-height and letter-spacing. It works whether typeset reading is on or off: the body font is overridden, and typeset layout such as sidenotes and line width is unchanged. Code, `pre`, and `kbd` stay monospace. The setting is local to Onyx (it is not written to the vault's `app.json`).


### Changed
- Atlas folder circles keep a clear gap between their edges, so neighbors no longer overlap or sit on top of each other. Very large folders use a compressed size scale (a soft cap on radius) so they don't swallow the canvas, and small ones such as Home keep a minimum size and stay visibly separate. Cluster titles and note-count labels sit inside their own circle. The view still fits the whole atlas after layout, and the layout is deterministic from one open to the next.
- The vault's home note is shown in semibold in the file tree. The path is the Obsidian Homepage plugin's note when that's set, otherwise `Home.md` at the vault root. If that note is a folder note, the folder row is bold, since the file itself is hidden.

### Fixed
- Wide tables in the reader no longer crush a column to a single character or wrap dates at the hyphen. Each wrapping column keeps a minimum of 8em and wraps on words (including long wikilink titles); dates, numbers, and other short unbreakable cells stay on one line. A table whose column minimums fit the measure stays in the measure and wraps prose there — it does not bleed or force a long description onto one line. Only when the minimums exceed the measure may it use a little of the pane on either side, and it then scrolls horizontally inside its own container rather than overflowing or clipping. A 4px always-visible, low-contrast scrollbar appears when (and only when) the wrap actually overflows. Booktabs rules and Latin Modern are unchanged. The editor is source Markdown, so this is the reader (and hover previews that use it).
- Mermaid diagrams get the same extra room, but only when the SVG is naturally wider than the measure: up to 8rem of the pane on each side (with a 1.2rem gutter at the edge). A figure is scaled to that bled width — and centered — as long as node labels stay at least about 11px (from the scale and Mermaid's font size, 15px by default). Only a wider figure scrolls, already shrunk to that font floor, starting centered on the diagram so a top-down fan-out is not left-aligned and clipped through the root. The 4px scrollbar is a custom always-visible track (WebKit's overlay bar is hidden globally in the reader and was not showing), and the soft fade appears only on the side that still has hidden content. The bleed is also applied in pixels so the extra room actually takes in the reader web view. The scroll container sizes to the full SVG (`useMaxWidth: false`, no `max-width` on the svg), so the right edge is reachable. Small diagrams are not upscaled or stretched.

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

[Unreleased]: https://github.com/kennethreitz/onyx/compare/v0.1.18...HEAD
[0.1.18]: https://github.com/kennethreitz/onyx/compare/v0.1.17...v0.1.18
[0.1.17]: https://github.com/kennethreitz/onyx/compare/v0.1.16...v0.1.17
[0.1.16]: https://github.com/kennethreitz/onyx/compare/v0.1.15...v0.1.16
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
