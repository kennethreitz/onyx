# Onyx — design notes

Onyx edits like iA Writer and reads like a typeset paper (the Reitz LaTeX theme, native).
The page is the interface; everything else is summoned, and Esc puts it away.

## Chrome

- **Title path** (always visible, quiet): `Knowledge / Hebrew Letters / Aleph`, or the `partOf` ancestry
  `Medication › SSRI › Sertraline` when the note has a parent (`Ancestry.chain`: first parent at each step, cycle-safe,
  12 deep; other direct parents behind a faint +N menu), so folders and hierarchy never repeat each other. A frontmatter
  `class:` is a hairline tag after the name.
  Folder segments are links (hover underline, pointer cursor): a click docks the Files
  sidebar, expands down to that folder, selects and scrolls to it, and opens its folder
  note (`Folder/Folder.md`, the folder-notes convention) when one exists. The last segment
  copies `[[Note]]`.
- **Footer** (auto-dims to ~40%, full on hover): files, switcher, graph, three-pane,
  read/edit, focus mode · word count · inspector. Hovering reveals character and
  backlink counts in width already reserved, so the Read Aloud pause and stop
  controls don't slide under the pointer. The Reading/Paused chip keeps a fixed
  width; footer buttons are 22pt.
- **Sidebar** is always docked. First launch shows it; ⌘K shows or hides it. Visibility is
  remembered (`onyx.sidebarOpen`). There is no pin button, floating overlay, or left-edge peek.
- **Resizable panels**: drag the inner edge of the sidebar or inspector (a hairline that shows
  a small grip and a resize cursor on hover). Sidebar 140–560pt (default 270), inspector
  150–600pt (default 300); widths persist (`onyx.sidebarWidth`, `onyx.inspectorWidth`), and a
  double-click on the edge resets to the default. Tab icons compress to fit narrow panels.
- **Scrollbars**: thin and quiet everywhere. Editor and panels use `ThinScroller` (a 3pt
  rounded thumb, 5pt under the pointer, no track, ~20% ink in light and ~26% white in dark)
  that fades in while scrolling or on hover and out after ~0.9s idle; neither reserves a
  gutter: `ThinScrollView` lays the text under its scroller, and the reader hides WebKit's
  scrollbar and draws a floating 3px thumb (draggable) from reader.js, so split panes meet at
  a bare hairline. `ONYX_SCROLL_TEST=<seconds>` scrolls everything in small steps that long
  after launch, for screenshots.
- **Inspector** (outline, backlinks, properties): ⌘I or the footer button only, docked,
  remembered across launches (`onyx.inspectorOpen`). There is deliberately no right-edge
  hover: a pointer parked at the window's right edge kept re-summoning it ("stuck").
  ⌘I is caught ahead of the editor so it works while typing. Esc puts it away too.
- **Title fade**: a paper-colored gradient sits behind the title path, so body text scrolls
  up into a soft fade instead of colliding with the path.
- **Split panes**: a flat row (⌘D) or column (⇧⌘D) of up to four panes; a new split sets
  the axis for the whole group. The hairline between panes is draggable (resize cursor on
  hover, a small grip while dragging, 240pt minimum; when the window is tighter, panes
  shrink together). Double-click a divider to equalize. Ratios, axis, and the note
  (or docked graph) in each pane are remembered per vault and restored on the next
  launch, clamped to a 240pt minimum for the current window. Screenshot and test
  hooks never write this. Swap model: the focused pane drives the live
  editor/reader state; unfocused panes keep their own path, text and mode and render
  read-only (dimmed a touch) until clicked or reached with ⌃⇥. Two panes on the same
  note show the live text in both.
