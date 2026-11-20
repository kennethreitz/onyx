# Obsidian Sync protocol map

Status: Phase 1 (reverse-engineering + offline implementation). Last checked 2026-11-20 against
**Obsidian 1.15.1** desktop (`~/Library/Application Support/obsidian/obsidian-1.15.1.asar`, `app.js`, same code in the
1.15.0 bundled `/Applications/Obsidian.app/Contents/Resources/obsidian.asar`) and Obsidian's own
**`obsidian-headless` 0.0.14** npm package (`cli.js`, the official `ob` CLI by Dynalist Inc.).

Obsidian Sync has no public API. Everything below was read from those shipped JavaScript bundles (read-only; no
network traffic was captured and no account was used). Implementation: `Sources/OnyxSync`.

Confidence legend: **[code]** read directly in the shipped JS · **[vector]** additionally proven by byte-exact test
vectors in Swift + an independent Python implementation · **[guess]** inferred, not yet observed on the wire.

> **Worth knowing:** Obsidian now ships an official headless Sync client (`npm i -g obsidian-headless`, command `ob`,
> Node ≥ 22, UNLICENSED). `ob sync --continuous` in a vault folder keeps it synced without the desktop app. That's
> the zero-risk fallback if the native path ever breaks, and it's a second reference implementation of everything here.

## 1. REST API — `https://api.obsidian.md` **[code]**

Every call is `POST <base><path>` with a JSON body and `Content-Type: application/json`. A non-2xx status is
an HTTP error; a 2xx body with an `"error"` key is an API error (`{error: "..."}`). The desktop app sends no custom
User-Agent; `obsidian-headless` sends `User-Agent: obsidian-headless/<version>`. Auth is a bearer-ish `token` field in
the body (not a header).

| Path | Body | Response (fields used by the client) |
|---|---|---|
| `/user/signin` | `email, password, mfa` (verbatim; `mfa: ""` first) | `token, email, name, license`. 2FA accounts get an error containing "2FA code"; retry with the code. **obsidian-headless sends an `OPTIONS` preflight first and `Origin: https://obsidian.md` on both requests** — mirror that exactly (see below) |
| `/user/signout` | `token` | |
| `/user/info` | `token` | account info |
| `/user/authtoken` | `token` | (token refresh/exchange) |
| `/subscription/list` | `token` | |
| `/vault/list` | `token, supported_encryption_version` (=3) | `vaults[], shared[], limit` (limit 0 → no Sync subscription) |
| `/vault/regions` | `token, host?` | `regions: [{name, value}]` |
| `/vault/create` | `token, name, keyhash, salt, region, encryption_version` | vault object. Standard (managed) encryption: `keyhash`/`salt` null |
| `/vault/migrate` | `token, vault_uid, keyhash, salt, region, encryption_version` | `id, name, host, encryption_version, password?, salt?` |
| `/vault/access` | `token, vault_uid, keyhash, host, encryption_version` | ok, or error if keyhash is wrong ("Failed to validate password") |
| `/vault/rename` | `token, vault_uid, name` | |
| `/vault/delete` | `token, vault_uid` | |
| `/vault/share/{list,invite,remove}` | `token, vault_uid, email / share_uid` | |

**Sign-in, exactly as `ob login` does it** (cli.js 0.0.14, `As` → `z`): `OPTIONS /user/signin` with
`Origin: https://obsidian.md` + `User-Agent: obsidian-headless/0.0.14`, then `POST /user/signin` with those two plus
`Content-Type: application/json` and `{"email","password","mfa"}` as typed (its prompt strips only the newline; no
trim/lowercase/NFKC). First attempt uses `mfa: ""`; on an error containing "2FA code" (but not "2FA code is
incorrect") it prompts and resends. Onyx's first attempt (no preflight, no Origin, `User-Agent: Onyx-sync-poc`,
code sent up front, password via getpass) was refused with "Login failed, please double check your email and password."

Vault object (from `/vault/list`): `id, name, host, salt, password?, encryption_version, share_uid?`, plus size
fields. `host` is the websocket host, e.g. `sync-NN.obsidian.md` **[guess on exact naming; it's whatever the server returns]**.
`password` is present only for **standard** encryption: the server holds it and the client still runs the same
scrypt over it. **End-to-end** vaults omit it and the user types it. Shared vaults have a non-empty `share_uid`.

## 2. Keys and encryption **[vector]**

Key derivation (`BT`): `key = scrypt(NFKC(password), NFKC(salt), N=32768, r=8, p=1, dkLen=32)`. The salt is the
vault's salt *string* used as UTF-8 bytes (new salts are 16 random bytes rendered as 32 hex chars, but they are
never hex-decoded).

