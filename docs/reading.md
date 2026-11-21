# Reading

Onyx opens a folder of `.md` files and gets out of the way. It edits like a calm text editor and reads like a typeset page — Latin Modern, hyphenated, ragged-right (justification is opt-in). Your Obsidian vault opens as-is. Obsidian can keep running right alongside it. Quiet, fast, and yours — no database, no account, no lock-in.

<p align="center"><img src="reader.png" alt="Reading view: a note typeset in Latin Modern" width="85%"></p>

Two modes, one keystroke. The editor is IBM Plex Mono with live Markdown styling. The reader is the Reitz LaTeX theme: a measure you can set, Tufte-style sidenotes, footnotes, tables, callouts, Mermaid figures, and `$inline$` / `$$display$$` math (including multi-line `$$` blocks). <kbd>⌘↩</kbd> (or <kbd>⌘E</kbd>) flips between them, saves, and keeps your place in the note. <kbd>Esc</kbd> in the editor does the same one way — save and return to reading — but only when nothing else would consume it (Settings ▸ Editor; on by default). It never leaves reading view. A single newline inside a paragraph is a line break, the way Obsidian does it unless “Strict line breaks” is on.

Typeset reading (on by default, Settings ▸ Reading) sets the page the way a book would: curly quotes and real dashes (never inside code), true small caps for acronyms, old-style figures in prose and lining tabular figures in tables, hyphenation in the note’s `lang`, ragged-right text (Settings ▸ Reading can turn on justification), hanging punctuation, a small-caps lead-in or drop cap, epigraphs, booktabs tables, and numbered figure and table captions. Choose Latin Modern or ET Book. Sidenotes stack and never collide, and they reflow when fonts, images, or the window change. Write `[^n]: {-} …` for an unnumbered margin note. When the window is narrow, notes fold behind a tap. Turn it off to get the plain Reitz LaTeX page back.

File ▸ Export as PDF… (<kbd>⇧⌘E</kbd>) and Print… (<kbd>⌥⌘P</kbd>) lay the note out as a book page. You get sidenotes as margin notes, a running head in small caps, and folios, and links keep working. Math is typeset in the export too.

`$inline$` and `$$display$$` math uses Obsidian’s rules — no space right inside the delimiters — so currency like `$5 and $10`, escaped `\$`, and dollars inside code are left alone. The editor keeps showing the source. Invalid TeX is shown inline as an error instead of breaking the page. KaTeX is bundled and works offline.

Frontmatter, `%%comments%%`, embeds, images, PDFs, audio and video all render in the reader. Preliminary Dataview support runs `dataview` blocks in the reader: TABLE (including WITHOUT ID) with AS columns, and LIST; FROM a folder or `#tag` with OR and `-` exclusion; WHERE with comparisons, AND/OR, `contains()`, `choice()`, `default()`; SORT; LIMIT. Inline queries, DataviewJS, TASK, CALENDAR, and GROUP BY are not supported yet; those queries show an error box.

Saves are atomic and conflict-aware: if the file changed on disk, Onyx offers to keep yours, take theirs, or keep both. Light, dark, or auto, text size, and line measure live in <kbd>⌘,</kbd>. <kbd>⌃⌘F</kbd> is focus mode — just the text.

Split with <kbd>⌘D</kbd> (side by side) or <kbd>⇧⌘D</kbd> (stacked), up to four panes. Drag the divider to resize (240pt minimum); double-click it to equalize. Each pane keeps its own note, its own history, and its own read/edit mode. <kbd>⌘W</kbd> closes the focused pane, or the window when there is only one.

See also [keyboard shortcuts](shortcuts.md) and [getting around](navigation.md).
