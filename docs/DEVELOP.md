# Developing Onyx

This is the technical guide: building, architecture, test hooks, signing, and releases. The user-facing guide is [README.md](README.md). Design notes live in [DESIGN.md](DESIGN.md).

## Building from Terminal

Requires macOS 14+ and Swift 5.10 (Xcode 15.3 or newer). There is no Xcode project: it is a Swift package, built from Terminal.

```sh
make run                       # build Onyx.app and open your vault
make run VAULT=~/path/to/vault # any folder of Markdown; does not change the remembered vault
make run-test                  # the disposable test copy (/tmp/onyx-vault), never ~/Notes
make app                       # native Onyx.app in build/ (this machine’s architecture; fast)
make release                   # universal (arm64 + x86_64) Onyx.app, plus the GitHub zip
UNIVERSAL=1 make app           # universal app, no zip
make test                      # Swift tests, then the reader tests
swift run -c release onyx-bench /tmp/vault-copy   # timings against a vault copy (docs/performance.md)
make install                   # universal Onyx.app into /Applications (quits a running Onyx first)
make install ONE_ARCH=1        # this machine's architecture only (faster); also `make install-native`
make install ARCH=arm64        # one slice (arm64 or x86_64)
make install INSTALL_DIR=~/Applications RELAUNCH=1   # elsewhere; RELAUNCH reopens it if it was running
make uninstall                 # remove $(INSTALL_DIR)/Onyx.app
make dev                       # debug binary, pointed at a test vault
make open                      # open the built app on the remembered vault
make demo-vault                # a disposable copy under /tmp/onyx-vault
make clean                     # remove .build and build/
```

`make install` is the same universal `Onyx.app` as `make release`, without the zip. It asks a running Onyx to quit first only when the target is the real `/Applications` (never `kill -9`; `NO_QUIT=1` skips this), copies the bundle with `ditto` so the code signature is kept, and swaps it in beside the old app. `INSTALL_DIR` and `DESTDIR` stage or install elsewhere (a path other than `/Applications` never quits the running app). `RELAUNCH=1` reopens Onyx if it was running. `make uninstall` removes `$(INSTALL_DIR)/Onyx.app`.

`make install ONE_ARCH=1` or `make install-native` is the same install path, but builds only this machine's architecture (`uname -m`) in release config. `ARCH=arm64` or `ARCH=x86_64` selects the slice (`make install ARCH=x86_64`, or together with `ONE_ARCH=1`). Make cannot pass `--one-arch` as a flag, so these are variables and an alias target.

With no `--vault`, Onyx opens the last vault you chose, or `~/Notes` if that folder exists. A vault in `/tmp` is never remembered, so test copies don’t stick. `ONYX_NO_DEFAULT_VAULT=1` skips the fallback entirely (used by `make run-test` and `make dev`). `--vault` never overwrites the remembered vault.

**Never write test files into `~/Notes`.** Point the app at a copy under `/tmp`. `make demo-vault` builds `/tmp/onyx-vault` from the neutral parts of a real vault (read-only on the source). Prefer a git worktree so you don’t overwrite a running `build/Onyx.app` someone is using.

### One running Onyx

Closing the last window leaves the process running (`applicationShouldTerminateAfterLastWindowClosed` is false); ⌘Q and a second packaged Onyx still quit through `willTerminate`. Launching a second packaged Onyx (same bundle identifier, `org.kennethreitz.onyx`) asks the copy that's already running to quit first. That copy saves unsaved notes and session state through the normal `willTerminate` path (`flushSave`, the split layout, and git's finish-for-quit), then exits. The new copy waits up to 10 seconds so those writes land before it restores the window and vault, and it never force-kills the old one: if the wait times out (git quit can take up to 8 seconds, or a note may still be saving), both may briefly run.

**Test, screenshot, and harness launches must not quit a running Onyx someone is using.** Set `ONYX_ALLOW_MULTIPLE=1` to skip the takeover, or turn on the hidden default `onyx.allowMultipleInstances`. `make run-test`, `make dev`, and `scripts/shoot.sh` set `ONYX_ALLOW_MULTIPLE=1` automatically. The same skip also happens when any of the usual test hooks are set (`ONYX_NO_DEFAULT_VAULT`, `ONYX_SHOT_QUIET`, `ONYX_TYPE_TEST`, `ONYX_KEY_SELFTEST`, `ONYX_SCROLL_TEST`, `ONYX_OPEN_SETTINGS`, `ONYX_DUMP_MENUS`, `ONYX_BASES_EDIT`). Unpackaged `swift run` / `.build/debug/Onyx` binaries have no bundle identifier and never ask another copy to quit. `onyx-bench` is a separate executable and does not launch `Onyx.app`.

