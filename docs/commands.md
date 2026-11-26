# Commands

Every command below is in the command palette (<kbd>⌘P</kbd>) and the menu bar, and can be rebound in Settings ▸ Shortcuts. Defaults follow Obsidian where they don’t clash with Onyx’s own keys (⌘K is the sidebar, so Insert Markdown Link starts unbound; italic is ⌘I and the outline sidebar is ⌥⌘I).

## File

| Command | Default |
| --- | --- |
| New Note | <kbd>⌘N</kbd> |
| New Folder | <kbd>⇧⌘N</kbd> |
| Open Vault… | <kbd>⇧⌘O</kbd> |
| Quick Switcher… | <kbd>⌘O</kbd> |
| Command Palette… | <kbd>⌘P</kbd> · <kbd>⇧⌘P</kbd> |
| Save | <kbd>⌘S</kbd> |
| Rename File… | — |
| Move Note to… | <kbd>⇧⌘M</kbd> |
| Delete Note… | — |
| Export as PDF… | <kbd>⇧⌘E</kbd> |
| Export Selection as PDF… | — |
| Export Folder as PDF… | — |
| Print… | <kbd>⌥⌘P</kbd> |
| Duplicate Note | — |
| Copy File Path | — |
| Open in Default App | — |
| Clip Web Page… | <kbd>⇧⌘K</kbd> |
| Open Settings… | — |

<kbd>⌘⌫</kbd> is not bound to Delete Note…, so the editor can use it to delete to the start of the line. When the file tree has focus, <kbd>⌘⌫</kbd> still deletes the selected file(s) to the Trash, after a confirm, like Finder. The command stays in the File menu and the palette.

## Edit

| Command | Default |
| --- | --- |
| Find in Note… | <kbd>⌘F</kbd> |
| Find and Replace… | <kbd>⌥⌘F</kbd> |
| Replace in Vault… | <kbd>⌥⇧⌘F</kbd> |
| Undo Last Replace | — |
| Search Vault for Selection | — |
| Toggle Spellcheck | — |
| Merge Current File With Another File… | — |
| Extract Current Selection… | — |
| Extract This Heading… | — |

Replace in Vault opens a preview of every match, grouped by note, with per-match checkboxes and before/after highlighting. You can search the whole vault, the current folder, or the current note, and choose match case, whole word, regular expressions (with `$1` capture groups in the replacement), and whether frontmatter is included. Replace Selected and Replace All ask for confirmation and show the counts; writes are atomic, open editors are updated, and Undo Last Replace restores the previous contents of those notes. The Search sidebar (⇧⌘F) has a button that opens the same panel with the current query. In-note find and replace (⌘F / ⌥⌘F in the editor) is unchanged.

## Format

| Command | Default |
| --- | --- |
| Toggle Bold | <kbd>⌘B</kbd> |
| Toggle Italic | <kbd>⌘I</kbd> |
| Toggle Strikethrough | — |
| Toggle Highlight | — |
| Toggle Inline Code | — |
| Toggle Comment | <kbd>⌘/</kbd> |
| Insert Wikilink | — |
| Insert Markdown Link | — |
| Heading 1 | — |
| Heading 2 | — |
| Heading 3 | — |
| Heading 4 | — |
| Heading 5 | — |
| Heading 6 | — |
| Toggle Bullet List | — |
| Toggle Numbered List | — |
| Toggle Checklist | — |
| Cycle Checkbox | <kbd>⌘L</kbd> |
| Toggle Blockquote | — |
| Indent | — |
| Outdent | — |
| Insert Callout | — |
| Insert Code Block | — |
| Insert Table | — |
| Insert Horizontal Rule | — |
| Insert Current Date | — |
| Insert Current Time | — |
| Move Line Up | — |
| Move Line Down | — |
| Duplicate Line | — |
| Delete Line | — |

## View

