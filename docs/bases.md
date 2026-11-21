# Bases

Obsidian Bases (`.base` files) open from the sidebar and <kbd>⌘O</kbd> as a table, a list, or a card grid. Views switch at the top, columns sort with a click (and the sort is saved back to the file), and note names open the note. Filters, formulas, summaries, and the subset of `file.*` functions those files use are evaluated against the live vault index. A fenced `base` code block in a note renders the same way, but stays read-only.

## What it supports

The official YAML is parsed: filters, formulas, views, sort, limit, `groupBy`, and `summaries`, plus the legacy `columns` / `filter` shape used in real vaults. Views are `table`, `list`, and `cards` (including a cover image and card size when the file asks for them). Unknown expressions warn instead of crashing the view; malformed YAML is tolerated rather than throwing.

Filters can be `and` / `or` / `not` groups, free expressions, or the legacy operators (`eq`, `contains`, `startswith`, `endswith`, `isempty`, and the usual comparison names). Formulas are evaluated per row, including references to other formulas (a cycle warns and returns empty).

`file.*` properties: `name`, `filename` / `basename`, `folder`, `ext`, `path`, `size`, `mtime` / `ctime`, `tags`, and `link`. File methods: `hasTag`, `hasLink`, `inFolder`, and `asLink`. Global functions: `if`, `list`, `link`, `now`, `today`, `date`, `duration`, `number`, and `string`. Value methods: `startsWith`, `endsWith`, `contains`, `containsAny`, `toString`, `toLower`, `toUpper`, `toFixed`, `date`, and `isEmpty`, plus:

- **Dates.** Arithmetic with duration literals (`now() + "1d"`, `"2w"`, `"1h30m"`), `.format("YYYY-MM-DD")`, `.relative()`, and `.year` / `.month` / `.day` (also hour, minute, second). Dates compare with `<` `>` `==`.
- **Lists.** `length`, `join`, `contains`, and (when cheap) `filter` / `map` with a small arrow function, e.g. `list(1, 2, 3).filter(x => x > 1)`.
- **Numbers.** `round`, `abs`, `ceil`, `floor`.
- **Strings.** `length`, `slice`, `replace`, `split`, `title`, `trim`.

Comparisons, booleans, and dates work in expressions.

**Summaries.** A table view can declare a `summaries` map (property → `Count`, `Sum`, `Average`, `Min`, `Max`, `Earliest`, `Latest`, `Unique`, `Empty`, or `Filled`). Custom formulas live in the file-level `summaries` key and receive `values` as the list of cells in that column (`values.mean().round(1)`). The summary row is drawn at the bottom of the table, and at the top of each group when the view is grouped.

By default a base includes every file under its filters — notes and attachments — unless the filters narrow it.

## Editing

A `.base` file opened as itself (not a fenced block in a note) can be edited in the view:

- Add or remove columns from a property picker (vault properties, `file.*`, and formulas). Reorder a column from the header’s context menu.
- Click a column header to sort; the sort is written to that view’s `sort` key.
- Double-click a view tab (or use the context menu) to rename it. The **+** menu adds a new table or cards view.
- **Filter…** opens a small popover for a simple property / operator / value filter, saved as the view’s legacy `filter` key.

Writes go through an atomic save, and **⌘Z** undoes the last base edit. The YAML is spliced, not rewritten: comments, unknown keys, and the order of untouched keys are kept as much as possible. If something is mid-edit in another app, the usual conflict sheet still applies.

## Limits

- **A subset of the formula language.** Unknown functions, methods, and formulas warn and return empty. Unknown filter operators warn and are skipped (the filter is treated as true, so rows are not dropped by a filter Onyx cannot read).
- **Not every Bases feature.** This is not a plugin host. If a formula or view option isn’t in the list above, expect a warning rather than a match for Obsidian’s own renderer.
- **Fenced `base` blocks** in notes are still view-only; only a `.base` file is edited in place.
- **Simple filters only**, from the popover. Complex `filters:` groups can still be edited in the file.

See also [compatibility](compatibility.md) and [Canvas and Kanban](boards.md).