Workers launching a packaged `build/Onyx.app` (or any other copy with that bundle identifier) must set `ONYX_ALLOW_MULTIPLE=1`, or use the Makefile / shoot.sh targets that already do. Do not `open -n` a packaged Onyx without that escape hatch.

To leave git or Obsidian Sync alone for a session:

```sh
ONYX_NO_GIT=1 make run         # don’t auto-commit, pull, or push
ONYX_NO_SYNC=1 make run        # don’t start Obsidian Sync, even if this vault is connected
```

## Architecture

```
Sources/OnyxCore     vault index, parsing, link resolution, Dataview-lite, graph layout, updater
                     canvas, bases, kanban, daily notes
Sources/Onyx         the macOS app (SwiftUI + AppKit, WKWebView reader)
Sources/OnyxSync     Obsidian Sync protocol
Sources/OnyxSyncPOC  a small command-line client for the same protocol
Resources/web        reader.html + reader.js/css (the Reitz LaTeX page) and
                     typeset.js/css (book typography); katex/ (offline math, MIT); canvas.html/js/css for .canvas boards; BasesView for .base files
Tests/               OnyxCore and OnyxSync tests; Tests/reader for the typography
```

The reader is a WKWebView. `reader.js` / `reader.css` render the page; `typeset.js` / `typeset.css` add the book typography (small caps, old-style figures, hyphenation, drop caps, sidenote layout) when Typeset reading is on. Graph layout lives in OnyxCore (`Graph.swift`, `GraphIndex.swift`, `RelationGraph.swift`) and is drawn by `GraphView.swift`. Git autosync is `GitSync.swift`. Auto-update from GitHub Releases is `Updater.swift` (OnyxCore) plus `UpdateUI.swift`. Obsidian Sync is the `OnyxSync` package plus `ObsidianSync.swift`. Protocol notes are in [docs/obsidian-sync-protocol.md](docs/obsidian-sync-protocol.md).

`scripts/bundle.sh` wraps the SwiftPM binary into `build/Onyx.app` and signs it. It first runs `scripts/build-extensions.sh`, which builds the app extensions in `Extensions/` into `Contents/PlugIns` without an Xcode project: `OnyxSafari.appex` (the Clip to Onyx Safari Web Extension: `SafariWebExtensionHandler.swift` plus `manifest.json`, `background.js`, and the committed icons in `Extensions/Safari/Resources/images`, rendered from `Resources/AppIcon.icns` by `swift scripts/make-extension-icons.swift`: the app icon for the manifest, a monochrome crystal-and-graph glyph for the toolbar, which Safari treats as a template) and `OnyxShare.appex` (the Share menu). Each is compiled with `swiftc -e _NSExtensionMain` per architecture (both for `UNIVERSAL=1`) and lipo'd, along with `Sources/OnyxCore/ClipURL.swift`. `SKIP_EXTENSIONS=1` leaves them out. `Tests/extension` (run by `make test`) checks `background.js` against a stub `browser` API.

## Environment variables and test hooks

These are for development and screenshots. Don’t set them in normal use unless you mean to.