- **File views** (`FileView.swift`, `AudioPlayer.swift`): attachments take the pane like a note does. A 30pt header
  sits under the title path with kind · size · details in small muted type, then the type's controls and
  `FooterButton`s for linked notes, Open in Default App, and Reveal in Finder. Under it is the viewer: an NSScrollView
  image view (fit ≤ 100%), PDFKit on `paperAlt`, AVKit, or the audio player, which is serif title, a 72pt
  waveform (ink played, faint ahead, a slate playhead), and round ink-wash transport buttons. Reader audio embeds
  echo it as one line in an 8px card.
- **Focus mode** ⌃⌘F: pure text; the same keys restore exactly what was showing.

## Scales

Chrome (not the page) draws from a few shared scales in `Theme.swift`. New UI should pick from these
rather than invent numbers; the page itself is typeset by the reader and editor at the user's size.

- **Spacing** (`Space`): 2 · 4 · 6 · 8 · 12 · 16 · 24. Panel rows inset 12–14pt; list washes inset 5–6pt.
- **Radii** (`Radius`): 4 small (chips, keycaps, ≤22pt icon buttons) · 6 control (rows, tabs, fields) ·
  8 card (popovers, find bar, completion) · 12 panel (`panelChrome`).
- **Type** (`TypeScale`, SF points): 9.5 label (UPPERCASE, tracked 0.8) · 10.5 caption · 11.5 small ·
  12.5 body · 13.5 palette row. Serif (Latin Modern) is for titles, empty states and the page.
- **Color**: paper, ink, muted, faint, hairline, and slate (`cursorBlue`) for focus and the current
  note. `warn` (burnt amber) and `danger` (madder red) are the only alarm tints; no system orange/red.
  `Theme.faint` stays the editor's syntax gray; `Color.faint` (`faintLabel`) is a shade darker in light
  mode so small chrome labels clear ~4:1 on paper.
- **States**: hover is an ink wash at ~4% (rows) or 6% (icon buttons); selection ~7–8%; focus is a
  slate ring. Shortcuts render as `Keycaps` (one cap per modifier, two spaces between chords).
- **Empty states** (`QuietEmpty`): one italic serif line in muted, plus an optional caption hint.
- **Motion** (`Motion`): `hover` 0.12s, `quick` 0.15s, `fade` 0.18s, `overlay` spring 0.26/0.9,
  `layout` spring 0.3/0.88. With Reduce Motion on, springs become ~0.12s dissolves and
  `Motion.slide` / `Motion.pop` transitions become plain fades; the reader honors
  `prefers-reduced-motion` the same way.

## Keys

