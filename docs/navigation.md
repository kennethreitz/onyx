# Getting around

<kbd>⌘O</kbd> is the quick switcher. It ranks exact matches first, then prefix, initials, substring, and fuzzy; it ignores accents, matches folders and aliases (“hebrew aleph”, “hl”, “resume” → Résumé), and highlights what matched. <kbd>⌘↩</kbd> opens in a split; <kbd>⇧↩</kbd> creates a note. <kbd>⌘P</kbd> (or <kbd>⇧⌘P</kbd>) is every command.

<kbd>⌘D</kbd> splits side by side and <kbd>⇧⌘D</kbd> stacks, up to four panes. The axis, divider positions, and the note in each pane are remembered per vault and come back when you reopen it.

The title path whispers the folder above the page; click a segment to reveal it in the sidebar and open its folder note. <kbd>⌘[</kbd> and <kbd>⌘]</kbd> go back and forward per pane (mouse buttons and swipe too). Daily notes follow the vault’s own `.obsidian/daily-notes.json` folder; <kbd>⌘T</kbd> or <kbd>⌘\</kbd> opens today, <kbd>⌥⌘[</kbd> and <kbd>⌥⌘]</kbd> step through them. <kbd>⇧⌘H</kbd> opens the homepage from the Obsidian Homepage plugin, or `Home.md`.

<kbd>⇧⌘F</kbd> searches the vault. <kbd>⌘F</kbd> finds in the current note (editor or reader); <kbd>⌥⌘F</kbd> is find and replace in the editor.

<p align="center">
  <img src="title-path.png" alt="Title path revealing a folder in the sidebar" width="85%">
</p>

## Files and the sidebar

<kbd>⌘K</kbd> shows or hides the file list. The sidebar is always docked — it does not float or auto-hide. It can be dragged as narrow as 140pt, the inspector as narrow as 150pt; double-click the edge to reset. Tabs cover files, vault search (<kbd>⇧⌘F</kbd>), recent files, bookmarks, tags, and source control.

Sort the sidebar by name (natural order, so “Note 2” precedes “Note 10”), modified, or created, ascending or descending, with folders on top if you want. The choice is remembered per vault. Right-click a folder to override the sort for just that folder, or to create a new note or folder there. Right-click the empty area below the file list for a new note or folder in the vault root. <kbd>⇧⌘N</kbd> or New Folder in the command palette does the same for the selected folder.

<kbd>⌘N</kbd>, the compose button at the bottom of the sidebar, and Command Palette ▸ New note create an Untitled note in the folder selected in the file tree, or next to the open note if you haven’t selected a folder (or at the vault root). Type a heading and save (<kbd>⌘S</kbd>, or leave the note): the file is renamed from that title and shows up in the sidebar under the real name. Autosave already wrote the bytes, so nothing is lost if you keep typing. Clicking an unresolved <code>[[wikilink]]</code> creates the note at the vault root, named after the link; <kbd>⇧↩</kbd> in the quick switcher creates one with the name you typed. Daily notes still follow the vault’s daily-notes folder.

Shift-click selects a range; <kbd>⌘</kbd>-click adds or removes one file without changing the open note. Right-click the selection to move, reveal in Finder, or delete them all (one confirmation, one git commit). <kbd>Esc</kbd> clears the selection; after clicking in the sidebar, <kbd>⌘⌫</kbd> deletes it.

Rename or Move to… (<kbd>⇧⌘M</kbd>) from the File menu or a right-click. Wikilinks — including path links, aliases, headings, embeds, and bare `partOf::` / `related::` names — are rewritten to follow, and so are standard Markdown links and embeds (`[text](folder/note.md)`, `![](image.png)`). The note stays open. Delete sends files to the Trash after a confirm. “Open in Obsidian” is on the same menu, for a note you want to check in the official app.

See also [keyboard shortcuts](shortcuts.md) and [graph and atlas](graph.md).
