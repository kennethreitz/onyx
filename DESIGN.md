# Onyx — design notes

Onyx edits like iA Writer and reads like a typeset paper (the Reitz LaTeX theme, native).
The page is the interface; everything else is summoned, and Esc puts it away.

## Chrome

- **Title path** (always visible, quiet): `Knowledge / Hebrew Letters / Aleph`.
  Folder segments are links (hover underline, pointer cursor): a click docks the Files
  sidebar, expands down to that folder, selects and scrolls to it, and opens its folder
  note (`Folder/Folder.md`, the folder-notes convention) when one exists. The last segment
  copies `[[Note]]`.
- **Footer** (auto-dims to ~40%, full on hover): files, switcher, graph, three-pane,
  read/edit, focus mode · word count · inspector.
- **Sidebar** remembers whether it was docked; first launch shows it. Left-edge hover peeks
  it, and won't re-peek until the pointer leaves the edge after a hide.
- **Inspector** (outline, backlinks, properties): ⌘I or the footer button only, docked,
  remembered across launches (`onyx.inspectorOpen`). There is deliberately no right-edge
  hover: a pointer parked at the window's right edge kept re-summoning it ("stuck").
  ⌘I is caught ahead of the editor so it works while typing. Esc puts it away too.
- **Focus mode** ⌃⌘F: pure text; the same keys restore exactly what was showing.

## Keys

| Key | Action |
| --- | --- |
| ⌘O | Quick switcher (find or create) |
| ⌘P, ⇧⌘P | Command palette (⇧⌘P for VS Code hands) |
| ⌘K | Files sidebar |
| ⇧⌘F | Search the vault |
| ⌘I | Inspector |
| ⌘G / ⇧⌘G | Focus graph / Atlas |
| ⌘E, ⌘↩ | Read ⇄ edit; ⌘↩ also saves immediately |
| ⌘T, ⌘\\, ⌘D | Today's daily note |
| ⌘[ ⌘] | Previous / next daily note (history back / forward elsewhere) |
| ⌘N | New note |
| ⌃⌘F | Focus mode |
| Esc | Put away the topmost layer (overlay → floating panel → inspector → focus mode) |

## Graph

- **Focus graph** (⌘G): the note at the center, direct links on the first ring (out filled,
  in hollow), second hop faint beyond. Click travels with an animated re-center and a
  breadcrumb trail (⌫ back); double-click or ↩ opens.
- **Atlas** (⇧⌘G): semantic zoom. Folders (or top tags) are regions sized by note count,
  with edges weighted by cross-links, opening into sub-regions and then notes as you zoom.
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