| Key | Action |
| --- | --- |
| ⌘O | Quick switcher (find or create) |
| ⌘P, ⇧⌘P | Command palette (⇧⌘P for VS Code hands) |
| ⌘K | Show or hide the sidebar (always docked; from another tab, switches to Files) |
| ⇧⌘F | Search the vault |
| ⌘I | Inspector |
| ⌘G / ⇧⌘G | Focus graph / Atlas |
| ⌘E, ⌘↩ | Read ⇄ edit; ⌘↩ also saves immediately |
| ⌘T, ⌘\\ | Today's daily note (⌘D is no longer bound to it) |
| ⌘D / ⇧⌘D | Split side by side / stacked |
| ⌘W | Close the focused pane; with one pane, close the window |
| ⌃⇥ / ⌃⇧⇥ | Next / previous pane (click also focuses) |
| ⌘[ ⌘] | Back / forward through this pane's history (also mouse buttons 4/5, swipe) |
| ⌥⌘[ ⌥⌘] | Previous / next daily note |
| ⌘⌫ | Delete note: confirm, then the Trash; panes and history move on (replaces the editor's delete-to-line-start) |
| ⌘N | New note (in the selected folder, or next to the open note). ⌘S names a still-Untitled file from its first heading |
| ⇧⌘N | New folder |
| ⌃⌘F | Focus mode |
| Esc | Put away the topmost layer (overlay → floating panel → inspector → focus mode) |

## Canvas

- **Obsidian canvases** (`.canvas`, JSON Canvas 1.0) open from the sidebar, ⌘O, links,
  backlinks and the graph into the pane, in place of the reader/editor (⌘E does nothing there).
- **Drawing**: paper cards with hairline borders; Obsidian colors 1–6 (red, orange, yellow,
  green, cyan, purple, muted) and hex colors become a tinted border and a faint wash. Text
  cards are typeset by the reader's Markdown (links, embeds, highlights); file cards show the
  note (or its `#heading` subpath), an image, a PDF, or a quiet "not found". Link cards show
  the host and URL (no live web page). Groups are tinted regions with their label above.
  Edges are curves leaving each side along its normal, with arrows (`toEnd` defaults to
  arrow), labels and colors; missing sides are picked from the cards' positions.
- **Moving around**: two-finger scroll pans, pinch zooms (⌘-scroll for a mouse wheel), drag
  on empty space pans, ⇧1 zooms to fit (⇧2 to the selection), + − ⤢ sit faint at bottom
  right. A canvas opens fitted. Scrolling inside a selected card scrolls the card.
- **Editing**: click selects (⇧ adds), ⇧-drag on empty space draws a selection box; drag
  moves (a group carries the cards inside it); drag any edge or corner to resize; double-click
  empty space for a new card, a text card (or ↩) to type in it (Esc or ⌘↩ to finish), a file
  card to open it, a group's label to rename it, an edge to label it. Drag from the dots on a
  card's sides to connect; drop on empty space to make a connected card. ⌫ deletes, arrows
  nudge (⇧ for more), ⌘Z / ⇧⌘Z undo and redo. Right-click: add card, add note… (the ⌘O
  matcher), group, colors, arrows, delete.
- **Saving**: the page sends `JSON.stringify(doc)`; Swift rewrites it in Obsidian's layout
  (tab-indented, one node or edge per line, no trailing newline) through the usual
  conflict-safe save, so ids, key order and unknown fields survive and Obsidian reads it
  unchanged. A canvas that can't be parsed is shown as such and never written.
- **Links**: file cards and `[[links]]` in text cards count as the canvas linking to those
  notes (backlinks, graph). Moving or renaming a note rewrites file cards pointing at it.

## Graph

- **Focus graph** (⌘G): an overlay on the current pane (or the solo page) only — never
  over the sidebar, inspector, or other split panes — with a short fade and scale-in,
  sitting on top of the note underneath. The note at the center, direct links on the
  first ring (out filled, in hollow), second hop faint beyond. Click travels with an
  animated re-center and a breadcrumb trail (⌫ back); double-click or ↩ opens that
  note in this pane and dismisses the overlay. Esc closes it and returns focus to the
  note underneath.
- **Atlas** (⇧⌘G): the same overlay mechanism, in semantic-zoom form. Folders (or top tags)
  are regions sized by note count, with edges weighted by cross-links, opening into
  sub-regions and then notes as you zoom. Clicking a note in the atlas focuses it;
  double-click or ↩ opens and dismisses, same as the focus graph.
- **Region colors**: each region's name hashes into a muted, hue-ordered palette
  (terracotta, ochre, olive, sage, teal, violet, plum, rose) with light and dark variants.
  Regions on the map get collision-free hues (largest first, ≥2 hue steps apart when it can).
  Slate blue is reserved for the current note. Focus-graph dots borrow their region's hue.
- **Labels**: region titles are large bold serif at the centroid, with a paper halo and a
  faint tinted outline, fading and shrinking as sub-regions take over. Every label is
  collision-checked and haloed.
- **Orphans** are hidden by default. Filter → Show orphans draws them as faint satellites
  just outside their region's rim (no list).
- The canvas is static unless a transition is running; the TimelineView only exists while
  animating, so camera changes can't be drawn stale.

## Keeping your place

Onyx tracks "where you are" as a **source line**, not a pixel offset: the line sitting just
under the title (48pt down), with a fraction for how far into a soft-wrapped paragraph or a
multi-line block that point is.

- The reader renders each top-level markdown block with `data-line` / `data-lines` (0-based
  line in the file, frontmatter included; dataview fences keep their line count when replaced).
  The editor maps line ↔ glyph rect through TextKit.
- Both views report their top line as you scroll (into unobserved workspace state, so scrolling
  never re-renders SwiftUI), and a freshly created view opens at it. That is what keeps
  **⌘↩ / ⌘E** on the same passage in both directions, and makes **⌘D / ⇧⌘D** open the new pane
  exactly where the source pane is.
- Resizes (splitting, sidebars, the window) re-apply the last chosen line, so the source pane
  never jumps when it gets narrower or shorter. The editor also refuses AppKit's
  "recenter the caret on resize" scroll.
- Positions inside the frontmatter map to the top of the reader (it shows properties there).

## Shortcut audit hooks

Debug-only environment switches used to check the "Onyx, in a few keys" sheet against reality:
`ONYX_DUMP_MENUS=1` prints every menu key equivalent (to catch double bindings),
`ONYX_KEY_SELFTEST=1` offers each sheet shortcut to the view hierarchy with the editor / reader
as first responder (to catch a view swallowing it before the menu), and `ONYX_DEBUG_KEYS=1`
logs workspace state after each key press.

## Quick switcher (⌘O)

One matcher (`OnyxCore/QuickMatch.swift`) serves ⌘O, the command palette and `[[` completion.
`key::` lines use the same popup through `FieldCompletion`: `word:` at line start (text after the caret blank, outside
frontmatter) offers known keys by prefix (`VaultSnapshot.fieldKeys()`, most used first); `key:: ` on a link-valued key
(`linkValuedKinds()`) offers notes for the current comma segment and inserts `[[Note]]`. ↩ with nothing highlighted keeps
its normal meaning there; Esc dismisses for that line.

- **Tiers, per query token:** exact > prefix (or a whole later word, so "20" finds 2026-11-20) >
  word boundary / initials ("hl" → Hebrew Letters, "heblet", "js" → JavaScript via camelCase) >
  contiguous substring > scattered subsequence. Scattered matches must land two thirds of their
  letters on word starts or runs, so letters sprinkled across a long title don't count.
- **Folding:** case, diacritics and width are ignored ("resume" → Résumé, "bahai" → Bahá'í),
  with a 1:1 character map so highlights line up with the original text.
- **Multi-token:** split on spaces and "/"; every token must match the title, an alias, or the
  folder path (real words only, no scattering), in any order. The whole query is also tried
  as one title, so "onyx plan" prefers *Onyx Plan* over notes that merely contain both words.
- **Aliases** from frontmatter match a little below the title and show as a badge.
- **Recency:** recently opened (up to +250) and recently edited (up to +100) nudge order within
  a tier, never across one; daily-note names count by their own date, newest first. An empty
  query lists recent notes.
- **Speed:** keys are folded once per vault snapshot (`QuickIndex`); a query is about 1ms over
  5,000 notes in a release build.
- **Keys:** ↑/↓ move, ↩ opens, ⌘↩ opens in a new split, ⇧↩ creates a note with the typed name
  (a `Folder/Name` query creates it in that folder). The Create row is shown whenever no note
  has exactly that name, and is preselected when nothing matches. Esc closes.

## Back and forward

Each pane keeps its own history (cap 200) of places: notes and the graph view (focus or atlas).
Opening a note pushes an entry; going somewhere new from the middle of the history drops the
forward entries, as in a browser. Each note entry remembers its source line at the top of the view and its mode, so going back
lands where you were reading or writing, in read or edit mode. Closing the graph (Esc, ⌘G) counts as a step back, so ⌘] reopens it.
Notes deleted since are skipped. Splitting copies the history into both panes.

Triggers: ⌘[ / ⌘] (Go menu, also caught by the window's key monitor so the editor and web
view can't claim them), mouse buttons 4/5, three-finger "swipe between pages", and a two-finger
horizontal swipe when the system setting allows it (outside overlays). The title bar shows
‹ before the path and › after the title, dimmed when there's nowhere to go. The graph header has both chevrons side by side.

## Deleting and the file menu

Right-click any note, file or folder (tree, recent, bookmarks, search): Open, Open in Split,
New Note Here (folders), Rename…, Move to…, Reveal in Finder, Open in Obsidian (`obsidian://open?vault=…&file=…`),
Delete…. Delete Note… is also in the File menu and the palette (⌘⌫). Delete always confirms and
always goes to the Trash (`NSWorkspace.recycle`), so it can be undone from Finder. A new Untitled
note is named from its first heading (or first line) when you save or leave it. Afterwards the
note leaves every pane's history (with collapsed neighbours, so A ✕ A doesn't leave a double step),
any pane showing it steps back (or closes, if it has nowhere to go) and the recent list forgets it.
`vaultMutated` is the hook git auto-commit uses for deletes, renames and moves.

Sidebar multi-select works like Finder: click selects one row and opens it; ⇧-click selects the
visible rows between the anchor and the click; ⌘-click toggles a row without changing the open note
(the anchor moves to it). Selected rows share one highlight; during a multi-selection the open note,
if not selected, keeps only a faint one. Right-clicking a selected row gives a selection menu: Move N
Items to…, Reveal N Items in Finder, Delete N Items… (Open, Rename and Open in Obsidian are shown
disabled). ⌘⌫ deletes the selection when the last click was in the tree; Esc clears it. A folder
in the selection swallows its selected descendants (`TreeSelection.roots`). Batch moves rewrite
links per item but report one vault change, and batch deletes are one Trash call, so git sync makes
one commit per batch ("Move 3 items: a, b, c → Folder", "Delete a and b").

## Git, continuously

When the vault folder is itself a git repository (its own `.git`) and git is installed, Onyx
keeps it committed and in sync with no buttons to press (GitSync):

- **Commit** about a second after a save settles (so ~2s after you stop typing), and at once
  on delete / rename / move, switching notes, leaving the app and quit. Messages name the notes:
  "Edit Mercury", "Add 2026-11-20; edit Mercury", "Rename A → B", "Move A → Archive",
  "Delete Old Note", "Edit 7 notes: A, B, C, …" (file list in the body). Commits use the repo's
  own identity (Onyx <onyx@host> only if none is configured) and `--no-verify`.
- **Sync** after every commit, on launch, when the app comes forward and every 30s:
  fetch → `rebase @{u}` (autostash) → push, going round again if the push is rejected because
  the remote moved. No upstream yet: `push -u` the current branch. No remote: local only.
- **Never** force-push, never amend or rewrite pushed history, never drop work.
- **Conflicts**: during the rebase, each conflicted file keeps the local version at its path
  and the remote version is written beside it as `Note (conflict YYYY-MM-DD HHMM).md`; both are
  committed and pushed. Edited-vs-deleted keeps the edit. Anything unexpected → `rebase --abort`,
  which leaves the local commits exactly as they were. A rebase or merge you started by hand is
  left alone (Onyx waits).
- **Offline**: network errors retry with backoff (5s, 10s, 20s … 5 min). Prompts are disabled
  (`GIT_TERMINAL_PROMPT=0`, ssh BatchMode) so a missing credential fails instead of hanging.
- **Indicator**: a tiny glyph in the footer: ✓ synced, ↻ syncing, ↑ pushing, wifi-slash offline,
  dashed circle local only, ⚠ conflict (until the copies are gone) or needs attention. Hover for
  details; click for Source Control, which lists conflict copies.

`ONYX_NO_GIT=1` turns it off; `ONYX_GIT_INTERVAL=<s>` changes the poll (tests use 5 or 600).
Tested only on /tmp repos: a bare remote plus two clones (Onyx on one, the git CLI as the other
machine) covering launch pull, edit → commit → push, remote edits arriving, delete commits, a
same-line conflict (kept both), and offline → backoff → recovery.

## Rename and Move to…

Rename… (File menu, palette, right-click, or Return on a focused file-tree row) edits the
row name in place, Finder-style: the stem is selected (without `.md`), ↩ commits, Esc or an
empty or unchanged name cancels, clicking away commits, and a collision or illegal character
keeps the edit and shows an error. If the sidebar is hidden, the old name prompt is used.
⌘-drag a row (or a multi-selection) onto a folder, a file in that folder, or the empty area at the bottom of the tree (the vault root) to move it; the drop target highlights and a collapsed folder expands after a short hover. A folder cannot land inside itself or a descendant, and a name collision is refused with an error. Plain drag does not move files. Move to… (⇧⌘M, palette, right-click) opens a folder picker on the ⌘O matcher: type to filter,
↩ moves, ⇧↩ or the Create row makes the typed folder (nested paths fine) and moves there.
Folders get both. Links across the vault follow: path links (`[[Folder/Note]]`, with or without
`.md`) are rewritten to the new path, name links (`[[Note]]`) only when the name changed (or
to a path if the new name would be ambiguous); `#heading`, `|alias` and `![[embeds]]` are kept.
The note stays open in its panes, history, recent list and bookmarks, and git commits the
move at once ("Move Venus → Archive", "Rename Mercury → Hermes"). Markdown-style
`[text](path.md)` links are not rewritten yet.

## Inline fields and relationships

Dataview-style fields are parsed by `InlineFields`: whole-line `key:: value` (also as a list item),
mid-line `[key:: value]` / `(key:: value)`, and frontmatter properties whose values are links.
Fields inside code spans, fences and `%%comments%%` are ignored. `partOf`, `related`, `relatesTo`
and `correspondsTo` are relation keys: their values may be bare note names (`partOf:: Knowledge`),
`[[links]]`, quoted YAML strings or comma-separated lists, and every value resolves like a wikilink.
Other keys turn only explicit `[[links]]` into links.

Field links are ordinary `WikiLink`s tagged with `fieldKey` (bare values carry `isBare` and the exact
source range), so they count as links and backlinks, show up as unresolved links (clicking creates the note), and
are rewritten by rename/move like any wikilink, bare names included. `VaultSnapshot.relationsOut/In` index them by
kind: `parents(of:)`, `parts(of:)`, `siblings(of:)` and the symmetric `related(to:)`.

The reader renders a field as a small monospace key plus link chips; the editor tints `key::`.
The inspector's Links tab (`RelationshipsSection`) lists Part of, Parts and Related above the backlinks. Parts is a tree from
`Ancestry.partsTree` (cycle-safe: a note that is its own ancestor in a branch shows once more as ↻; depth 6), Siblings fold
under a count, and `VaultSnapshot.fieldRelations(of:)` groups every other link-valued key both ways (`treats`, `treats · from`). In the focus graph, `partOf`
spokes are firmer muted stems with a small open chevron halfway along, pointing part → parent; Filter ▸ Hierarchy only
(`onyx.graph.hierarchyOnly`) lays out `FocusLayout.layout(hierarchy:)` from `GraphIndex.partOf`/`parts` alone. Related spokes are blue dotted lines. Hovering any resolved reader link or an inspector
relation for 400 ms opens a card: the note's parents above, parts below (two staggered lanes, "+N more"),
siblings faint at the side, related to the right, or its plain links when it has no fields. Click a node
to open it, the card background for the note itself; leaving the link or the card closes it.


## Sidebar sorting

The sidebar header's ↑↓ menu sets the vault order: Name (natural, so "Note 2" precedes "Note 10"),
Modified or Created, ascending or descending, and Folders on Top (default on). A folder's right-click
"Sort This Folder By" overrides it for that folder's children ("Use Vault Order" clears it).
Folders sort by their newest modification / oldest creation inside. Saved per vault
(`onyx.<vault>.treeSort`). Overrides follow folder renames. ⇧-click ranges use the displayed order
(`Workspace.treeChildren` feeds both the view and `visibleTreePaths`).

## Title-bar graph button

Right of the forward chevron: click opens the focus graph for the current note (⌘G), and click
again (or ⌘G again) closes it and returns to the note; ⇧-click or the right-click menu opens the
atlas (⇧⌘G), and does the same toggle when the atlas is already showing. The button is marked
while the overlay is open. Hovering it for 400 ms shows the current note's graph card. The
footer's graph icon remains, and toggles the same way.


## Graph pane and startup atlas

⌘G / ⇧⌘G (and the title-bar graph button) open the graph as an overlay that covers only the
focused pane, and close it if that same graph is already showing (⌘G, or a regular click, also
closes the atlas). In a split, the other panes stay visible; Esc or the overlay's close button
puts the graph away and focuses the note that was under it. The overlay is pinned to the
pane it was opened from, so focusing another pane doesn't move it.

The graph can also stay open as a pane beside notes: the overlay's "keep open as a pane" button, ⌥⌘G, or
`openGraphPane`. A graph pane is a `Pane` with `isGraph`; it never takes the editor's focus (focus
cycling and clicks skip it), its focus graph follows the note you're on, it zooms only under the
pointer, and keys stay with the editor. ⌘W next to a single note closes the graph pane first.
"Open the atlas on startup" (Settings ▸ Graph, per vault) shows the atlas as that pane overlay over
the home note at launch; it defaults to on when the vault's Obsidian Homepage plugin opens "Graph view"
on startup (~/Notes does).


