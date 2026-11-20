// onyx-sync-poc: live proof of concept for OnyxSync against a THROWAWAY Obsidian Sync vault.
//
//   swift run onyx-sync-poc            # creates onyx-throwaway-<timestamp>, exercises it, deletes it
//   swift run onyx-sync-poc --keep     # leave the throwaway vault in place (inspect it from Obsidian)
//
// Safety rails:
// - You type your Obsidian email/password/2FA here; the token lives only in memory and is signed out at exit.
// - It only ever opens a websocket to a vault whose name starts with "onyx-throwaway-" and that it created
//   in this run. Your real vaults are never connected to, read, or written; their names aren't printed.
// - Nothing on disk is touched.
import Foundation
import OnyxSync

let prefix = "onyx-throwaway-"
let keep = CommandLine.arguments.contains("--keep")

/// Prompts like obsidian-headless's `Ke`: the line exactly as typed, minus the newline (no trimming).
/// Secrets use readpassphrase(3) with a 4 KB buffer: getpass(3) on macOS silently truncates at 128 chars.
func ask(_ prompt: String, secret: Bool = false) -> String {
    if secret {
        var buf = [CChar](repeating: 0, count: 4096)
        guard readpassphrase(prompt, &buf, buf.count, RPP_REQUIRE_TTY) != nil else { return "" }
        defer { for i in buf.indices { buf[i] = 0 } }
        return String(cString: buf)
    }
    print(prompt, terminator: ""); fflush(stdout)
    return readLine(strippingNewline: true) ?? ""
}
func step(_ s: String) { print("→ \(s)") }
func ok(_ s: String) { print("  ✓ \(s)") }
struct Fail: Error, CustomStringConvertible { let description: String }
func check(_ c: Bool, _ msg: String) throws { if c { ok(msg) } else { throw Fail(description: "FAILED: \(msg)") } }

func next(_ it: inout AsyncStream<SyncEvent>.AsyncIterator) async throws -> SyncEvent {
    guard let e = await it.next() else { throw Fail(description: "event stream ended") }
    if case .disconnected(let why) = e { throw Fail(description: "disconnected: \(why)") }
    return e
}

let api = ObsidianAPI()   // same headers as the official obsidian-headless CLI
print("""
Onyx ⇄ Obsidian Sync proof of concept
This signs in, creates a new end-to-end-encrypted vault named \(prefix)…, syncs a few test files
through it, verifies them, and \(keep ? "leaves it in place" : "deletes it"). Your existing vaults are not touched.
""")
guard ask("Continue? [yes/no] ") == "yes" else { exit(0) }
let email = ask("Obsidian email: ")
let password = ask("Obsidian password: ", secret: true)

