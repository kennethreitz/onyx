# Attachments: drag, drop, paste, and open

Drop files into the editor, or paste them, and Onyx adds them to the vault the way Obsidian does. Each file is copied into your attachment folder, and a link goes in at the drop point or the caret. Click an attachment and it opens in the pane, in a viewer made for its type ([Opening attachments](#opening-attachments)).

## What you can drop or paste

- **Files from Finder.** Any type, and several at once. Each one is copied in under its own name, and the links go in one per line.
- **Images from a browser, Photos, Mail, or Preview.** When the app hands over the original file, it keeps its name and format. When it only hands over pixels, Onyx saves a PNG named `Pasted image YYYYMMDDHHmmss.png`.
- **An image on the clipboard.** Use ⌘V after Copy Image or a screenshot to the clipboard (⌃⇧⌘4). It becomes `Pasted image ….png`. Copied rich text that happens to include a picture still pastes as text.
- **Files copied in Finder.** Copy them with ⌘C, then paste with ⌘V in the editor.
- **Files already in the vault.** Use ⌘-drag from the sidebar, or drag from Finder a file that lives inside the vault. These files are linked where they are, not copied.

Dragging text, or a plain web link, still works as ordinary text.

## Where files go

Onyx reads **Default location for new attachments** (`attachmentFolderPath` in `.obsidian/app.json`). You can change it in Onyx under Settings ▸ Files & Links, or in Obsidian under Settings ▸ Files and links. Both apps write the same file ([Obsidian settings](obsidian-settings.md)).

| Setting | Files land in |
| --- | --- |
| unset, or `/` (Obsidian's default) | the vault root |
| `./` | the same folder as the note |
| `./assets` | a subfolder of the note's folder (created if needed) |
| `Attachments` | that folder in the vault (created if needed) |

When a name is taken, Onyx adds a number before the extension, as Obsidian does: `photo.png`, then `photo 1.png`, then `photo 2.png`. Onyx also replaces characters Obsidian doesn't allow in file names (`* " \ / < > : | ? # ^ [ ]`) with spaces.

## The link

Onyx writes the link in the format your app.json asks for. **New link format** and **Use [[Wikilinks]]** are in Settings ▸ Files & Links.

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

## Opening attachments

Any file in the vault that isn't a note, canvas, or base opens in the pane, the way a note does. It takes the place of the note in that pane, joins back/forward history and Recent, and ⌘[ (or the back chevron in the file's header) returns you to the note. You can open an attachment:

- from the reader: click a `[[file]]` link, a Markdown `[text](file)` link, an embedded image, or the "name ↗" link on an audio, video, or PDF embed;
- from the editor: ⌘-click `[[file]]`, `![[file]]`, `[text](file)`, or `![](file)`;
- from the sidebar, Recent, a canvas file card, or a base row;
- from the quick switcher (⌘O), which lists attachments by their full file name, such as `photo.png`. They show up in `[[` suggestions too.

Every file view has a header with the file's kind, size, and details (pixel dimensions, page count, or duration), a menu of the notes that link to it, **Open in Default App**, and **Reveal in Finder**. Onyx never writes to an attachment it shows.

| Type | Extensions | What you get |
| --- | --- | --- |
| Audio | m4a, mp3, aac, wav, aiff, caf, flac, 3gp (ogg and opus only if macOS can play them) | Onyx's player: a waveform you click or drag to seek, elapsed and remaining time, play/pause (Space), skip back and forward 15 s (← →), speed 0.75×–2× (click to cycle, or pick from its menu; remembered, with pitch kept), and volume. When Record Audio left a `> [!transcript]` callout under the file's embed, the transcript shows under the player, with a link to its note. Playback stops when you leave the file. |
| Images | png, jpg, gif, webp, svg, avif, heic, bmp, tiff, ico | Fit to the pane (never enlarged past 100%), zoom in and out from the header or with a pinch, actual size, drag to pan, and double-click to switch between fit and 100%. GIFs animate. |
| PDF | pdf | PDFKit, continuous pages. The header has page n / N with previous and next, zoom, fit width, and a find field (↩ for the next match, ⇧↩ for the previous one; every hit is highlighted). |
| Video | mp4, m4v, mov (webm, mkv, ogv, avi if macOS can play them) | AVKit's player, with full screen. |
| Anything else | | A file card with the icon, type, size, and modified date, plus Open in Default App and Reveal in Finder. |

A file that can't be shown, such as an Ogg file AVFoundation won't play or an image NSImage can't decode, falls back to the file card with a short note.

### Embeds in the reader

An audio embed (`![[clip.m4a]]` or `![](clip.m4a)`) is a quiet one-line player that uses the chrome's scales: an 8 pt card radius, an ink-wash play button, and a hairline track you click to seek. The time sits next to the file name, and the name opens the full player. Starting one embed pauses the others. Video and PDF embeds play or show inline, with a "name ↗" link under them to their viewer. Clicking an embedded image opens it in the image viewer.

## Image size

Sizes follow Obsidian's syntax. The last `|` part of the embed is the size when it reads `W` or `WxH`, in CSS pixels:

| You write | You get |
| --- | --- |
| `![[photo.png\|300]]` | 300 px wide, height in proportion |
| `![[photo.png\|300x200]]` | 300 × 200 (fitted inside that box, never stretched) |
| `![[photo.png\|A caption\|300]]` | 300 px wide, with "A caption" as its alt text |
| `![300](photo.png)` or `![A caption\|300](https://…/photo.jpg)` | the same for Markdown images, local or remote |
| `![[clip.mp4\|480]]` or `![480](clip.mp4)` | a 480 px wide video embed |

An image is never drawn wider than the text column, whatever its size says. Text after `|` that isn't a size, such as `![[photo.png|Doug]]`, is alt text, as before. A sized image sits inline in its paragraph, the way Obsidian shows it.

### Drag to resize

In the reader, hover an embedded image and a small corner grip appears at its bottom-right. Drag it to resize. The aspect ratio is kept, a label shows the width as you go, and the image can't grow past the column or shrink below 32 px. When you let go, Onyx writes the width into that embed in the note: `![[photo.png]]` becomes `![[photo.png|412]]`, `![[photo.png|300x200]]` becomes `![[photo.png|412]]`, and `![alt](photo.png)` becomes `![alt|412](photo.png)`. Alt text and `#heading` parts are kept. Double-click the grip to go back to the natural size, which removes the size.

Only the embed you dragged changes. When the same image appears several times, Onyx finds the right one by its block's source line and its position among that image's embeds in the block. Inside a table, the `|` is written as `\|` so the cell stays whole. The edit saves through the normal save path (git and Obsidian Sync see it). When the editor holds the note, it's one undo step, so ⌘Z in the editor takes it back.

A click on the image without dragging still opens it in the image viewer. Grips appear only in the focused pane, never in a hover preview, an unfocused split, an embedded note, a dataview result, or a canvas card. Those images belong to another note or are generated.

## Limits

- Height-only sizes (`x200`) aren't an Obsidian form, so they're read as alt text. Dragging always writes a width only.
- Images in footnotes (sidenotes) and in embedded notes can't be drag-resized. Edit their size in the source.
- The editor shows embeds as text, so sizes apply in the reader only.

- Transcripts have no timestamps (Record Audio writes plain paragraphs), so you can't click a sentence to seek to it.
- The audio waveform is skipped for files over three hours, which show a plain track instead.
- Split panes each have their own viewer. A file view in an unfocused pane doesn't take the audio keys.
- Dropped folders are skipped. Only files are added.
- There's no Onyx-side setting. Change the behavior in Obsidian's Files and links settings, or edit `.obsidian/app.json`.
- Moving the original in Finder by holding ⌘ isn't supported. Outside files are always copied.