## Backlinks in the reading view

Below every note (not Kanban boards) the reader lists linked mentions, grouped by note with up to
three context lines each. Field links count, wikilinks read as their alias, and table rows are flattened. Clicking
a context opens the note at that line. "Unlinked mentions" loads on demand when expanded.
Both sections collapse, and the open state is remembered.

## Hover page preview

Hovering a resolved link in the reader (or holding ⌘ over a `[[link]]` in the editor) opens a card after 400 ms.
The card shows the target note rendered compactly and scrollable, or its local graph. A toggle in the card header
switches between the two, and links remember the last choice (page by default). The title-bar graph button and the
inspector's relation rows always open on the graph. `[[Note#Heading]]` previews just that section. Inside the preview,
links navigate (and close the card) but do not nest further previews. Tasks are read-only there.

## Find in note (⌘F)

There is one find bar for the editor and the reader. It does a literal match, ignoring case by default (`Aa` toggles
that). It shows "n of N", highlights every match and the current one more brightly, and scrolls to the current match.
In the reader it searches the rendered text, skips the backlinks section, and opens a collapsed callout or details block
when a match is inside one. **⌘G conflict:** ⌘G stays Focus graph, except while the find bar is open, when ⌘G/⇧⌘G go
to the next/previous match (the Mac convention). ↩/⇧↩ in the field do the same, so the graph is always one Esc away. ⌥⌘F
opens the replace row (editor only). ↩ there replaces the current match, and "All" replaces every match in one undo step.
Switching edit and read, or changing notes, keeps the bar open and recounts.