| Variable | What it does |
| --- | --- |
| `ONYX_ALLOW_MULTIPLE=1` | Don’t ask another running Onyx to quit at launch. Required for any packaged test or screenshot launch so it cannot close someone’s running app. `make run-test`, `make dev`, and `scripts/shoot.sh` set this. A hidden default, `defaults write org.kennethreitz.onyx onyx.allowMultipleInstances -bool true`, does the same. Usual test hooks also skip the takeover (see above). |
| `ONYX_NO_DEFAULT_VAULT=1` | Don’t fall back to the remembered vault or `~/Notes`. Used by `make run-test` and `make dev`. Also skips asking another Onyx to quit. |
| `ONYX_NO_GIT=1` | Don’t auto-commit, pull, or push for this session. |
| `ONYX_NO_SYNC=1` | Don’t start Obsidian Sync, even if this vault is connected. |
| `ONYX_UPDATE_DISABLE=1` | Don’t check for GitHub updates automatically. Manual **Check for Updates…** still works. Screenshot and self-test hooks also skip automatic checks. |
| `ONYX_UPDATE_API_URL=<url>` | Override the GitHub Releases API endpoint (tests point this at a local fake release). |
| `ONYX_UPDATE_VERSION=<semver>` | Pretend the running app is this version. |
| `ONYX_UPDATE_APP=<path>` | Install the update at this `.app` path instead of the running bundle. Tests use a copy under `/tmp`, never the real app. |
| `ONYX_GIT_INTERVAL=<seconds>` | Git poll interval (default 30; tests use 5 or 600). |
| `ONYX_NO_STARTUP_GRAPH=1` | Skip opening the atlas on startup, even if that setting is on. |
| `ONYX_OPEN_SETTINGS=1` | Open Settings at launch (screenshots / UI checks). |
| `ONYX_SETTINGS_TAB=<name>` | Open a given Settings tab: `general`, `editor`, `shortcuts`, `reading`, `graph`, `sync`, `updates`. Aliases: `typography`, `typesetting`, `atlas`, `advanced`, `keys`, `keyboard`, `hotkeys`. |
| `ONYX_SHOT_QUIET=1` | Park the window off-screen and deaf to the pointer, so a screenshot run doesn’t cover someone’s work or sprout hover cards. Never autosaves or restores that frame (the shot app shares the real app’s defaults). Also skips writing per-vault session state such as the split layout. |
| `ONYX_SYNC_LOG_DEMO=1` | Seed a short demo Sync Log if this vault’s log is empty. For screenshots; use with `ONYX_SHOT_QUIET=1`. |
| `ONYX_SCROLL_TEST=<seconds>` | Scroll every scroll view and the reader in small steps for that long (values `≤ 1` become 4). |
| `ONYX_DUMP_MENUS=1` | Print every menu key equivalent, to catch double bindings. |
| `ONYX_KEY_SELFTEST=1` | Offer each help-sheet shortcut to the view hierarchy with the editor or reader as first responder, to catch a view swallowing it before the menu. |
| `ONYX_DEBUG_KEYS=1` | Log key handling in the root view and switcher. |
| `ONYX_DEBUG=1` | Chrome / link-suggest debug logging to stderr. |
| `ONYX_TYPE_TEST=<script file>` | Type into the editor in-process (the test window can’t become key without stealing focus). See below. |
| `ONYX_PREVIEW_DELAY=<seconds>` | Hover graph-card delay (default 0.4). |
| `ONYX_SWITCHER_QUERY=<text>` | Prefill the quick switcher query. |
| `ONYX_KANBAN_FILE=/tmp/…/Ideas.md` | Optional test: a real board (a copy) must round-trip byte for byte. Skipped if unset. |
| `ONYX_CANVAS_FIXTURES=<folder>` | Optional canvas fixture tests; defaults to `/tmp/onyx-canvas-vault`, skipped when the folder isn’t there. |
| `ONYX_BENCH_VAULT=~/Notes` | Optional read-only smoke check against a real vault: `ONYX_BENCH_VAULT=~/Notes swift test --filter RealVault`. Skipped if unset. Never write to this vault. |
| `ONYX_BASES_VAULT=~/Notes` | Optional read-only check of `.base` files: `ONYX_BASES_VAULT=~/Notes swift test --filter testRealBasesReadOnly`. Skipped if unset. Never write to this vault. |
| `ONYX_UPDATE_LINKS=update` / `skip` | Answer the "Update links?" prompt for scripted rename and move runs in a test vault whose `alwaysUpdateLinks` is off. |
| `ONYX_BASES_EDIT=filter` | Open the Bases filter popover at launch (also `column`, `rename`). For screenshots; use with `ONYX_SHOT_QUIET=1`. Never writes the window frame. |

### Launch arguments

Useful with `open -n build/Onyx.app --args …` or `make run ARGS='…'`:

| Argument | What it does |
| --- | --- |
| `--vault <path>` | Open this folder. Does not change the remembered vault. |
| `--open <note>` | Open this note once the vault is up. |
| `--mode read` / `--mode edit` | Start in that mode. |
| `--appearance light` / `dark` / `system` | Override the appearance for this launch. |
| `--show sidebar` / `search` / `inspector` / `outline` / `switcher` / `palette` / `graph` / `atlas` / `workspace` / `daily` / `synclog` / `newfolder` | Open that UI after launch (for screenshots). `synclog` seeds a short demo log if the vault’s log is empty. `newfolder` creates an Untitled Folder and selects it, without the rename prompt. |
| `--sidebar open` | Start with the sidebar docked. |
| `--size <W>x<H>` | Window content size (default 1180×820). |
| `--window-id-file <path>` | Write the window number here, for `screencapture -l`. |

`scripts/shoot.sh NAME [onyx args…]` launches Onyx against the test vault (`VAULT`, default `/tmp/onyx-vault`) and captures the window to `build/shots`. Use `ONYX_SHOT_QUIET=1` so the window stays off-screen. Never point a screenshot run at `~/Notes`.

### Type-test scripts

`ONYX_TYPE_TEST=<file>` runs a small script against the editor after launch. Lines may be:

