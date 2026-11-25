# Onyx on iOS

This is the plan and audit for an iPhone and iPad Onyx in the same repository as the Mac app (`kennethreitz/onyx`, branch `ios`). The Swift package already holds the shared engine; the Mac UI stays in `Sources/Onyx`, and a new `OnyxMobile` target is the iOS UI.

The first milestone (this branch) is groundwork: OnyxCore compiles for iOS, and a minimal app can open a vault folder, list and search notes, open today’s daily note, and render a note in the same typeset WKWebView reader the Mac uses.

## Shared vs Mac-only

### Shared (platform-neutral, in `OnyxCore`)

These are Foundation (plus simd, CryptoKit, JavaScriptCore, Observation) and already compile — or now compile — for iOS 17:

- **Vault** — `VaultSnapshot.scan`, note records, folder tree, wikilink resolution, backlinks, unlinked mentions, `search`
- **Parsing** — Markdown notes, frontmatter, inline fields, wikilinks, attachments, image sizes, tables
- **Daily notes** — `DailyNotes` and `.obsidian/daily-notes.json` via `ObsidianConfig`
- **Find, fuzzy, Quick Switcher scoring** — `FindText`, `Fuzzy`, `QuickMatch`
- **Reader payload** — `ReaderPayload` builds the JSON the existing `Resources/web` page (`reader.html` / `reader.js` / `typeset.js`, KaTeX, Mermaid) consumes. Wikilinks, embeds, Dataview, and Bases HTML are resolved in Swift so JS never touches the disk
- **Typesetting policy** — `TableLayout`, fold *logic* (`Folding`, not the AppKit layout manager)
- **Graph and atlas models** — `Graph`, `GraphIndex`, `RelationGraph` (layout math only)
- **Boards and Bases models** — `Canvas`, `Kanban`, `Bases`, `BaseFormula`, `BaseEdit`
- **Dataview** — `Dataview` and `DataviewJS` (JavaScriptCore is available on iOS)
- **Editing primitives for later** — `EditCommands`, `ListContinue`, `ListRenumber`, `SmartPairs`, `Linter`, `LinkUpdater`, `NoteComposer`, `NoteNaming`
- **Other** — `Attachments`, `AudioNote`, `CommandCatalog`, `KeyChord`, `ShortcutStore`, `SpeechText`, `TitlePath`, `TreeMove` / `TreeSort` / `TreeSelection`, `PaneRatios`, `SplitLayout`, `WindowLifecycle` (policy, not windows), `ReleaseNotes`, `Semver` / GitHub release *fetch* in `Updater`

`Resources/web` and `Resources/fonts` are also shared. The iOS app bundles them next to the same `onyx://app/…` and `onyx://vault/…` scheme the Mac reader uses.

### Shared: Obsidian Sync (`OnyxSync`)

Obsidian Sync (`OnyxSync`) is Foundation + CryptoKit + CommonCrypto + Security + JavaScriptCore and compiles for iOS 17. The two Mac-only bits are guarded: the conflict-copy device name falls back to the binding's device name instead of `Host`, and local deletions, which go to the Trash on the Mac, are moved into the vault's backups folder on iOS (no user-visible Trash). Keychain (`SecretStore`) uses generic passwords under Onyx's own service (`md.onyx.sync`) with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.