## Editable Kanban

Boards in the obsidian-kanban format (`kanban-plugin` frontmatter) can be edited in the reader. Drag a card within a lane or
to another lane (a line marks where it will drop). Use the checkbox to check it off, double-click to edit (↩ saves, ⇧↩ adds a
new line, Esc cancels), use "+ Add a card" to add one, and ↓ to archive one. `KanbanDoc` (OnyxCore) parses the file into line
ranges and splices only the lines that change. Frontmatter, the `%% kanban:settings %%` block, spacing and card markup stay
as they were. A board that is opened but not edited is never written. Lanes keep the plugin's layout (`## Lane`, a blank line, the cards,
two blank lines). Archived cards go under `***` / `## Archive` ahead of the settings block, the way the plugin writes them.
Only the focused pane's board can be edited. Split and preview copies are read-only. `ONYX_KANBAN_FILE=/tmp/…` runs the real-board
round-trip test against a copy.
Lanes collapse with the ‹ in the header. A collapsed lane is a thin strip with the title rotated and the card count. Click it to expand,
or drop a card on it to add the card to the end of that lane. Right-clicking a header or strip offers Collapse/Expand, "Collapse all except this"
and "Expand all". The state is the plugin's own `list-collapse` array (one boolean per lane index) in the
`%% kanban:settings` JSON, so it round-trips with Obsidian. Only that array is rewritten. If the key is missing, it is added; if the
board has no settings block, one is added.

