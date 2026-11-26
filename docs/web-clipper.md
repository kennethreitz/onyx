# Web clipper

Onyx saves web pages into your vault as clean Markdown notes, the way Obsidian Web Clipper does: readable text only (no menus, ads or comments), frontmatter with the source, images linked to where they live on the web (nothing is downloaded), and the note filed in a Clippings folder.

There are three ways to clip: the Safari extension (or the Share menu), a bookmarklet for any browser, and Clip Web Page… inside Onyx.

## In Safari: the Clip to Onyx extension

Onyx.app carries a Safari Web Extension (and a Share menu item). Nothing to download:

1. Open Onyx once (any build from 0.1.18 on). macOS registers the extension when the app is launched.
2. Safari ▸ Settings ▸ **Extensions** ▸ turn on **Clip to Onyx**. Settings ▸ Files & Links ▸ Web Clipper ▸ **Safari Extension…** in Onyx jumps there.
3. Click the **Clip to Onyx** toolbar button (Safari asks once to let it read the page you're on), or right-click a page, a selection, or a link: **Clip Page to Onyx**, **Clip Selection to Onyx**, **Clip Link to Onyx**. ⌃⇧O (Control-Shift-O) does the same as the toolbar button; Safari ▸ Settings ▸ Extensions can change it.

It sends the same thing as the bookmarklet: the page's URL, title, and metadata, plus your selection if there is one. The extension's native half opens `onyx://clip` itself, so there is no "allow this page to open Onyx?" prompt and no URL-length worry for selections. If that fails it falls back to opening the `onyx://` link in the tab.

**Share menu:** Safari's Share button (and any app that shares a link or text) also lists **Onyx**. A shared link is fetched and clipped; shared text is saved as is.

### Signing: why the extension may not show up

Safari only lists extensions from apps signed by an Apple-issued certificate. Onyx is normally signed with the self-signed "Onyx Local Signing" identity (or ad hoc), which Safari counts as **unsigned**:

- **Without an Apple certificate:** turn on Safari ▸ Settings ▸ Advanced ▸ *Show features for web developers*, then Safari ▸ Settings ▸ Developer ▸ **Allow unsigned extensions** (asks for your password). Safari turns that off every time it quits, so the extension disappears on the next launch until you allow it again. The Share menu item doesn't depend on this.
- **With a free Apple ID (Personal Team) or a paid account:** in Xcode ▸ Settings ▸ Accounts, select your Apple ID ▸ Manage Certificates… ▸ **+ ▸ Apple Development**. `make app`, `make install`, and `make release` (`scripts/bundle.sh`) already prefer an "Apple Development" or "Developer ID Application" identity over Onyx Local Signing, so the next build is signed with it, and Safari keeps Clip to Onyx enabled across restarts with no developer setting. (Changing identity once makes Keychain ask again for Onyx's saved passwords.)
- Distributing a signed extension to *other* people's Macs needs Developer ID signing plus notarization (paid Apple Developer Program); Safari 18.4+ loads those.

## From any browser: the bookmarklet

1. Open Settings ▸ Files & Links ▸ **Web Clipper** and click **Copy Bookmarklet**.
2. In Safari, Chrome, Arc, or Firefox, show the bookmarks bar, add a bookmark of any page, and edit it: name it *Clip to Onyx* and paste the copied text as its **address** (URL).
3. On any page, click **Clip to Onyx**. The first time, the browser asks whether the page may open Onyx; allow it (Chrome can remember this).

- With **nothing selected**, Onyx loads the page itself and keeps just the article (Mozilla's Readability, the engine behind Firefox Reader View).
- With **text selected**, only the selection is clipped, exactly as you see it in the browser, so this also works for pages behind a login or a paywall you can read.

If you'd rather paste it by hand, this is the bookmarklet (one line):

```
javascript:(()=%3E%7Bconst%20m=(...n)=%3E%7Bfor(const%20k%20of%20n)%7Bconst%20e=document.querySelector(%60meta%5Bname=%22$%7Bk%7D%22%5D,meta%5Bproperty=%22$%7Bk%7D%22%5D,meta%5Bitemprop=%22$%7Bk%7D%22%5D%60);if(e&&e.content)return%20e.content.trim()%7Dreturn''%7D;const%20p=new%20URLSearchParams();p.set('url',location.href);p.set('title',m('og:title')%7C%7Cdocument.title);const%20a=m('author','article:author','parsely-author','sailthru.author');if(a&&!/%5Ehttps?:/.test(a))p.set('author',a);const%20d=m('description','og:description');if(d)p.set('description',d);const%20t=m('article:published_time','datePublished','date','parsely-pub-date');if(t)p.set('published',t);const%20s=m('og:site_name');if(s)p.set('site',s);const%20g=getSelection();if(g&&g.rangeCount&&!g.isCollapsed)%7Bconst%20w=document.createElement('div');for(let%20i=0;i%3Cg.rangeCount;i%2B%2B)w.appendChild(g.getRangeAt(i).cloneContents());w.querySelectorAll('img').forEach(i=%3E%7Bif(i.currentSrc)i.setAttribute('src',i.currentSrc)%7D);w.querySelectorAll('%5Bsrc%5D,%5Bhref%5D').forEach(e=%3E%7B%5B'src','href'%5D.forEach(k=%3E%7Bif(e.hasAttribute(k))try%7Be.setAttribute(k,new%20URL(e.getAttribute(k),location.href).href)%7Dcatch(_)%7B%7D%7D)%7D);p.set('selection',new%20XMLSerializer().serializeToString(w))%7Dlocation.href='onyx://clip?'%2Bp.toString().replace(/%5C%2B/g,'%2520')%7D)()
```

## From inside Onyx: Clip Web Page…

File ▸ **Clip Web Page…** (<kbd>⇧⌘K</kbd>, also in the command palette) asks for a URL, prefilled with one from the clipboard. Onyx fetches the page in an offscreen web view with no cookies or storage, extracts the article, and saves it.

## What a clipping looks like

Clippings go to `Clippings/` by default, named after the page title (`:` becomes ` -`, other characters Obsidian refuses are dropped). With the built-in template:

```markdown
---
title: "Anthropic acquires Stainless"
source: "https://www.anthropic.com/news/anthropic-acquires-stainless"
author: ["Jane Doe"]
published: 2026-05-17
created: 2026-11-25
description: "…"
site: "Anthropic"
tags: [clippings]
class: Source
---

# Anthropic acquires Stainless

The article, as Markdown…
```

- **class** and **tags** follow the clippings already in that folder (the most common `class:` and `tags:`, folder indexes ignored), so a new clipping matches the rest of your collection. With an empty folder they are `Source` and `clippings`. Set either in Settings to override.
- **Images** are hotlinked, not downloaded: each becomes `![alt](https://…)` pointing at the image on the web, so clipping adds nothing to your attachment folder. Onyx picks the largest candidate from `srcset` (and a `<picture>`'s `<source>`s), reads lazy-loaded images from `data-src`, `data-srcset`, `data-original` and similar, and makes relative and protocol-relative (`//cdn…`) addresses absolute. Inline `data:` images, `blob:` addresses, and tracking pixels (1–2 px images and known analytics beacons) are left out. If the site later removes or blocks an image, the note shows a broken image.
- The Markdown keeps headings, bold and italic, links (made absolute), nested and numbered lists, task lists, block quotes, fenced code with its language, tables, highlights, strikethrough, figure captions, and YouTube embeds. `$`, `*`, `_`, `[` and the like in the text are escaped so they stay literal.
- The note opens when it's saved, and Onyx comes to the front. With git sync on, the clipping is committed right away.

## Settings

Settings ▸ Files & Links ▸ Web Clipper (stored in Onyx's preferences, not the vault):

| Setting | Default |
| --- | --- |
| Clippings folder | `Clippings` |
| Class | match the folder, else `Source` |
| Tags | match the folder, else `clippings` |
| Template note | built-in |

A **template note** is any note in the vault (path with or without `.md`). Onyx replaces `{{title}}`, `{{url}}` (or `{{source}}`), `{{author}}`, `{{published}}`, `{{date}}` (or `{{created}}`, `YYYY-MM-DD`), `{{time}}` (`HH:mm`), `{{description}}`, `{{site}}`, `{{tags}}` (comma-separated), `{{class}}` and `{{content}}`. Values are inserted as is; quote them in YAML yourself if a title might contain `:`. Without `{{content}}` the article is appended after the template.

## The onyx://clip URL

`clip` is one action on the `onyx://` scheme; [Onyx URLs](uri.md) documents `open`, `search`, `new`, and `daily`.


The bookmarklet opens `onyx://clip?…`, and anything else can too (Shortcuts, Alfred, Raycast, a script):

```sh
open "onyx://clip?url=https%3A%2F%2Fexample.com%2Fpost"
```

| Parameter | |
| --- | --- |
| `url` | The page. Alone, Onyx fetches and extracts it. |
| `title` | Note title (default: the page's). |
| `selection` | HTML to clip instead of fetching the page. |
| `text` | Plain Markdown/text to clip instead. |
| `author`, `description`, `published`, `site` | Metadata, used when the page doesn't provide it. |
| `folder` | Vault folder for this clipping, overriding the setting. |

Values are percent-encoded. A clip sent while Onyx is closed opens Onyx and waits for the vault. Clips arriving together are saved one after another.

## Limits

- Pages that need a login or are built entirely by scripts can come out empty or partial from the URL path, because Onyx fetches them without your browser's cookies. Select the text and use the bookmarklet instead.
- A very large selection makes a very long `onyx://` URL; browsers handle a few megabytes, but a whole book chapter may be refused. Clip the page without a selection, or in parts.
- PDFs and other non-HTML URLs aren't clipped. Download the file and drop it into a note instead.
- Videos other than YouTube, iframes, forms, and comments are left out. Math rendered as images stays an image.
- Readability sometimes misjudges a page (a front page, a forum thread). Select what you want and clip the selection.
- The Safari extension shows up without the developer setting only when Onyx is signed with an Apple certificate (see *Signing* above).
- Chrome, Arc, and Firefox have no bundled extension; use the bookmarklet there.

## Credits

Article extraction uses [Readability.js](https://github.com/mozilla/readability) 0.6.0 by Mozilla and Arc90, under the Apache License 2.0 (`Resources/web/clipper/LICENSE-Readability.md`).