var token = ""
var created: ObsidianAPI.RemoteVault?
do {
    step("Signing in")
    // Same order as `ob login`: try without a code; if the server asks for one, prompt then retry.
    var s: ObsidianAPI.SignIn
    do { s = try await api.signIn(email: email, password: password, mfa: "") }
    catch where ObsidianAPI.needsMFA(error) {
        s = try await api.signIn(email: email, password: password, mfa: ask("2FA code: "))
    }
    guard let t = s.token else { throw Fail(description: "no token in signin response") }
    token = t; ok("signed in")

    let name = prefix + ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
    let e2ePassword = UUID().uuidString            // throwaway vault, throwaway password
    let salt = (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()  // like y9()
    step("Deriving key (scrypt N=32768) and creating \(name)")
    let key = try ObsidianCrypto.deriveVaultKey(password: e2ePassword, salt: salt)
    let crypto = try ObsidianCrypto.provider(version: ObsidianCrypto.currentEncryptionVersion, key: key, salt: salt)
    _ = try await api.createVault(token: token, name: name, keyhash: crypto.keyHash, salt: salt)
    // Re-read from /vault/list so we use exactly what Obsidian would (host, salt, version).
    let list = try await api.listVaults(token: token)
    guard let vault = list.vaults.first(where: { $0.name == name }), vault.name.hasPrefix(prefix) else { throw Fail(description: "created vault not in list") }
    created = vault
    ok("vault \(vault.id) on \(vault.host), encryption v\(vault.encryption_version ?? -1)")
    try check(vault.salt == salt, "server echoes our salt")

    step("POST /vault/access (server verifies keyhash)")
    try await api.access(token: token, vaultID: vault.id, keyhash: crypto.keyHash, host: vault.host, encryptionVersion: crypto.encryptionVersion)
    ok("key accepted")

    step("Websocket init")
    let conn = SyncConnection(crypto: crypto)
    var ev = conn.events.makeAsyncIterator()
    try await conn.connect(url: try SyncConnection.url(forHost: vault.host), token: token, vaultID: vault.id, version: 0, initial: true, device: "Onyx PoC")
    guard case .ready(let v0) = try await next(&ev) else { throw Fail(description: "expected ready") }
    ok("ready, version \(v0), perFileMax \(await conn.perFileMax)")

    let now = Int(Date().timeIntervalSince1970 * 1000)
    let note = Data("# Hello from Onyx\n\nWritten by OnyxSync over the Obsidian Sync protocol.\n".utf8)
    step("Push folder + note")
    try await conn.push(path: "Onyx", folder: true)
    guard case .push(let f) = try await next(&ev) else { throw Fail(description: "no folder echo") }
    try check(f.path == "Onyx" && f.folder, "folder echoed and decrypted")
    try await conn.push(path: "Onyx/Hello.md", ctime: now, mtime: now, data: note)
    guard case .push(let n) = try await next(&ev) else { throw Fail(description: "no file echo") }
    try check(n.path == "Onyx/Hello.md" && n.hash == ObsidianCrypto.contentHash(note), "file echoed with matching hash (uid \(n.uid))")

    step("Pull it back")
    let back = try await conn.pull(uid: n.uid)
    try check(back == note, "content round-trips through the server")

    step("Edit, history, size")
    let note2 = note + Data("\nSecond revision.\n".utf8)
    try await conn.push(path: "Onyx/Hello.md", ctime: now, mtime: now + 1000, data: note2)
    guard case .push(let n2) = try await next(&ev) else { throw Fail(description: "no edit echo") }
    let h = try await conn.history(path: "Onyx/Hello.md")
    try check(h.items.map(\.uid).contains(n2.uid) && h.items.map(\.uid).contains(n.uid), "history lists both versions")
    print("  raw history keys:", h.raw.dict.keys.sorted(), "item keys:", (h.raw.dict["items"] as? [[String: Any]])?.first?.keys.sorted() ?? [])
    print("  size:", try await conn.size().dict)

    step("Delete")
    try await conn.push(path: "Onyx/Hello.md", deleted: true)
    guard case .push(let d) = try await next(&ev) else { throw Fail(description: "no delete echo") }
    try check(d.deleted, "deletion recorded")
    await conn.disconnect()

    step("Second device: reconnect from version 0")
    let c2 = SyncConnection(crypto: try ObsidianCrypto.provider(version: vault.encryption_version ?? 3, key: key, salt: vault.salt ?? salt))
    var ev2 = c2.events.makeAsyncIterator()
    try await c2.connect(url: try SyncConnection.url(forHost: vault.host), token: token, vaultID: vault.id, version: 0, initial: true, device: "Onyx PoC 2")
    var seen: [String] = []
    while true {
        let e = try await next(&ev2)
        if case .push(let p) = e { seen.append(p.path + (p.deleted ? " (deleted)" : "")) }
        if case .ready = e { break }
    }
    print("  backlog:", seen)
    try check(seen.contains("Onyx"), "backlog decrypted on a fresh connection")
    await c2.disconnect()
    print("\nALL CHECKS PASSED")
} catch {
    print("\n✗ \(error)")
}
if let v = created, v.name.hasPrefix(prefix), !keep {
    do { try await api.deleteVault(token: token, vaultID: v.id); ok("deleted \(v.name)") } catch { print("  could not delete \(v.name): \(error) (delete it in Obsidian → Sync → Manage)") }
}
if !token.isEmpty { try? await api.signOut(token: token); ok("signed out") }