### Encryption version 2 and 3 (current; new vaults use 3)
Identical client-side; the number is just reported to the server. With `IKM = key`, `S = UTF-8(salt)`, HKDF-SHA256:

| Purpose | HKDF salt | info | Use |
|---|---|---|---|
| keyhash | `S` | `ObsidianKeyHash` | `keyhash = hex(32 bytes)` — sent to `/vault/access`, `/vault/create`, websocket `init` |
| SIV MAC key | `S` | `ObsidianAesSivMac` | AES-256 for CMAC (S2V) |
| SIV CTR key | `S` | `ObsidianAesSivEnc` | AES-256 for CTR |
| content key | empty | `ObsidianAesGcm` | AES-256-GCM for file bodies |

- **Paths and hashes** (`deterministicEncodeStr`) → `hex(AES-SIV(UTF-8(s)))` = `V(16) || CTR(...)`. S2V/CMAC is
  RFC 5297 with **no associated data**. **Quirk:** the CTR stage is WebCrypto `AES-CTR` with `length: 16`, so only the
  low 16 bits of the counter block (after clearing bits 63 and 31 per RFC) increment, and they **wrap without
  carry**. A stock RFC 5297 library (e.g. Python `cryptography.AESSIV`) agrees for almost all strings but produces
  different bytes when `V[14..15] + blocks` overflows 0xFFFF; the `ctrWrap` vector covers it.
- **File content** (`encrypt`) → `IV(12, random) || AES-GCM ciphertext || tag(16)`. A 12-byte blob (IV only) decrypts
  to empty. Empty files are sent as zero bytes, not encrypted.
- Whole path is encrypted as one string (`/` separators are inside the ciphertext); the server can't see structure.

### Encryption version 0 (legacy)
`keyhash = hex(sha256(key))`; content key = `key` directly (AES-GCM); deterministic strings use AES-GCM with
`IV = sha256(plaintext)[0..<12]`.

### Content hash
`hash = hex(sha256(plaintext bytes))`, then deterministically encrypted on the wire. Used for change detection and
server-side dedupe (a push whose encrypted hash matches the latest version is answered `res: ok` without upload).

## 3. Websocket protocol **[code]** unless noted

