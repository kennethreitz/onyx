# Onyx URLs

Onyx registers the `onyx://` URL scheme, so a link, Shortcut, Alfred workflow, or `open` command can jump to a vault or a note. The actions and parameters follow [Obsidian's URI scheme](https://help.obsidian.md/Extending+Obsidian/Obsidian+URI): rewrite `obsidian://` to `onyx://` and the same link works.

The web clipper's `onyx://clip` is documented in [Web clipper](web-clipper.md#the-onyxclip-url).

Values must be percent-encoded (` ` → `%20`, `/` → `%2F`, `#` → `%23`). "Copy Onyx URL" does this for you.

## Open a note

```
onyx://open?vault=My%20Vault
onyx://open?vault=My%20Vault&file=folder%2FNote
onyx://open?vault=My%20Vault&file=Note.md%23Heading
onyx://open?path=%2FUsers%2Fme%2FNotes%2Ffolder%2FNote.md
```

- `vault` is the folder name or an Obsidian vault id. If it is omitted, the current vault is used. Onyx looks the name up among the current vault, recently opened vaults, sync-only vaults, and vaults listed in Obsidian's `obsidian.json`.
- `file` is a path from the vault root, or a note name. The `.md` extension can be left off. A heading or block id belongs in `file` as `#Heading` or `#^id` (written `%23` so it is not a URL fragment). `file=Note#Heading` also works.
- `path` is an absolute filesystem path. It overrides `vault` and `file`: Onyx picks the most specific known vault that contains that path, and the remainder becomes `file`.
- The file must already exist; `open` does not create it.
- The shorthand `onyx://vault/My%20Vault/folder/Note` is the same as `open` with that vault and file. `onyx://vault/My%20Vault` just opens the vault.

The link opens in the existing Onyx window (or launches Onyx to that vault, if it was not running).

## Search

```
onyx://search?vault=My%20Vault
onyx://search?vault=My%20Vault&query=tag%3Afoo
```

Opens Search in the sidebar, with `query` filled in when it is present.

## Create a note

```
onyx://new?vault=My%20Vault&name=My%20note
onyx://new?vault=My%20Vault&file=folder%2FMy%20note&content=Hello
onyx://new?vault=My%20Vault&file=My%20note&append=true&heading=Tasks&content=Buy%20milk
```

- `name` creates the note in the default new-note folder. `file` is a vault-root path (and overrides `name`). `path` is an absolute path, as in `open`.
- `content` is the note body. `clipboard=true` uses the clipboard instead.
- If the file already exists it is opened and left unchanged, unless you pass `append`, `prepend`, or `overwrite`.
- `overwrite=true` replaces the file, but only when neither `append` nor `prepend` is set.
- `append` / `prepend` merge `content` into the existing note. `heading` limits that merge to the section under that heading. `spacing` is `auto` (a blank line, the default), `newline`, or `inline`.
- `silent=true` writes the file without opening it.

## Daily note

```
onyx://daily?vault=My%20Vault
onyx://daily?vault=My%20Vault&append=true&heading=Log&content=Called%20Sam
```

Opens today's daily note, creating it from the vault's template if needed. The same parameters as `new` are accepted.

## Other forms

`onyx:///open?…` and `onyx://x-callback-url/open?…` work too, matching the clipper.

## Copy Onyx URL

Command Palette ▸ Copy Onyx URL copies an `onyx://open?…` link for the current note. In the File menu and a note's context menu the command is hidden behind the Option key: it swaps in for Copy File Path while Option is held, the same way Open in Obsidian swaps in for Reveal in Finder.

## Links in notes

An `obsidian://` or `onyx://` link clicked in a note is handled inside Onyx. Onyx does not register the `obsidian://` scheme, so a click outside the app still goes to Obsidian.
