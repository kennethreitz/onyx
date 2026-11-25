# Tags

Onyx reads tags the way Obsidian does and shows them as a tree.

## What counts as a tag

- Inline: `#tag`, nested `#parent/child/grandchild`, and Unicode (`#café`, `#📚`). Letters, numbers, `_`, `-` and `/`; a tag needs at least one character that isn't a number, so `#2024` isn't a tag but `#y2024` is.
- Frontmatter: `tags:` or `tag:` as an inline list (`tags: [a, b/c]`), a block list (`- a`), or a space- or comma-separated value (`tags: a b, c`), quoted or not, with or without a leading `#`.
- Case doesn't matter: `#Book` and `#book` are one tag. The tree shows whichever spelling is used most.
- Not tags: anything in fenced or inline code, inside `[[links]]` (`[[Note#Heading]]`, `[[#Heading]]`), Markdown link targets (`[x](#anchor)`), URLs (`https://example.com/#frag`), HTML entities (`&#123;`), `c#sharp` (a word character before `#`), and headings (`# Heading` has a space after `#`). A trailing `/` (`#a/b/`) belongs to the sentence, not the tag.

## The Tags pane

Open it from the sidebar's `#` tab (or the command palette: tags).

- **Tree.** Nested tags nest. Click the disclosure triangle (or double-click the row) to open or close a node; <kbd>⌥</kbd>-click the triangle to open or close everything beneath it. The expansion state is remembered per vault. A parent that no note uses directly (only its children) shows in a lighter ink.
- **Counts.** The number on the right is how many notes have the tag or any tag nested under it, each note counted once. When a parent is also used on its own, a fainter count before it is the notes tagged exactly there (`3 · 12`). Hover a row for both in words.
- **Notes.** Click a tag to list its notes under the tree, including nested tags (Obsidian's `tag:#parent`). **+ Nested** switches to **Exact** (only notes tagged exactly that); the same choice is in the sort menu as Exact Matches Only and also changes the counts. The magnifier opens the tag in vault search (`tag:parent`), which also includes nested tags.
- **Filter.** Type in the box at the top to keep only tags whose path contains every word (`fic book`); matching branches open themselves. <kbd>↩</kbd> selects the first match; <kbd>Esc</kbd> clears.
- **Sort.** By name or by count (most notes first), from the menu beside the filter. Expand All and Collapse All are there too.

## Rename and move

Right-click a tag ▸ **Rename…**. The new name applies to the tag and everything nested under it, in every note: renaming `#book` to `#library` turns `#book/fiction/scifi` into `#library/fiction/scifi`, in text and in frontmatter `tags:` lists alike, and leaves `#bookish`, code, and other properties alone. You can type a nested path to move it (`#reading/books`), and a case-only rename (`#book` → `#Book`) works. The sheet previews every line that changes, note by note, before anything is written, and says when the new name already exists (the two tags merge). Notes are written atomically and open editors update. The sort menu offers **Undo Rename** for the last one.

**Drag** a tag onto another tag to nest it there (drag `#fiction` onto `#book` to get `#book/fiction`), or onto the empty space below the tree to make it top-level; **Move to Top Level** is in the context menu too. Both open the same preview first.

## In notes

- **Completion.** Type `#` in a note and a list offers your tags by path segment: `#pro` offers `#projects`, `#projects/` offers its children, `#projects/ac` the children starting with `ac`. Deeper tags whose segment matches come after the top-level ones. <kbd>↓</kbd>/<kbd>↑</kbd> highlight, <kbd>↩</kbd>/<kbd>⇥</kbd> take the highlighted row (nothing is taken unless you highlight it or the top row matches exactly), <kbd>Esc</kbd> closes it. Taking a parent that only exists through its children writes `#parent/` and keeps the list open for the next segment; a finished tag gets a space after it. The same completion works in a frontmatter `tags:` list, without the `#`.
- **Clicking tags.** Click a tag in the reader, <kbd>⌘</kbd>-click one in the editor, or click a tag chip in the inspector's Properties tab, and the Tags pane opens on it, with its parents expanded and its notes listed.

The parsing, tree, counts, filtering, completion, and rename logic live in OnyxCore (`Sources/OnyxCore/Tags.swift`) with unit tests (`swift test --filter TagsTests`). On a 2,600-note vault the tree builds in about 3 ms, and a rename preview of a tag on 1,000 notes takes under 100 ms, off the main thread.