| Command | Default |
| --- | --- |
| Read Note / Edit Note | <kbd>⌘E</kbd> |
| Save and Read / Edit and Save | <kbd>⌘↩</kbd> |
| Focus Mode | <kbd>⌃⌘F</kbd> |
| Show Sidebar | <kbd>⌘K</kbd> |
| Search Vault | <kbd>⇧⌘F</kbd> |
| Recent Files | <kbd>⇧⌘R</kbd> |
| Bookmarks | <kbd>⇧⌘B</kbd> |
| Tags | <kbd>⇧⌘T</kbd> |
| Source Control | <kbd>⇧⌘Y</kbd> |
| Version History | — |
| Show Outline | <kbd>⌥⌘I</kbd> |
| Outline | <kbd>⌥⌘1</kbd> |
| Links | <kbd>⌥⌘2</kbd> |
| Properties | <kbd>⌥⌘3</kbd> |
| Three-Pane Workspace | <kbd>⌥⌘0</kbd> |
| Footnotes as Sidenotes | — |
| Appearance: Light | — |
| Appearance: Dark | — |
| Appearance: Match System | — |
| Show Sync Log | — |

| Fold Section | <kbd>⌥⌘←</kbd> |
| Unfold Section | <kbd>⌥⌘→</kbd> |
| Toggle Fold | — |
| Fold All Headings and Lists | <kbd>⌥⇧⌘←</kbd> |
| Unfold All | <kbd>⌥⇧⌘→</kbd> |
| Zoom In | <kbd>⌘=</kbd> |
| Zoom Out | <kbd>⌘-</kbd> |
| Actual Size | <kbd>⌘0</kbd> |

Backlinks lists notes that link to the current one (click to open at that line) and unlinked mentions of its title or aliases, each with Link or Link all to turn them into wikilinks.

## Navigate

| Command | Default |
| --- | --- |
| Today’s Daily Note | <kbd>⌘T</kbd> · <kbd>⌘\</kbd> |
| Previous Daily Note | <kbd>⌥⌘[</kbd> |
| Next Daily Note | <kbd>⌥⌘]</kbd> |
| Back | <kbd>⌘[</kbd> |
| Forward | <kbd>⌘]</kbd> |
| Homepage | <kbd>⇧⌘H</kbd> |
| Open Random Note | — |
| Focus Graph | <kbd>⌘G</kbd> |
| Atlas | <kbd>⇧⌘G</kbd> |
| Graph in a Pane | <kbd>⌥⌘G</kbd> |
| Yesterday’s Daily Note | — |
| Tomorrow’s Daily Note | — |
| Jump to Heading… | — |
| Reveal in Sidebar | — |

## Pane

| Command | Default |
| --- | --- |
| Split Side by Side | <kbd>⌘D</kbd> |
| Split Stacked | <kbd>⇧⌘D</kbd> |
| Close Pane | <kbd>⌘W</kbd> (closes the window when there is only one pane; that leaves Onyx running) |
| Next Pane | <kbd>⌃⇥</kbd> |
| Previous Pane | <kbd>⌃⇧⇥</kbd> |
| New Note in New Pane | — |

## Note

| Command | Default |
| --- | --- |
| Bookmark | <kbd>⌥⌘D</kbd> |
| Copy Wikilink | <kbd>⇧⌘L</kbd> |
| Reveal in Finder | <kbd>⌥⇧⌘R</kbd> |
| Open in Obsidian | — (hold ⌥ in menus; always in the palette) |
| Read Aloud | — |
| Pause Reading | — |
| Stop Reading | — |
| Record Audio | — |
| Rebuild Index | — |
| Show Shortcut Hints | — |

## Notes

