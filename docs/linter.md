# Linter

Onyx can tidy Markdown in a way similar to the Obsidian Linter plugin. It's conservative, it runs on your Mac, and running it twice gives the same result as running it once.

- **Note ▸ Lint Current Note**, or *Lint Current Note* in the command palette, tidies the open note as one undoable edit (<kbd>⌘Z</kbd>). Your caret stays on the same line.
- **Note ▸ Lint All Notes in Folder…** asks for a folder in the vault. You can also right-click a folder in the file tree and choose **Lint Notes in Folder…**. Before anything is written, a sheet shows how many notes would change. Notes open in a pane are skipped, and so is any file that changes on disk between the preview and Apply. Folder edits are written to disk and can't be undone with ⌘Z. Use git or Sync history to roll them back.
- **Lint on save** is in Settings ▸ Linter and is off by default. When it's on, an edited note is linted on <kbd>⌘S</kbd>, Save and Read, Esc to reading, and when you switch notes. It never runs on the typing autosave, so a space you just typed stays put.

Neither command has a default shortcut. You can bind them in Settings ▸ Shortcuts.

## Rules

| Rule | Default | What it does |
|---|---|---|
| Trim trailing whitespace | on | Removes trailing spaces and tabs. Two or more spaces after text become exactly two, which is a hard line break. You can turn that off with *Preserve two-space hard line breaks*. |
| Collapse blank lines | on | Turns two or more blank lines in a row into one. |
| Single trailing newline | on | The file ends with exactly one newline. |
| Blank lines around headings | on | Adds an empty line before and after each heading. |
| Space after # in headings | on | Changes `##Heading` to `## Heading`. A single `#word` is a tag, so it's left alone. |
| Consistent list marker | on | Every unordered bullet uses `-`. You can pick `*` or `+` instead. Horizontal rules aren't changed. |
| Blank lines around code blocks | on | Adds an empty line before and after top-level fenced code blocks. Fences nested in lists aren't changed. |
| Normalize checkboxes | on | Changes `[]` to `[ ]` and `[X]` to `[x]`. Custom statuses such as `[/]`, `[-]`, and `[>]` are kept. |
| Heading increments | off | Stops headings from skipping a level. The first heading keeps its level. |
| Tidy frontmatter keys | off | Normalizes top-level YAML key spacing, so `key :value` becomes `key: value`. Values and nested lines aren't changed. |
| Updated timestamp | off | Writes `updated: YYYY-MM-DDTHH:mm` in local time, or `modified:` if you choose that key. A manual lint stamps the note only when another rule changed it. Lint on save stamps every edited note. If the note has no frontmatter, it's created. |

## What the linter never touches

The linter leaves these alone:

- fenced code (backticks or tildes)
- `$$` math blocks
- `%% comments %%` and `<!-- HTML comments -->`
- blockquotes and callouts (`> [!note]`)
- inline-field lines such as `partOf:: [[Parent]]` or `- related:: [[A]]`
- frontmatter, unless *Tidy frontmatter keys* or *Updated timestamp* is on, and even then values stay as they are apart from the timestamp key

Inline code, `$math$`, and wikilinks are protected too, because the rules only change the start and end of a line and the blank lines between lines. When an inline code or math span runs across several lines, all of those lines are left untouched until the paragraph ends. Windows (CRLF) line endings are kept.

Settings live in UserDefaults (`onyx.lint.*`), so they apply to every vault.
