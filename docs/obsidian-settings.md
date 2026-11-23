# Obsidian settings in Onyx

Two Settings tabs, **Files & Links** and **Daily Notes**, edit Obsidian's own core settings for the open vault. They don't keep a separate copy: Onyx reads and writes the same files under `.obsidian/` that Obsidian uses, so a change made in either app shows up in the other. That includes changes that arrive through Obsidian Sync.

## How Onyx writes them

- Only the keys you change are written. Every other key in the file stays where it is, with its exact text, including settings from Obsidian versions or plugins that Onyx doesn't know about. New keys go at the end, in Obsidian's 2-space JSON layout.
- Writes are atomic. The file is replaced in a single step, so Obsidian or Sync never sees half a file.
- A missing file, or a missing `.obsidian` folder, is created.
- A file that isn't valid JSON is left alone, and Onyx says so instead of overwriting it.
- Onyx watches `app.json`, `daily-notes.json`, and `templates.json`. When Obsidian or Sync changes one of them, Settings and the daily-note commands pick up the new values right away.
- Text fields save when you press Return or leave the field. Folder and file fields have a **Choose…** button that only accepts places inside the vault. You can also type a vault-relative path. Paths outside the vault (`..`, `~`) and names with characters Obsidian rejects get a warning.

## Files & Links (`.obsidian/app.json`)

| Setting | Key | What Onyx does with it |
| --- | --- | --- |
| Default location for new notes | `newFileLocation` (`root`, `current`, `folder`) and `newFileFolderPath` | Used for ⌘N, creating a note from the quick switcher, and clicking a link to a note that doesn't exist. **Onyx default** (no key) keeps Onyx's own choice: ⌘N uses the selected folder or the open note's folder, and links and the switcher use the vault root. Obsidian treats no key as the vault root. New Note Here in the sidebar always uses that folder. |
| New link format | `newLinkFormat` | Shortest, relative, or absolute paths in links to [dropped and pasted files](attachments.md#the-link), and in links that rename has to turn from a name into a path. |
| Use [[Wikilinks]] | `useMarkdownLinks` (inverted) | When it's off, attachment links are Markdown links: `![](photo.png)`. |
| Default location for new attachments | `attachmentFolderPath` | Vault folder (`/`), same folder as the current file (`./`), a subfolder under the current folder (`./attachments`), or a folder you name. Dropped, pasted, and recorded files go there ([details](attachments.md#where-files-go)). |
| Automatically update internal links | `alwaysUpdateLinks` | On: renaming or moving a file updates links to it without asking. Off or unset: Onyx asks first, like Obsidian, and **Always Update** turns this on ([details](attachments.md#renaming-and-moving)). |
| Default view for new tabs | `defaultViewMode` (`preview`, `source`) | The mode Onyx opens a vault in. |
| Excluded files | `userIgnoreFilters` | One folder or path per line. These files are hidden from search, the graph, and the sidebar. **Apply** re-indexes the vault. |

## Daily Notes (`.obsidian/daily-notes.json`)

| Setting | Key | What Onyx does with it |
| --- | --- | --- |
| Date format | `format` | A [moment.js format](https://momentjs.com/docs/#/displaying/format/), as in Obsidian. The default is `YYYY-MM-DD`. A `/` nests notes in dated folders, as in `YYYY/MM/YYYY-MM-DD`. Text in `[brackets]` is copied literally. The field shows a live preview. |
| New file location | `folder` | Where daily notes go. When the file doesn't name a folder, Onyx keeps using `Daily`. |
| Template file location | `template` | A note whose text starts each new daily note. Leave it empty to use Onyx's built-in daily note, which has `class: DailyNote` frontmatter and a long-date heading. |
| Open daily note on startup | `autorun` | When the vault opens, today's note opens too (after your restored panes), instead of the home note or the atlas. |

In a template, the following placeholders are filled in, as in Obsidian:

- `{{date}}` and `{{title}}` become the note's date in the daily format.
- `{{time}}` becomes the current time in the Templates time format.
- `{{date:dddd, MMMM D}}` and `{{time:h:mm A}}` take a format of their own.

Previous and Next Daily Note step through every note that matches the folder and format, in date order.

### Templates (`.obsidian/templates.json`)

| Setting | Key | What Onyx does with it |
| --- | --- | --- |
| Template folder location | `folder` | Where **Choose…** starts when you pick a daily-note template. |
| Date format | `dateFormat` | Used by Insert Current Date. The default is `YYYY-MM-DD`. |
| Time format | `timeFormat` | Used by Insert Current Time and `{{time}}`. The default is `HH:mm`. |

## Limits

- Onyx has no Insert Template command yet, so the template folder only affects the template picker.
- Formats with ordinals (`Do`) or Unix time (`X`, `x`) work for creating notes. Onyx can't read the date back out of those names, so Previous and Next Daily Note skip them. The Date format field warns about this.
- Moment's localized tokens (`L`, `LL`, `LT`) and lowercase `a` aren't supported. `a` gives `AM`/`PM`, just like `A`.
- Onyx doesn't read `promptDelete`.
- Unique note creator (`zk-prefixer.json`) isn't supported.