## Rename and move: Markdown links too

Besides wikilinks, rename and move rewrite standard Markdown links and embeds (`[t](x.md)`, `![](img.png)`), keeping
each link's style:
- relative (`../`, `./`), vault-absolute (`Folder/x.md`, `/Folder/x.md`) or bare name;
- `%20`-encoded, raw or `<angle>`;
- the `#heading` anchor and title.

The relative links inside a moved note are re-expressed from its new folder. Moving or renaming an attachment (or a folder
of them) updates both `![[path]]` wikilinks and Markdown embeds. Links are resolved the way Obsidian does: relative to the
note, then from the vault root, then by name. External URLs, same-note `#anchors`, code and comments are left alone. All
edits and the move land in one git commit. The logic is in `MarkdownLinks` (OnyxCore), with tests in MarkdownLinksTests.

`LinkUpdater.plan` (OnyxCore) works out every edit a move needs before anything is written: wikilinks, embeds,
frontmatter and field links, Markdown links (through `MarkdownLinks`), and canvas file cards. A bare-name link is checked
against a small post-move name index (`PostIndex`, the same rules as `VaultSnapshot.resolve`), so it stays a name only while
it still resolves to the same file, including when the source note itself moves or another file with that name moves in.
`Workspace.relocate` asks first unless `alwaysUpdateLinks` is true (`ONYX_UPDATE_LINKS=update|skip` answers for scripted
runs), then writes the plan, moves the file, and commits once. Tests are in LinkUpdaterTests.


