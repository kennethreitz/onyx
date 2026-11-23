# Commands

Every command below is in the command palette (<kbd>⌘P</kbd>) and the menu bar, and can be rebound in Settings ▸ Shortcuts. Defaults follow Obsidian where they don’t clash with Onyx’s own keys (⌘I is the inspector and ⌘K the sidebar, so Italic and Insert Markdown Link start unbound).

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
| Delete Note… | <kbd>⌘⌫</kbd> |
| Export as PDF… | <kbd>⇧⌘E</kbd> |
| Export Selection as PDF… | — |
| Export Folder as PDF… | — |
| Print… | <kbd>⌥⌘P</kbd> |
| Duplicate Note | — |
| Copy File Path | — |
| Open in Default App | — |
| Open Settings… | — |

## Edit

| Command | Default |
| --- | --- |
| Find in Note… | <kbd>⌘F</kbd> |
| Find and Replace… | <kbd>⌥⌘F</kbd> |
| Search Vault for Selection | — |
| Toggle Spellcheck | — |
| Merge Current File With Another File… | — |
| Extract Current Selection… | — |
| Extract This Heading… | — |

## Format

| Command | Default |
| --- | --- |
| Toggle Bold | <kbd>⌘B</kbd> |
| Toggle Italic | — |
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
| Inspector | <kbd>⌘I</kbd> |
| Outline | <kbd>⌥⌘1</kbd> |
| Backlinks | <kbd>⌥⌘2</kbd> |
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
| Open in Obsidian | — |
| Read Aloud | — |
| Pause Reading | — |
| Stop Reading | — |
| Record Audio | — |
| Rebuild Index | — |
| Show Shortcut Hints | — |

## Notes

- Format commands work on the editor. From the reader, they switch to editing first. Each one is a single undo step.
- Toggles are reversible: running Toggle Bold on `**bold**` (selected with or without its markers) removes the markers. List, checklist, and quote toggles apply to every selected line, and remove the prefix when every line already has it. A heading command on a line at that level turns it back into text.
- Cycle Checkbox (<kbd>⌘L</kbd>) turns a line into `- [ ] `, then toggles it between `[ ]` and `[x]`.
- Move Line Up/Down, Duplicate Line, and Delete Line act on every line the selection touches.
- Today’s Daily Note and Previous/Next Daily Note were already there. Previous/Next step between existing daily notes when one is open. Yesterday’s and Tomorrow’s always go by the calendar, and create the note if needed.
- Jump to Heading… lists the open note’s headings in a palette.
- Folding (View ▸ Folding) folds a heading’s section or a list item’s nested items in the editor, and headings in the reader. It’s display only; the note text never changes. See [folding.md](folding.md).
- Zoom In/Out change the editor and reader text sizes together, within the Settings ranges. Actual Size resets both.
- Spellcheck is on by default; the toggle is also in Settings ▸ Editor.
- Note composer matches Obsidian’s core plugin. Merge Current File With Another File… opens a quick switcher, asks you to confirm, then appends (or prepends) the open note to the one you pick, merges frontmatter, rewrites links to the source so they point at the target, and moves the source to the Trash. Extract Current Selection… and Extract This Heading… (the heading and everything until the next heading of the same or a higher level) write the text to a new note or append it to an existing one, and replace the original with a wikilink, an embed, or nothing — one undo step in the editor. Both extract commands are also in the editor’s context menu. A selection that starts with a heading offers that heading as the filename. Settings are in Settings ▸ Editor: confirm before merging, append vs prepend, where new notes land, what to leave behind, and whether to open the extracted note.
