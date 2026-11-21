# Compatibility and privacy

## Installing

The latest build is on the [releases page](https://github.com/kennethreitz/onyx/releases/latest). Unzip it and drag `Onyx.app` to `/Applications`.

This build is not notarized, so macOS will block the first launch. Open Onyx once, then go to System Settings ▸ Privacy & Security, scroll to Security, and click **Open Anyway** next to “Onyx was blocked…”. Confirm when asked. You can also right-click `Onyx.app` and choose **Open**, or clear quarantine from Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Onyx.app
```

Starting with v0.1.1, Onyx checks GitHub for a newer release when it launches and every six hours. There’s also a **Check for Updates…** menu item, and you can turn the checks off in Settings. v0.1.0 has to be updated by hand; after that, updates install in place and relaunch on their own. It updates itself from v0.1.1 on.

## Requirements

macOS 14 (Sonoma) or later, Apple silicon or Intel. The official download is a universal binary.

## Obsidian compatibility

Onyx is built to open an Obsidian vault without converting anything. It understands wikilinks (aliases, headings, embeds), frontmatter, nested tags, folder notes, `%%comments%%`, callouts, footnotes, and Mermaid. It reads a few things out of `.obsidian`: the daily-notes folder, default view mode, user ignore filters, bookmarks, and the Homepage plugin’s start note. Rename and move rewrite wikilinks and standard Markdown links and embeds. Kanban boards, `.canvas` files, and `.base` files open in place.

It is not a plugin host, and it does not implement Templates or Excalidraw. [Bases](bases.md) are supported for viewing (read-only). You can keep using Obsidian for the rest, and “Open in Obsidian” is one click away.

Early days, moving fast. It is tested against a real vault of a few thousand notes, but expect rough edges. Back up your vault — or point Onyx at a copy — while it settles.

## Privacy

Your notes live in a folder you choose. Onyx does not require an account and does not phone home. The only network it uses, and only if you ask it to, is:

- **Git**, to the remotes already configured on that vault.
- **Obsidian Sync**, if you connect a vault under Settings. Tokens and encryption keys stay in the Keychain; file contents are encrypted with Obsidian’s protocol before they leave the machine. Sync hosts are limited to `*.obsidian.md`.

Starting with v0.1.1, the auto-updater also talks to GitHub, and only to check for (and download) a newer release.

Building from source? See [DEVELOP.md](DEVELOP.md).