URL: `wss://<host>` (`ws://` only for `127.0.0.1`/`localhost`, Obsidian's dev server on `:3003`). The desktop client
**refuses any host not ending in `.obsidian.md`** (OnyxSync does the same). `binaryType = arraybuffer`. Control
messages are JSON text frames; file bytes are binary frames.

### Handshake
Client → `{"op":"init","token","id":<vault id>,"keyhash","version":<last uid seen, 0 fresh>,"initial":<bool>,
"device":<device name>,"encryption_version"}`

Server → first non-`pong` frame must be `{"res":"ok", "perFileMax"?: int, "userId"?: int}`. Errors:
`{"res":"err"|"status":"err","msg":...}` (messages seen in client code: "Your subscription to Obsidian Sync has expired",
"Vault not found"). A binary frame here is a protocol error.

Then the server streams every record newer than `version` as `{"op":"push", ...}` (including deletions), then
`{"op":"ready","version":N}`. After `ready` the client stores `version = max(version, N)`, `initial = false`.

### Server push (change notification)
`{"op":"push","uid","path":<enc>,"hash":<enc or "">,"size","ctime","mtime","folder","deleted","device","user"}`.
`uid` is a global, monotonically increasing version id; the client sets `version = uid` as it applies them. The
client recognises echoes of its own upload by comparing `path, folder, deleted, mtime, hash` (ciphertext) with what it
just pushed. **[guess]** whether the echo precedes or follows the final `res` reply; the JS race suggests "precedes".

### Requests (one in flight at a time; next text frame without an `op` is the reply; `err` field = failure)
| op | Request | Reply |
|---|---|---|
| `ping` | `{op}` every 20 s if idle > 10 s; disconnect if silent > 120 s | `{op:"pong"}` |
| `pull` | `{op, uid}` | `{size, pieces, deleted}` then `pieces` binary frames; concatenate, AES-GCM-decrypt |
| `push` (folder/delete) | `{op, path, relatedpath, extension:"", hash:"", ctime:0, mtime:0, folder, deleted}` | reply ignored |
| `push` (file) | `{op, path, relatedpath, extension, hash, ctime, mtime, folder:false, deleted:false, size, pieces}` | `res:"ok"` → done (dedupe); otherwise send `pieces` binary frames of ≤ 2 MiB, awaiting one reply after each **[guess: intermediate reply is `{res:"next"}`; client ignores its content]** |
| `history` | `{op, path:<enc>, last:<uid or null>}` | `{items:[{uid, path, relatedpath, ts, size, device, folder, deleted, ...}], more?}` **[guess: `more`]** |
| `deleted` | `{op, suppressrenames:true}` | `{items:[...]}` |
| `restore` | `{op, uid}` | |
| `size` | `{op}` | `{vault_size?, ...}` (migrate dialog reads `vault_size`) |
| `usernames` | `{op}` | user id → name map **[guess shape]** |
| `purge` | `{op}` | (clears history; destructive — never used by Onyx) |

`relatedpath` = encrypted previous path for renames, else null. `extension` = lowercased extension of the basename
(`""` for dotfiles/folders). `ctime`/`mtime` are ms since epoch. `perFileMax` defaults to 199 MiB.

## 4. Client sync algorithm (Obsidian's, for parity) **[code]**
State per path: local `{mtime, ctime, size, hash, synchash, synctime, previouspath}`, server `{uid, hash, ...}`,
plus a queue of pending server pushes. Each pass:
1. Apply pending server records: skip if hashes equal; download if local missing; folder/file type clashes rename to
   `"<name> (Conflicted copy).<ext>"`; on `initial` take the newer mtime; for `.md` conflicts do a **3-way merge**
   (base = last server version we had, via `pull(old uid)`) or, with conflict strategy "conflict", write
   `"<name> (Conflicted copy <device> <yyyyMMddHHmm>).md"`; `.obsidian/*.json` conflicts shallow-merge keys.
2. Push deletions of server files that no longer exist locally (deepest files first, then folders).
3. Push new folders (shallowest first), then new/changed files (smallest first). Files are skipped if modified in
   the last 10–30 s (size-based debounce) or larger than `perFileMax`.
Config-dir (`.obsidian/`) files sync only per user toggles (app, appearance, themes, snippets, hotkeys, core/community
plugin lists and plugin `manifest.json/main.js/styles.css/data.json`); `workspace*.json` never syncs.

## 5. Implementation in Onyx
- `OnyxSync/Scrypt.swift` — RFC 7914 scrypt (CommonCrypto PBKDF2 + Swift Salsa20/8); ~4 s per vault key in debug builds.
- `OnyxSync/AESSIV.swift` — Obsidian-flavoured AES-SIV (CMAC/S2V + 16-bit-wrap CTR) on CommonCrypto AES.
- `OnyxSync/ObsidianCrypto.swift` — key derivation, v0 / v2-3 providers, content hash.
- `OnyxSync/ObsidianAPI.swift` — REST client.
- `OnyxSync/SyncConnection.swift` — websocket client (init/ready/push events, pull, push incl. multi-piece, history,
  deleted, size, restore, heartbeat), host allow-list.
- `onyx-sync-poc` — live proof of concept that only ever touches a vault it creates named `onyx-throwaway-…`.
- Tests: byte-exact vectors (`Tests/OnyxSyncTests/Resources/obsidian-sync-vectors.json`, generated by
  `scripts/obsidian-sync-vectors.mjs`, cross-checked by `scripts/obsidian-sync-xcheck.py`), RFC 7914 vectors, and an
  in-process mock sync host (Network.framework) exercising the full wire flow.

Not built yet: the sync engine (local index, debounce, merge, conflict copies, config-dir filters) and any UI.

## 6. Open questions (need one live session on a throwaway vault)
1. Exact intermediate reply during multi-piece uploads (`res:"next"`?) and whether the echo `push` precedes the final reply.
2. `history` response pagination (`more`?) and item fields (`ts` confirmed in UI code; others guessed).
3. `size`, `usernames`, `deleted` reply shapes.
4. Rate limits / max concurrent connections per vault, and whether a non-Obsidian User-Agent matters (none is sent by
   the desktop app; Onyx sends `Onyx`).
5. Token lifetime and whether `/user/authtoken` is a refresh.
6. Server behaviour on `version` far behind (full backlog vs. snapshot).

## Prior art
- Obsidian, `obsidian-headless` (official CLI, npm) — https://www.npmjs.com/package/obsidian-headless
- DeepWiki notes on it — https://deepwiki.com/obsidianmd/obsidian-headless/3.2-encryption
- Belphemur/obsidian-headless (Go port, GPL-3.0) protocol docs — https://belphemur.github.io/obsidian-headless/architecture/sync-protocol.html
- laurensramandt/rev-obsidian-sync (reimplemented server) — https://github.com/laurensramandt/rev-obsidian-sync
- acheong08/obi-sync (self-hosted server) — https://github.com/acheong08/obi-sync
- brendongl/obsidian-sync-headless (early notes) — https://github.com/brendongl/obsidian-sync-headless