- Format commands work on the editor. From the reader, they switch to editing first. Each one is a single undo step.
- Toggles are reversible: running Toggle Bold on `**bold**` or `__bold__` (selected with or without its markers) removes the markers, and Toggle Italic does the same for `*italic*` or `_italic_`. With no selection, each inserts an empty pair and a second press removes it. List, checklist, and quote toggles apply to every selected line, and remove the prefix when every line already has it. A heading command on a line at that level turns it back into text.
- Return in a list continues it: the same `-`, `*`, or `+` bullet, the next number (`1.` or `1)`), or a new unchecked checkbox. A Return in the middle of an item splits the text onto the new item. Return on an empty item ends the list, or outdents one level if the item is nested. Following numbered items in that contiguous list are then renumbered, keeping the list's starting number and delimiter; nested lists are numbered independently. A blank line or a non-list line ends the list, so two numbered lists separated by a blank stay independent. Shift-Return is a plain newline. Tab and Shift-Tab indent and outdent list items (the Indent and Outdent commands do the same, and have no default shortcut), and both the level left and the level joined are renumbered (a newly nested item starts at 1). Delete Line, Backspace, Delete, and cut also renumber when they leave a list out of sequence. This is off when `smartIndentList` is `false` in the vault’s `app.json`; Settings ▸ Editor has the toggle. Return does not continue a list inside a fenced code block or frontmatter, or while an IME is composing, and those regions are not renumbered.
- Smart pairs (Obsidian’s Auto pair brackets and Auto pair Markdown syntax) insert a closer when you type `(`, `[`, `{`, `"`, `'`, or `` ` ``, with the caret in between — so `[[` becomes `[[|]]`, and wikilink autocomplete still steps past or writes the existing `]]`. Quotes do not pair mid-word (`don't`). With a selection, those markers and `*` `_` `~` `=` wrap the text and keep it selected, so typing `*` twice wraps `**bold**`. Typing the closer when it is already next steps over it; Backspace in an empty pair deletes both. `*` `_` `~` `=` are not paired without a selection, and are left alone in fenced code. Off when `autoPairBrackets` or `autoPairMarkdown` is `false` in `app.json`; Settings ▸ Editor has the toggles.
- Cycle Checkbox (<kbd>⌘L</kbd>) turns a line into `- [ ] `, then toggles it between `[ ]` and `[x]`.
- Move Line Up/Down, Duplicate Line, and Delete Line act on every line the selection touches.
- Today’s Daily Note and Previous/Next Daily Note were already there. Previous/Next step between existing daily notes when one is open. Yesterday’s and Tomorrow’s always go by the calendar, and create the note if needed.
- Jump to Heading… lists the open note’s headings in a palette.
- Show Outline (<kbd>⌥⌘I</kbd>) and Outline (<kbd>⌥⌘1</kbd>) show or hide the right outline sidebar (always docked, no tab bar). The scope menu there can widen the tree from this note to its folder, linked and `partOf` neighbors, or the whole vault. A leading H1 is the note's title row. Clicking a heading lands it a little below the visible top of the page; the current section highlights as you scroll, and off-path branches collapse. Links (<kbd>⌥⌘2</kbd>) opens the left sidebar’s Links tab (relationships, backlinks, and unlinked mentions). Properties (<kbd>⌥⌘3</kbd>) opens the title-bar properties popover (also Note ▸ Properties).
- Folding (View ▸ Folding) folds a heading’s section or a list item’s nested items in the editor, and headings in the reader. It’s display only; the note text never changes. See [folding.md](folding.md).
- Zoom In/Out change the editor and reader text sizes together, within the Settings ranges. Actual Size resets both.
- Spellcheck is on by default; the toggle is also in Settings ▸ Editor.
- Note composer matches Obsidian’s core plugin. Merge Current File With Another File… opens a quick switcher, asks you to confirm, then appends (or prepends) the open note to the one you pick, merges frontmatter, rewrites links to the source so they point at the target, and moves the source to the Trash. Extract Current Selection… and Extract This Heading… (the heading and everything until the next heading of the same or a higher level) write the text to a new note or append it to an existing one, and replace the original with a wikilink, an embed, or nothing — one undo step in the editor. Both extract commands are also in the editor’s context menu. A selection that starts with a heading offers that heading as the filename. Settings are in Settings ▸ Editor: confirm before merging, append vs prepend, where new notes land, what to leave behind, and whether to open the extracted note.
