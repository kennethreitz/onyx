# Folding

Fold a heading's section, or a list item's nested items, down to one line. Folding changes only what you see. The text in the note stays the same, so saving, sync, git, search, find and replace, undo, copy, and `[[` completion all work on the whole note.

## In the editor

- Hover a heading, or a list item that has nested items, and a quiet chevron shows in the left margin. Click it to fold. A folded line keeps its chevron and ends with a small **⋯** pill. Click either one to unfold.
- A heading's section runs to the next heading of the same or a higher level. Blank lines at the end of a section stay visible, so the space between sections doesn't change. Headings inside code fences and frontmatter are ignored. Setext headings (`Title` over `===` or `---`) fold too.
- A list item folds only when it has a nested list item under it. Indented continuation lines fold with their parent; an unindented line ends the list.
- Folds nest. Opening a section leaves the folds inside it as they were.
- **The caret never goes into folded text.** <kbd>→</kbd> at the end of a folded line jumps to the next visible line, and <kbd>←</kbd> from there jumps back. <kbd>↑</kbd>, <kbd>↓</kbd>, and clicks land on the folded line itself.
- **Anything that takes you into a fold opens it:** Find and Find and Replace, Jump to Heading, the outline, a `[[Note#Heading]]` link, and undo or redo of an edit inside a fold.
- **Edits never touch hidden text.** Deleting the line break after a fold, or any edit that would change folded text, opens the fold first. Selecting a folded section from its heading down and deleting it removes it all, as you'd expect.
- Editing a folded heading keeps it folded, even when you change its level or text. Deleting the heading, or turning it into ordinary text, unfolds the section.

## In the reader

Headings in the reading view get the same chevron on hover. Click it, or the **⋯** after a folded heading, to fold or unfold. The reader and the editor share each note's folds. Find opens any fold its current match is in, and so does Jump to Heading. Folded sections are still printed and exported in full. List folding is only in the editor.

## Commands

All of these are in **View ▸ Folding** and the command palette. You can rebind them in Settings ▸ Shortcuts.

| Command | Default | What it does |
| --- | --- | --- |
| Fold Section | <kbd>⌥⌘←</kbd> | Folds the heading or list item at the caret, or else the section the caret is in. If that's already folded, it folds the parent section. |
| Unfold Section | <kbd>⌥⌘→</kbd> | Unfolds the folded line at the caret. |
| Toggle Fold | — | Folds or unfolds the line at the caret. |
| Fold All Headings and Lists | <kbd>⌥⇧⌘←</kbd> | |
| Unfold All | <kbd>⌥⇧⌘→</kbd> | |

These defaults follow Xcode because <kbd>⌥⌘[</kbd> and <kbd>⌥⌘]</kbd> already go to the previous and next daily note. In the reader, Fold Section, Unfold Section, and Toggle Fold act on the section you're reading.

## Settings and storage

**Settings ▸ Editor ▸ Folding** has two switches, both on by default: **Fold headings** and **Fold indent (nested lists)**. Turning one off hides its chevrons and lets those sections show, but Onyx remembers your folds for when you turn it back on.

Folds are saved per note on this Mac, like Obsidian's, and never in the note or in `.obsidian`. Onyx remembers each fold by its heading text and which occurrence it is, so folds come back after a relaunch, after a sync changes the note, and after a rename or move. Onyx drops a fold when its heading is gone.

## How it works

The editor uses TextKit 1. `FoldLayoutManager` (OnyxCore) gives the folded characters null glyphs and lets the line break at the end of a section stay visible. The hidden lines then take no space and never become line fragments of their own. Onyx changes no attributes, attachments, or text. Folding works out fold ranges in one pass in `MarkdownFolds`, keeps folds through edits with `FoldEdits`, and keeps the caret in visible text with `FoldSelection`. All three are covered by `FoldingTests` and `FoldLayoutTests`. When nothing is folded, the layout path does no extra work.
