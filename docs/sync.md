# Sync

## Git, continuously

If the vault is a git repository and `git` is installed, Onyx uses it without being asked. It commits a moment after you stop typing (the message names the notes), and immediately on delete, rename, move, switching notes, or quit. It pulls with `--rebase` on launch, on focus, before each push, and every 30 seconds, then pushes. It never force-pushes and never rewrites published history. On a rebase conflict, your version keeps the path and the incoming one is saved beside it as `Note (conflict YYYY-MM-DD HHMM).md`; both are committed. Anything unexpected aborts the rebase and leaves your branch as it was.

A tiny footer glyph shows synced, syncing, offline, local-only, or conflict. Click it, run Show Sync Log from the command palette, or press Show Log in Settings ▸ Sync, for a panel of recent git and Obsidian Sync activity, with timestamps, the kind of event, and a short detail. Errors and conflicts are marked. The last 500 events are kept, and the same log is saved as a plain-text file in Application Support so it survives relaunch. Copy and Reveal in Finder are in the panel header; Esc closes it.

To leave git alone for a session while developing, see [DEVELOP.md](DEVELOP.md) (`ONYX_NO_GIT`).

## Version history

The git sidebar (Source Control, <kbd>⇧⌘Y</kbd>, or Version History in the command palette) opens on a History tab when a note is open (Status otherwise). It lists commits that touched the file (`git log --follow`), with the date, author, and message. Choose one to see a rendered, reader-style diff against the current text (including unsaved edits): insertions highlighted, deletions struck through, word-level where practical, and whole-block for tables, code, and mermaid. A raw line diff and a full preview of that version are also there. Restore this version puts the old text in the editor as an unsaved edit after a confirmation; it never runs `git reset` or `git checkout` on the repository. If the vault is not a git repository, the pane says so and stays quiet.


## Obsidian Sync, optional

Off by default, and opt-in per vault. In Settings ▸ Sync, sign in to your Obsidian account (2FA is supported), pick a remote vault, enter its encryption password, preview what the first sync will do, then connect. Onyx speaks Obsidian’s end-to-end encrypted protocol and merges Markdown the way Obsidian does. Credentials live in the macOS Keychain; the sign-in token is not read until you actually use Sync, so a rebuild should not prompt you for the keychain unless Sync is connected.

Safety rails: the first sync never deletes on either side, and differing files are kept twice. A mass deletion or an empty-looking vault folder pauses for confirmation instead of propagating. Local deletions go to the Trash; overwritten Markdown is backed up first.

This is unofficial and still new. Try it on a throwaway vault before pointing it at the real one. If you’d rather not use it, Obsidian’s official [`obsidian-headless`](https://www.npmjs.com/package/obsidian-headless) CLI (`npx obsidian-headless`) can keep a folder in sync while Onyx simply edits the files. Protocol notes are in [obsidian-sync-protocol.md](obsidian-sync-protocol.md). To leave Sync alone for a session, see [DEVELOP.md](DEVELOP.md) (`ONYX_NO_SYNC`).

The Sync Log also records Obsidian Sync: connected and disconnected, files downloaded or uploaded, conflicts, and errors. Settings ▸ Sync has a Show Log button in both the Git and Obsidian Sync sections; it closes Settings so the panel is visible.

See also [compatibility and privacy](compatibility.md).
