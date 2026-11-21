# Bases

Obsidian Bases (`.base` files) open from the sidebar and <kbd>⌘O</kbd> as a table, a list, or a card grid. Views switch at the top, columns sort with a click, and note names open the note. Filters, formulas, and the subset of `file.*` functions those files use are evaluated against the live vault index. Bases are read-only in this release: you can look, not edit the YAML. A fenced `base` code block in a note renders the same way.

## What it supports

The official YAML is parsed: filters, formulas, views, sort, limit, and `groupBy`, plus the legacy `columns` / `filter` shape used in real vaults. Views are `table`, `list`, and `cards` (including a cover image and card size when the file asks for them). Unknown expressions warn instead of crashing the view; malformed YAML is tolerated rather than throwing.

Filters can be `and` / `or` / `not` groups, free expressions, or the legacy operators (`eq`, `contains`, `startswith`, `endswith`, `isempty`, and the usual comparison names). Formulas are evaluated per row, including references to other formulas (a cycle warns and returns empty).

`file.*` properties: `name`, `filename` / `basename`, `folder`, `ext`, `path`, `size`, `mtime` / `ctime`, `tags`, and `link`. File methods: `hasTag`, `hasLink`, `inFolder`, and `asLink`. Global functions: `if`, `list`, `link`, `now`, `today`, `date`, `number`, and `string`. Value methods: `startsWith`, `endsWith`, `contains`, `containsAny`, `toString`, `toLower`, `toUpper`, `toFixed`, `date`, and `isEmpty`. Comparisons, booleans, and dates work in expressions.

By default a base includes every file under its filters — notes and attachments — unless the filters narrow it.

## Limits

- **Read-only.** You can switch views and sort columns, but Onyx does not edit the `.base` YAML. Change the file in a text editor or in Obsidian.
- **A subset of the formula language.** Unknown functions, methods, and formulas warn and return empty. Unknown filter operators warn and are skipped (the filter is treated as true, so rows are not dropped by a filter Onyx cannot read).
- **Not every Bases feature.** This is viewing, not a plugin host. If a formula or view option isn’t in the list above, expect a warning rather than a match for Obsidian’s own renderer.

See also [compatibility](compatibility.md) and [Canvas and Kanban](boards.md).