```
# comments are ignored
type <text>
key <code> [cmd|shift|opt]
wait <seconds>
dump                  # print the note text
open <path>
link <target>         # follow [[target]] like a click (attachments open in FileView)
openat <line> <path>  # open a note scrolled to a source line
exportpdf <path>      # write the book-page PDF quietly
split
back
trash <path>          # no confirm
escape                # run the same Esc path as the key, print the action
move <path> -> <folder>
rename <path> -> <new path>
fold <command id>     # fold, unfold, togglefold, foldall, unfoldall
foldclick <n>         # click the nth fold region's chevron (through mouseDown)
select <offset>       # a programmatic caret move, as Find does (opens folds)
foldstate             # folded count, hidden ranges, text height, text intact?
rfold [command id]    # reader: run a fold command, print foldable/folded/hidden counts
tagtree               # the Tags pane tree, fully expanded, with own/total counts
tagreveal <tag>       # what clicking a #tag does: select it in the Tags pane
tagsuggest <query>    # the editor's #tag completion rows
tagrename <from> -> <to>  # plan and write a tag rename (no sheet)
tagundo               # undo the last tag rename
```

There are more workspace commands for tree selection, previews, and relations; see `TypeSelfTest` in `Sources/Onyx/LinkSuggest.swift`. Never set `ONYX_TYPE_TEST` in normal use.

## Signing

After a rebuild, macOS may ask for Keychain access if the app was signed ad hoc (the signature changes every build). `make app` and `make release` (via `scripts/bundle.sh`) sign with an Apple Development or Developer ID identity if you have one, otherwise with a stable local “Onyx Local Signing” identity. Create that once with `scripts/make-signing-cert.sh`. Then “Always Allow” lasts across rebuilds.

The extensions are signed first, each with `Extensions/sandbox.entitlements` (extensions must be sandboxed), then the app without `--deep`. Safari lists the web extension only when that identity is an Apple Development or Developer ID certificate; see [the web clipper doc](web-clipper.md#signing-why-the-extension-may-not-show-up). To check registration without launching the app: copy the bundle somewhere, `lsregister -f` it, `pluginkit -a` its `.appex`es, then `pluginkit -m -v -p com.apple.Safari.web-extension` (and `-p com.apple.share-services`); undo with `pluginkit -r` and `lsregister -u`.

`SIGN_IDENTITY` and `SIGN_KEYCHAIN` override the identity and keychain `bundle.sh` uses. If nothing is available, the app is signed ad hoc, and Keychain will prompt again after each rebuild.

The official release builds are not notarized, which is why first launch needs the Gatekeeper step in [docs/compatibility.md](docs/compatibility.md).

## Tests

`make test` runs `swift test`, then `node --test Tests/reader`.

- `Tests/OnyxCoreTests` — vault index, links, Markdown rewrite, kanban, canvas, Obsidian Bases (`.base` parse/filter/formula), find, git text, note version history, fuzzy matching, auto-update from GitHub Releases, split-layout encode/decode/clamp, and the optional fixture / bench tests above.
- `Tests/OnyxSyncTests` — crypto, the sync engine, a mock server, and protocol vectors in `Tests/OnyxSyncTests/Resources/`.
- `Tests/reader` — typography and sidenote layout in Node, with fixtures in `Tests/reader/fixtures/` (`typeset-specimen.md`, `named-sidenotes.md`).

Add a test when you’re touching parsing, typography, sync, or link rewriting.

## Release process

1. Bump `VERSION` (this is the short version the auto-updater compares to the GitHub tag).
2. From a clean tree: `make release`. This builds a universal binary (Apple silicon + Intel) and writes `build/Onyx-<version>-macOS.zip`. Everyday `make app` stays native so rebuilds stay fast; `UNIVERSAL=1 make app` builds the same universal app without the zip.
3. Confirm both slices are present:

   ```sh
   lipo -info build/Onyx.app/Contents/MacOS/Onyx
   # Architectures in the fat file: … are: x86_64 arm64
   ```

4. Publish with `gh release create` (or `gh release upload --clobber` if you’re replacing an asset on an existing tag), uploading `build/Onyx-<version>-macOS.zip`. The auto-updater looks for that exact asset name (`Onyx-<ver>-macOS.zip`); don’t rename it. Don’t move a tag unless you mean to.

The official zip is a universal binary (Apple silicon and Intel). Include the Gatekeeper first-open note in the release text; [docs/compatibility.md](docs/compatibility.md) has the full copy.

## Contributing

Patches are welcome. Keep the page quiet — if you’re changing how it looks or feels, read [DESIGN.md](DESIGN.md) first.

- Work on a branch or a git worktree. `git pull --rebase` before you push, and don’t force-push `master`.
- Run `make test`.
- Point the app at a copy under `/tmp` while you work. Never write test files into a real vault.
- When launching a packaged `Onyx.app` for tests, set `ONYX_ALLOW_MULTIPLE=1` so you don’t quit a running Onyx. Prefer `make run-test` or `make dev`.
- Onyx is [AGPL-3.0](LICENSE).
