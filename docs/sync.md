# Sync

## Git, continuously

If the vault is a git repository and `git` is installed, Onyx uses it without being asked. It commits a moment after you stop typing, and immediately on delete, rename, move, switching notes, or quit. The message is generated on-device from the staged diff — note titles, headings, tasks, frontmatter, and links — and stays at most 72 characters on the subject line (a body lists per-file details when more than one note changed). The Source Control commit box is prefilled with the same kind of message, which you can edit. It pulls with `--rebase` on launch, on focus, before each push, and every 30 seconds, then pushes. It never force-pushes and never rewrites published history. On a rebase conflict, your version keeps the path and the incoming one is saved beside it as `Note (conflict YYYY-MM-DD HHMM).md`; both are committed. Anything unexpected aborts the rebase and leaves your branch as it was.

A tiny footer glyph shows synced, syncing, offline, local-only, or conflict. Click it, run Show Sync Log from the command palette, or press Show Log in Settings ▸ Sync, for a panel of recent git and Obsidian Sync activity, with timestamps, the kind of event, and a short detail. Errors and conflicts are marked. The last 500 events are kept, and the same log is saved as a plain-text file in Application Support so it survives relaunch. Copy and Reveal in Finder are in the panel header; Esc closes it.

To leave git alone for a session while developing, see [DEVELOP.md](DEVELOP.md) (`ONYX_NO_GIT`).

## Version history

The git sidebar (Source Control, <kbd>⇧⌘Y</kbd>, or Version History in the command palette) opens on a History tab when a note is open (Status otherwise). It lists commits that touched the file (`git log --follow`), with the date, author, and message. Opening the tab selects the most recent commit that touched the note. The revision sheet defaults to Compare with latest (that commit vs the current text, including unsaved edits); vs previous shows what the commit changed against the next-older version, and the last-chosen mode is remembered. The rendered, reader-style diff highlights insertions and strikes through deletions, word-level where practical, and whole-block for tables, code, and mermaid. Long unchanged stretches collapse and can be expanded. A raw line diff (full width, with a line-number gutter) and a full preview of that version are also there. Restore this version puts the old text in the editor as an unsaved edit after a confirmation; it never runs `git reset` or `git checkout` on the repository. If the vault is not a git repository, the pane says so and stays quiet.


## Obsidian Sync, optional

Off by default, and opt-in per vault. In Settings ▸ Sync, sign in to your Obsidian account (2FA is supported), pick a remote vault, enter its encryption password, preview what the first sync will do, then connect. Onyx speaks Obsidian’s end-to-end encrypted protocol and merges Markdown the way Obsidian does. Credentials live in the macOS Keychain; the sign-in token is not read until you actually use Sync, so a rebuild should not prompt you for the keychain unless Sync is connected.

Signing in is safe to repeat. Onyx sends Obsidian's API no cookies (like the official CLI), reuses a token it already holds if the server still accepts it, signs out and clears a stale one, and retries "Already logged in" once. If the Keychain refuses the token after the server said yes, Onyx keeps it for the session. A build that can't use the Keychain at all (errSecMissingEntitlement, as in an unsigned simulator build) stores it in an owner-only, data-protected file under `Application Support/Onyx/Secrets` instead. Error messages are plain sentences; the underlying details are logged under subsystem `org.kennethreitz.onyx`, category `sync` (Console.app, or `log stream --predicate 'subsystem == "org.kennethreitz.onyx"'`).

Safety rails: the first sync never deletes on either side, and differing files are kept twice. A mass deletion or an empty-looking vault folder pauses for confirmation instead of propagating. Local deletions go to the Trash; overwritten Markdown is backed up first.

This is unofficial and still new. Try it on a throwaway vault before pointing it at the real one. If you’d rather not use it, Obsidian’s official [`obsidian-headless`](https://www.npmjs.com/package/obsidian-headless) CLI (`npx obsidian-headless`) can keep a folder in sync while Onyx simply edits the files. Protocol notes are in [obsidian-sync-protocol.md](obsidian-sync-protocol.md). To leave Sync alone for a session, see [DEVELOP.md](DEVELOP.md) (`ONYX_NO_SYNC`).

### Sync-only vaults

You don’t need a folder of your own to sync. **Connect Obsidian Sync Vault…** (on the welcome screen, in the File menu, and as **Sync-only Vault…** next to Settings ▸ General ▸ Vault ▸ Choose…) signs in, lists your remote vaults, asks for the vault’s end-to-end password when it has one, and creates a local copy that Onyx owns: `~/Library/Application Support/Onyx/Vaults/<vault name>` on the Mac, the app’s own container on iPhone and iPad. Onyx then downloads everything and keeps the copy synced while it’s open; the footer badge shows the status.

- Each sync-only vault is listed under Settings ▸ General ▸ Vault (and on the welcome screen) with Open, Reveal in Finder, and Delete Local Copy…. **Show Vaults Folder in Finder** opens the folder that holds them.
- **Disconnect…** (Settings ▸ Sync) stops syncing but keeps the local copy, still listed, so you can reconnect later. Connecting the same remote vault again reuses that copy and runs a careful first sync again: nothing is deleted on either side, and differing files are kept twice.
- **Delete Local Copy…** asks first, closes the vault if it’s open, and then deletes only this device’s copy, its sync state, its backups, and its key. The vault in Obsidian Sync and your other devices keep everything. Onyx refuses to delete anything that isn’t a sync-only folder it created inside the Vaults folder.
- Sync state for a sync-only vault is keyed by the remote vault id (`Application Support/Onyx/Sync/vault-<id>.json`), so an iOS container path changing after an update doesn’t lose it. Folders you picked yourself are keyed by path as before.

The library and its safety checks live in OnyxCore (`SyncVaultLibrary`), and the connect, disconnect, and delete flow in OnyxSync (`SyncOnlyVaults`). Both are tested against the in-process fake Obsidian Sync server.

The Sync Log also records Obsidian Sync: connected and disconnected, files downloaded or uploaded, conflicts, and errors. Settings ▸ Sync has a Show Log button in both the Git and Obsidian Sync sections; it closes Settings so the panel is visible.

See also [compatibility and privacy](compatibility.md).
