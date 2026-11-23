# Attachments: drag, drop, and paste

Drop files into the editor, or paste them, and Onyx adds them to the vault the way Obsidian does. Each file is copied into your attachment folder, and a link goes in at the drop point or the caret.

## What you can drop or paste

- **Files from Finder.** Any type, and several at once. Each one is copied in under its own name, and the links go in one per line.
- **Images from a browser, Photos, Mail, or Preview.** When the app hands over the original file, it keeps its name and format. When it only hands over pixels, Onyx saves a PNG named `Pasted image YYYYMMDDHHmmss.png`.
- **An image on the clipboard.** Use ⌘V after Copy Image or a screenshot to the clipboard (⌃⇧⌘4). It becomes `Pasted image ….png`. Copied rich text that happens to include a picture still pastes as text.
- **Files copied in Finder.** Copy them with ⌘C, then paste with ⌘V in the editor.
- **Files already in the vault.** Use ⌘-drag from the sidebar, or drag from Finder a file that lives inside the vault. These files are linked where they are, not copied.

Dragging text, or a plain web link, still works as ordinary text.

## Where files go

Onyx reads **Default location for new attachments** (`attachmentFolderPath` in `.obsidian/app.json`). That setting is in Obsidian under Settings ▸ Files and links.

| Setting | Files land in |
| --- | --- |
| unset, or `/` (Obsidian's default) | the vault root |
| `./` | the same folder as the note |
| `./assets` | a subfolder of the note's folder (created if needed) |
| `Attachments` | that folder in the vault (created if needed) |

When a name is taken, Onyx adds a number before the extension, as Obsidian does: `photo.png`, then `photo 1.png`, then `photo 2.png`. Onyx also replaces characters Obsidian doesn't allow in file names (`* " \ / < > : | ? # ^ [ ]`) with spaces.

## The link

Onyx writes the link in the format your app.json asks for:

- **`useMarkdownLinks`** is false by default, which gives wikilinks such as `![[photo.png]]`. When it's true, you get Markdown links such as `![](photo.png)`, with spaces encoded as `%20`.
- **`newLinkFormat`** controls the path in the link:
  - `shortest` is the default. It uses just the file name when that name is unique in the vault, and the full vault path otherwise.
  - `relative` uses a path relative to the note.
  - `absolute` uses the path from the vault root.

The file type decides between an embed and a link, as in Obsidian:

- Images, audio, video, PDFs, canvases, and bases are embedded with `!`.
- Notes and other files, such as `.zip` or `.docx`, get a plain link: `[[Other Note]]` or `[[archive.zip]]`.

Every drop or paste is a single edit, so ⌘Z takes it back out of the note. The copied file stays in the vault.

## In the reader

New attachments are indexed right away, so they render as soon as you switch to the reader. Images, audio, video, and PDFs show inline. Markdown image embeds (`![](…)`) now resolve the way Obsidian resolves them:

1. relative to the note,
2. then from the vault root,
3. then by name anywhere in the vault.

This means `shortest` and `absolute` Markdown links display correctly from notes in subfolders.

## Limits

- Dropped folders are skipped. Only files are added.
- There's no Onyx-side setting. Change the behavior in Obsidian's Files and links settings, or edit `.obsidian/app.json`.
- Moving the original in Finder by holding ⌘ isn't supported. Outside files are always copied.