The iOS app uses it for **sync-only vaults** (see [sync.md](sync.md#sync-only-vaults)):

- The empty state and the Vault menu offer **Connect Obsidian Sync Vault**: sign in (2FA when the account asks), pick a remote vault, type its end-to-end password if it has one, and Onyx creates a local copy in the app container (`Application Support/Onyx/Vaults/<name>`), pulls everything, and opens it. No folder picker or security-scoped bookmark is involved; the open sync-only vault is remembered by remote id (`onyx.ios.managedVault`).
- A sync icon next to the vault name in the toolbar shows the status; tapping it (or Vault ▸ Manage Sync…) opens **Manage Sync**: Sync Now, Pause/Resume, Continue Anyway (after a mass-delete pause), Disconnect (keeps the local copy), Reconnect, other sync-only vaults on the device, and Delete Local Copy (confirmed, and it warns when the vault isn't fully synced).
- Sync runs while Onyx is in the foreground (the engine's 30 s rescan and edits trigger passes; returning to the app syncs at once). On leaving the app Onyx asks iOS for a short background grace period (up to about 25 s) to finish the current sync. There is no background refresh (`BGAppRefreshTask`) yet, so changes made elsewhere arrive the next time Onyx is opened.
- The note list rescans as files arrive (at most every few seconds during a large first pull, and once when it finishes).
- `make ios` signs the simulator build ad hoc ("Sign to Run Locally") so the app has an `application-identifier` and can use the Keychain. An unsigned build (`CODE_SIGNING_ALLOWED=NO`, as before) gets errSecMissingEntitlement (-34018) from the Keychain; Onyx then keeps the sign-in token and vault keys in an owner-only, data-protected file under `Application Support/Onyx/Secrets` instead of failing.
- The same unofficial-protocol caveats as on the Mac apply; try a throwaway vault first.

### Mac-only (`Sources/Onyx` and a few Core types)

The shipping Mac app is AppKit + SwiftUI and stays macOS-only:

- **Shell** — `OnyxApp`, `RootView`, `Workspace`, `Panels`, menus, `NSOpenPanel` / settings windows, `SingleInstanceHandover`
- **Editor** — `EditorView` (`NSTextView` + TextKit 1), `MarkdownHighlighter`, `EditorCommands`, `EditorFolding`, `LinkSuggest`, `SmartPairs` UI, `FoldLayoutManager` (`NSLayoutManager`, already `#if canImport(AppKit)` in OnyxCore)
- **Reader / print / book** — `ReaderView` (`NSViewRepresentable` + WKWebView), `NotePrinter`, `NoteBook`
- **Sidebar and files** — file tree, `FileWatcher` (**FSEvents**), `FileView`, drag and drop, `AttachmentDrop`
- **Graph / Atlas UI** — `GraphView`, `GraphPreview`
- **Boards UI** — `CanvasView`, `BasesView`, Kanban chrome
- **System** — `GitSync` (`Process`, Homebrew/`/usr/bin/git`), `UpdateUI` (install + relaunch via `Process` / `NSWorkspace`), `Speech`, `AudioPlayer` / `AudioRecording` (AppKit + AVFoundation UI), `ThinScroller`, key monitors, print
- **Updater install path** in OnyxCore — `Process` for `/usr/bin/ditto` and `xattr` is `#if os(macOS)`. Checking GitHub for a later version is still shared; replacing a `.app` is not

`onyx-bench` and `onyx-sync-poc` are command-line tools for the Mac.

Git autosync is not a Phase 1 iOS feature: there is no reliable `git` binary to shell out to, and FSEvents does not exist. Use iCloud Drive and/or Obsidian Sync instead (see Vault access below).

## Architecture

```
                    ┌──────────────────────────────┐
                    │  Resources/web + fonts       │
                    │  (reader, typeset, KaTeX,    │
                    │   Mermaid)                   │
                    └─────────────┬────────────────┘
                                  │
         ┌────────────────────────┼────────────────────────┐
         │                        │                        │
 ┌───────▼────────┐      ┌────────▼─────────┐     ┌────────▼────────┐
 │ Sources/Onyx   │      │ OnyxCore         │     │ OnyxMobile      │
 │ macOS app      │      │ (and OnyxSync)   │     │ iOS 17+ app     │
 │ AppKit+SwiftUI │      │ platforms:       │     │ SwiftUI+WKWebView│
 │ make app       │      │ macOS 14, iOS 17 │     │ make ios        │
 └────────────────┘      └──────────────────┘     └─────────────────┘
```

- One repo, one Swift package (`Package.swift` lists both platforms). `OnyxCore` and `OnyxSync` are library products; the `Onyx` executable stays a Mac product.
- The iOS app is an Xcode target (`project.yml` + `Onyx.xcodeproj`) that depends on the `OnyxCore` product and compiles with `xcodebuild -scheme OnyxMobile -destination 'generic/platform=iOS Simulator'`. SwiftPM cannot produce a signed iOS `.app` on its own.
- Everyday Mac work is unchanged: `swift build`, `swift test`, `make app` / `make release`. Do not use the Mac checkout’s `build/Onyx.app` as a worktree for this branch; prefer `~/repos/onyx-ios`.

## Vault access

iOS has no equivalent of “the app always has a POSIX path to `~/Notes`.” A vault is a **security-scoped folder**:

1. **UIDocumentPicker / SwiftUI `.fileImporter`** with `UTType.folder`. The user picks a folder (Files, On My iPhone, or **iCloud Drive**, including an Obsidian vault such as `iCloud Drive/Obsidian/MyVault`).
2. **Security-scoped bookmark** (`URL.bookmarkData` / `URL(resolvingBookmarkData:)`, without the macOS-only `.withSecurityScope` option). Persist it in `UserDefaults` (`onyx.ios.vaultBookmark`) and call `startAccessingSecurityScopedResource()` whenever the app uses the folder. Stop accessing when the vault is closed.
3. **File coordination** — `NSFileCoordinator` around `VaultSnapshot.scan` so iCloud materializes files and we don’t read mid-download. Later: an `NSFilePresenter` (or a directory enumerator + refresh) to pick up remote changes; there is no FSEvents.
4. **iCloud Drive vs Obsidian Sync**
   - *iCloud Drive* is the straightforward path: if the vault already lives in iCloud (Obsidian’s iCloud vault, or a folder the user keeps there), both Onyx and Obsidian see the same files. The OS syncs them. Coordination and conflict files matter; don’t write without a coordinator.
   - *Obsidian Sync* is account-based and independent of iCloud. `OnyxSync` can eventually run on iOS against a local copy of the vault (the picker folder, or an app-container copy). It still uses unofficial protocol work; ship it later, behind the same explicit opt-in as on the Mac.
   - *Git sync* stays Mac-only unless we later adopt a library (not `Process` + `/usr/bin/git`).
5. **On-device copy** is a possible fallback if the user cannot grant folder access: import into the app container. Prefer the picked folder so Obsidian and Onyx share one tree.

Never scan `~/Notes` from the phone; there is no such path, and even on a Mac checkout this work uses `/tmp` demo vaults only.

## Phased milestones

### Phase 1 — Read-only vault browser (this branch’s target)

- Open a folder via the document picker; remember it with a security-scoped bookmark
- List notes; search with `VaultSnapshot.search`; jump to today’s daily note (`DailyNotes` + `.obsidian/daily-notes.json`)
- Render the selected note in the typeset WKWebView reader (`ReaderPayload` + bundled `Resources/web`)
- Follow wikilinks inside the reader; open `https` / `mailto` links in Safari
- Refresh the snapshot (pull to refresh / menu), using `NSFileCoordinator`

Out of scope for Phase 1: editing, graph, boards, Bases UI, Dataview *authoring*, Sync, git, recording, print.

### Phase 2 — Light editing

- `UITextView` + TextKit 2 (not `NSTextView`; `FoldLayoutManager` is AppKit-only and will need a UIKit sibling)
- Reuse `EditCommands`, list continue/renumber, smart pairs, linter, link rewrite, note composer
- Save through `NSFileCoordinator` (writing); conflict policy when iCloud or Sync also wrote the file
- New note / new folder / daily note *creation* from the template

### Phase 3 — Graph, Atlas, Canvas, Bases, Dataview

- Graph and Atlas views on top of the existing `Graph` / `GraphIndex` models (SwiftUI or Metal/Canvas, not the Mac `GraphView`)
- Canvas, Kanban, and Bases — models already in OnyxCore; new SwiftUI chrome
- Dataview already runs in the reader payload; this phase is editing queries, Bases views, and performance on large phones-side vaults
- Optional: Obsidian Sync on iOS; attachments viewers (PDFKit, AVKit, and Photos are all available)

## Building

```sh
# Mac (unchanged)
swift build
swift test
make app

# iOS simulator (this branch)
make ios    # xcodegen generate && xcodebuild -scheme OnyxMobile -destination 'generic/platform=iOS Simulator'
```

Requires Xcode with the iOS Simulator SDK (17+) and [XcodeGen](https://github.com/yonaskolb/XcodeGen). Open `Onyx.xcodeproj` and run the `OnyxMobile` scheme on an iPhone or iPad simulator.

## Screens added after the first cut

The iOS shell now surfaces the features that landed on master the same day, reusing OnyxCore:

- **Bookmarks** — a sidebar tab. The list is `.obsidian/bookmarks.json` (Obsidian's format, including groups). Swipe a note or use the note menu to pin or unpin; swipe a bookmark to remove it. File, folder, search, and URL bookmarks open; graph bookmarks explain that the graph isn't in the iOS app yet.
- **Outline** — This note, Folder, Linked & partOf, or Whole vault, flattened lazily the same way as the Mac inspector. Tapping a heading opens that note at the line.
- **Backlinks** — from the note menu, or under the note in the reader. Linked mentions open at the line. Unlinked mentions follow the same rules as the Mac app. **Link** / **Link all** write the wikilink through the security-scoped vault folder (`NSFileCoordinator`, atomic write, then the snapshot is updated).
- **Find** — a sidebar tab: match case, whole word, regular expression, a preview grouped by file with checkboxes. **Replace selected** writes the same way as Link, or rolls the whole pass back if one file fails. (The usual vault search operators stay on the Notes search field.)
- **Reading** — Latin Modern, ET Book, and OpenDyslexic, plus the typeset toggles, stored in the same UserDefaults keys as Mac Settings ▸ Reading. The setting is local to Onyx, not the vault. The bundled fonts already ship in the iOS target.
- **Version History** — a short “not available on iPhone” screen. History on the Mac uses git; the iOS app does not ship git, and we don't pretend otherwise.
- **Web clipper** — not on iOS. Article HTML is converted with `HTMLToMarkdown`, which needs macOS `XMLDocument`.

Limited writing is intentional: only bookmarks, linking a mention, and vault replace, all inside the folder the user picked. Creating notes, a full editor, and git are still later milestones.

## What’s in this first cut

- Package platforms include iOS 17; `OnyxCore` (and `OnyxSync`) are built as libraries
- `FoldLayoutManager` remains AppKit-only; `Updater`’s `ditto` / `xattr` install path is `#if os(macOS)`
- `ReaderPayload` lives in OnyxCore so both apps share it
- `Sources/OnyxMobile` — SwiftUI app, document picker, list, search, daily note, typeset reader
- `project.yml` generates `Onyx.xcodeproj`

## App icon

`Resources/iOS/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` is the Mac app icon (`Resources/AppIcon.icns`, the onyx crystal with its note graph) with its rounded tile scaled to fill the square, opaque and full-bleed (iOS masks the corners). Regenerate it with `swift scripts/make-ios-icon.swift` after the Mac icon changes; `project.yml` sets `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`.
