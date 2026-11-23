# Keyboard shortcuts

| Key | Does |
| --- | --- |
| <kbd>⌘O</kbd> | Quick switcher: find or create a note (<kbd>⌘↩</kbd> opens in a split, <kbd>⇧↩</kbd> creates) |
| <kbd>⌘P</kbd> · <kbd>⇧⌘P</kbd> | Command palette |
| <kbd>⇧⌘O</kbd> | Open vault… |
| <kbd>⌘K</kbd> | Show or hide the sidebar (always docked; opens on Files) |
| <kbd>⇧⌘F</kbd> | Search the vault |
| <kbd>⌘I</kbd> | Inspector: outline, backlinks, properties |
| <kbd>⌥⌘1</kbd> · <kbd>⌥⌘2</kbd> · <kbd>⌥⌘3</kbd> | Outline · backlinks · properties |
| <kbd>⌘G</kbd> · <kbd>⇧⌘G</kbd> · <kbd>⌥⌘G</kbd> | Focus graph overlay · atlas overlay · graph in a pane. <kbd>⌘G</kbd> or the title-bar button again closes the overlay; <kbd>⇧⌘G</kbd> closes the atlas if it is already showing. <kbd>Esc</kbd> also closes the overlay |
| <kbd>⌘F</kbd> · <kbd>⌥⌘F</kbd> | Find in the note (editor or reader) · find and replace (editor). While the bar is open, <kbd>⌘G</kbd>/<kbd>⇧⌘G</kbd> or <kbd>↩</kbd>/<kbd>⇧↩</kbd> go to the next/previous match, and <kbd>Esc</kbd> closes it |
| <kbd>⌘↩</kbd> · <kbd>⌘E</kbd> | Read ⇄ edit, and save |
| <kbd>⌘T</kbd> · <kbd>⌘\\</kbd> | Today’s daily note |
| <kbd>⌥⌘[</kbd> · <kbd>⌥⌘]</kbd> | Previous / next daily note |
| <kbd>⇧⌘H</kbd> | Homepage |
| <kbd>⌘D</kbd> · <kbd>⇧⌘D</kbd> | Split side by side · stacked. Layout (ratios, axis, open notes) is remembered per vault. |
| <kbd>⌘W</kbd> | Close the focused pane (the window, when there’s one pane) |
| <kbd>⌃⇥</kbd> · <kbd>⌃⇧⇥</kbd> | Next / previous pane |
| <kbd>⌘[</kbd> · <kbd>⌘]</kbd> | Back / forward (per pane; mouse buttons and swipe too) |
| <kbd>⌘⌫</kbd> | Delete note (to the Trash, after a confirm). After clicking in the sidebar, deletes the selection |
| <kbd>⇧</kbd>/<kbd>⌘</kbd>-click | Sidebar multi-select (range / toggle); right-click to Move, Reveal, or Delete them all; Esc clears |
| <kbd>⌘</kbd>-drag | Move the selected sidebar rows into a folder, or into the vault root (drop on the empty area). A folder can’t be moved into itself |
| <kbd>↩</kbd> | Rename the selected sidebar row, when the file tree is focused. Enter commits, Esc or an empty or unchanged name cancels |
| <kbd>⇧⌘M</kbd> | Move note to… a folder (fuzzy; type a new name to create one). Or ⌘-drag in the sidebar. Rename from File, right-click, or ↩ in the sidebar |
| <kbd>⌘N</kbd> | New note (in the selected folder, or next to the open note). The compose button at the bottom of the sidebar, Command Palette ▸ New note, and a folder’s New Note Here do the same |
| <kbd>⇧⌘N</kbd> | New folder (in the selected folder, or the vault root) |
| <kbd>⌘S</kbd> | Save. A still-Untitled note is named from its first heading (or first line) and appears under that name in the sidebar. Autosave writes the file while you type, but leaves the placeholder name until you save or leave the note |
| <kbd>⌃⌘F</kbd> | Focus mode: just the text |
| <kbd>⌥⌘←</kbd> · <kbd>⌥⌘→</kbd> | Fold / unfold the section at the caret ([folding](folding.md)) |
| <kbd>⌥⇧⌘←</kbd> · <kbd>⌥⇧⌘→</kbd> | Fold all headings and lists / unfold all |
| <kbd>⌥⌘0</kbd> | Three-pane workspace (sidebar + page + inspector) |
| <kbd>⌘,</kbd> | Settings |
| <kbd>⌘B</kbd> · <kbd>⌘/</kbd> · <kbd>⌘L</kbd> | Toggle bold · toggle `%%comment%%` · cycle checkbox (`- [ ]` → `- [x]`). The rest of the Format menu (italic, headings, lists, move line, …) is unbound by default; see [Commands](commands.md) |
| <kbd>⌘=</kbd> · <kbd>⌘-</kbd> · <kbd>⌘0</kbd> | Zoom text in · out · actual size (editor and reader together) |
| <kbd>Esc</kbd> | Put away whatever’s on top. In the editor, when nothing else would consume it, also saves and returns to reading view (Settings ▸ Editor; on by default). Never the other way |

Open Random Note is in the command palette and the Go menu; it has no default shortcut.

Read Aloud, Pause/Resume Reading, and Stop Reading are in the command palette and the Note menu; they have no default shortcut. Voice and Rate are in Settings ▸ Reading. Record Audio (Stop Recording while recording) is there too, also without a default shortcut.

Every command is also in the menu bar with its shortcut; the full list is in [Commands](commands.md). The first-run hint sheet lists the everyday ones; Note ▸ Show Shortcut Hints brings it back.

Customize any of these in Settings ▸ Shortcuts. Click a shortcut to record a new combination, or use Clear and Reset on that row. Reset All restores the defaults. If the combination is already used, or is reserved by the system (⌘Q for Quit, for example), Onyx warns you before it assigns it. The menu bar and the command palette follow the live bindings. Standard editing keys such as ⌘C, ⌘V, and ⌘Z stay with the editor and are not rebound here.

Lint Current Note and Lint All Notes in Folder… are in the command palette and the Note menu; they have no default shortcut. See [Linter](linter.md).

Merge Current File With Another File…, Extract Current Selection…, and Extract This Heading… are in the command palette and the Edit menu; the extract commands are also in the editor’s context menu. They have no default shortcut. Settings are in Settings ▸ Editor.