## Updates from GitHub Releases

On launch (after a short delay) and every six hours, and from **Onyx ▸ Check for Updates…**, the app asks
`https://api.github.com/repos/kennethreitz/onyx/releases/latest` for a later semver tag than
`CFBundleShortVersionString`. A non-modal prompt shows the release notes and **Install and Relaunch**,
**Later**, or **Skip This Version**. The notes are formatted (section labels, nested lists, bold, italic,
inline code, and links), not raw Markdown. Relative links such as `[docs](docs/obsidian-settings.md)`
open the file at that tag on GitHub (`https://github.com/kennethreitz/onyx/blob/v<version>/…`).
Skip is remembered for automatic checks only; a manual check still
offers that version. Settings ▸ Updates can turn automatic checks off (`onyx.updates.automatic`; default on).

Install downloads the `Onyx-<ver>-macOS.zip` asset, unpacks it with `ditto`, checks that the bundle id is
`org.kennethreitz.onyx` and that its short version is newer, strips `com.apple.quarantine`, replaces the
running `.app` atomically (the outgoing bundle is moved to the Trash), and relaunches through a detached
`/bin/sh` helper that waits for this process to exit. Unpackaged `swift run` builds are left alone.
`ONYX_UPDATE_API_URL`, `ONYX_UPDATE_VERSION`, and `ONYX_UPDATE_APP` override the endpoint, current version,
and destination for tests; `ONYX_UPDATE_DISABLE` and the screenshot/self-test hooks skip automatic checks.
If the app is translocated (opened from Downloads), the install is refused until it is moved to Applications
and opened from there. Logic lives in `Updater` and `ReleaseNotes` (OnyxCore), with tests against a fake local release in `/tmp`.
