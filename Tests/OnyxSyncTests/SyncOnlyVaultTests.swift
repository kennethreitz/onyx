import XCTest
import OnyxCore
@testable import OnyxSync

/// Sync-only vaults (a local copy inside Onyx's container) against the in-process mock Obsidian Sync host.
/// Everything lives under /tmp with an in-memory secret store; nothing touches a real vault, the Keychain
/// or the network.
final class SyncOnlyVaultTests: XCTestCase {
    let key = Array(Hex.decode("47828e890e26499530026a1d8a709efa527338b8abd7cb7d792cd5f4b1f82b26")!)
    let salt = "0123456789abcdef0123456789abcdef"
    var server: MockSyncServer!
    var crypto: ObsidianV2Provider!
    var tmp: URL!
    let clock = TestClock()

    override func setUp() async throws {
        crypto = try ObsidianV2Provider(key: key, salt: salt)
        server = try MockSyncServer(keyhash: crypto.keyHash)
        try await server.start()
        tmp = URL(fileURLWithPath: "/tmp/onyx-sync-only-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDown() async throws {
        server.stop()
        try? FileManager.default.removeItem(at: tmp)
    }

    func binding(_ device: String) -> SyncBinding {
        SyncBinding(vaultID: "remote-1", vaultName: "Throwaway", host: "127.0.0.1:\(server.port)", salt: salt,
                    encryptionVersion: 3, deviceName: device, accountEmail: "test@example.com")
    }
    var options: SyncEngine.Options {
        var o = SyncEngine.Options()
        o.allowLocalHost = true; o.deleteMode = .remove
        let c = clock; o.now = { c.now }
        return o
    }
    func makeVaults(_ store: MemoryStore = MemoryStore()) -> SyncOnlyVaults {
        SyncOnlyVaults(library: SyncVaultLibrary(root: tmp.appendingPathComponent("Vaults")), store: store, supportDir: tmp.appendingPathComponent("Sync"))
    }
    /// Another device: a plain folder synced with the ordinary engine.
    func device(_ files: [String: String]) throws -> (URL, SyncEngine) {
        let u = tmp.appendingPathComponent("Desktop")
        for (p, c) in files { try write(u, p, c) }
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        var o = options; o.backupDir = tmp.appendingPathComponent("backups-desktop")
        let e = SyncEngine(root: u, state: SyncState(binding: binding("Desktop")), crypto: crypto, token: "t",
                           stateURL: tmp.appendingPathComponent("desktop-state.json"), options: o)
        return (u, e)
    }
    func write(_ v: URL, _ p: String, _ c: String) throws {
        let f = v.appendingPathComponent(p)
        try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(c.utf8).write(to: f)
    }
    func read(_ v: URL, _ p: String) -> String? { try? String(contentsOf: v.appendingPathComponent(p), encoding: .utf8) }
    func files(_ v: URL) -> Set<String> {
        var out = Set<String>()
        guard let e = FileManager.default.enumerator(at: v, includingPropertiesForKeys: [.isDirectoryKey]) else { return out }
        for case let u as URL in e where (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false {
            out.insert(String(u.resolvingSymlinksInPath().path.dropFirst(v.resolvingSymlinksInPath().path.count + 1)))
        }
        return out
    }
    func settle(_ engines: SyncEngine..., rounds: Int = 6) async {
        for _ in 0..<rounds {
            for e in engines {
                await e.requestSync()
                for _ in 0..<4 {
                    clock.advance(31)
                    _ = await e.syncNow()
                    try? await Task.sleep(nanoseconds: 60_000_000)
                }
            }
        }
    }
    func liveRemote() async -> Set<String> {
        let c = crypto!
        return Set(await server.snapshot().records.filter { !$0.deleted && !$0.folder }.compactMap { try? c.decodeString($0.path) })
    }

    // MARK: -

    func testConnectCreatesLocalCopyAndPullsEverything() async throws {
        let (desk, ed) = try device(["Home.md": "home\n", "Daily/2026-11-25.md": "day\n", ".obsidian/app.json": "{\n  \"x\": 1\n}", "pic.png": "PNG"])
        await settle(ed)

        let store = MemoryStore()
        let vaults = makeVaults(store)
        let v = try vaults.connect(binding: binding("Phone"), key: key)
        let folder = vaults.folder(v)
        XCTAssertEqual(folder.path, tmp.appendingPathComponent("Vaults/Throwaway").path)
        XCTAssertTrue(vaults.isConnected(v))
        XCTAssertEqual(store.vaultKey("remote-1"), key, "the vault key is kept in the secret store, not in the state file")
        let stateText = try String(contentsOf: vaults.stateURL(v), encoding: .utf8)
        XCTAssertFalse(stateText.contains(Hex.encode(key)), "no key material in the state file")

        let e = try XCTUnwrap(try vaults.engine(for: v, token: "t", options: options))
        await settle(e)
        XCTAssertEqual(files(folder), ["Home.md", "Daily/2026-11-25.md", ".obsidian/app.json", "pic.png"])
        XCTAssertEqual(read(folder, "Home.md"), "home\n")
        let st = await e.state
        XCTAssertFalse(st.initialMerge, "first pass done")
        XCTAssertNotNil(st.lastSynced)
        let phase = await e.currentPhase
        XCTAssertEqual(phase, .synced)
        _ = desk
    }

    func testEditsFlowBothWaysAndStateSurvivesRestart() async throws {
        let (desk, ed) = try device(["Note.md": "one\n"])
        await settle(ed)
        let vaults = makeVaults()
        let v = try vaults.connect(binding: binding("Phone"), key: key)
        let folder = vaults.folder(v)
        var e = try XCTUnwrap(try vaults.engine(for: v, token: "t", options: options))
        await settle(e)

        try write(folder, "Note.md", "one\ntwo from phone\n")
        try write(folder, "New.md", "new\n")
        await settle(e, ed)
        XCTAssertEqual(read(desk, "Note.md"), "one\ntwo from phone\n")
        XCTAssertEqual(read(desk, "New.md"), "new\n")

        // Relaunch: the engine resumes from the saved state, and remote edits/deletes arrive.
        await e.stop()
        try write(desk, "Note.md", "one\ntwo from phone\nthree from desktop\n")
        try FileManager.default.removeItem(at: desk.appendingPathComponent("New.md"))
        await settle(ed)
        e = try XCTUnwrap(try vaults.engine(for: v, token: "t", options: options))
        let resumed = await e.state
        XCTAssertFalse(resumed.initial, "resumed, not a fresh first sync")
        await settle(e)
        XCTAssertEqual(read(folder, "Note.md"), "one\ntwo from phone\nthree from desktop\n")
        XCTAssertNil(read(folder, "New.md"), "a deletion on the other device reaches the local copy")
    }

    func testDisconnectKeepsTheCopyAndReconnectReusesItWithoutDeleting() async throws {
        let (_, ed) = try device(["Keep.md": "k\n"])
        await settle(ed)
        let store = MemoryStore()
        let vaults = makeVaults(store)
        let v = try vaults.connect(binding: binding("Phone"), key: key)
        var e = try XCTUnwrap(try vaults.engine(for: v, token: "t", options: options))
        await settle(e)
        await e.stop()

        vaults.disconnect(v)
        XCTAssertFalse(vaults.isConnected(v))
        XCTAssertNil(store.vaultKey("remote-1"))
        XCTAssertNil(try vaults.engine(for: v, token: "t", options: options))
        XCTAssertEqual(files(vaults.folder(v)), ["Keep.md"], "disconnect deletes nothing locally")
        XCTAssertEqual(vaults.library.load().map(\.id), ["remote-1"], "still listed, ready to reconnect")

        // While disconnected: a local-only note, and the copy of Keep.md is edited.
        try write(vaults.folder(v), "Offline.md", "offline\n")
        try write(vaults.folder(v), "Keep.md", "k\nedited offline\n")

        let again = try vaults.connect(binding: binding("Phone"), key: key)
        XCTAssertEqual(again, v, "same folder, no second copy")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vaults.library.root.path).filter { !$0.hasPrefix(".") }, ["Throwaway"])
        e = try XCTUnwrap(try vaults.engine(for: again, token: "t", options: options))
        let st = await e.state
        XCTAssertTrue(st.initialMerge, "a reconnect is a careful first sync again")
        await settle(e, ed)
        let local = files(vaults.folder(v))
        XCTAssertTrue(local.isSuperset(of: ["Keep.md", "Offline.md"]))
        XCTAssertEqual(read(vaults.folder(v), "Keep.md"), "k\nedited offline\n")
        let remote = await liveRemote()
        XCTAssertTrue(remote.isSuperset(of: ["Keep.md", "Offline.md"]), "nothing deleted remotely")
        XCTAssertTrue(local.contains { $0.hasPrefix("Keep (Conflicted copy Phone ") }, "the differing remote version is kept beside it")
    }

    func testRemoveLocalCopyDeletesOnlyThisDevicesCopy() async throws {
        let (desk, ed) = try device(["A.md": "a\n", "B.md": "b\n"])
        await settle(ed)
        let store = MemoryStore()
        let vaults = makeVaults(store)
        let v = try vaults.connect(binding: binding("Phone"), key: key)
        let e = try XCTUnwrap(try vaults.engine(for: v, token: "t", options: options))
        await settle(e)
        await e.stop()
        let backups = SyncStorage.backupDir(forState: vaults.stateURL(v))
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)

        try vaults.removeLocalCopy(v)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vaults.folder(v).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: vaults.stateURL(v).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backups.path))
        XCTAssertNil(store.vaultKey("remote-1"))
        XCTAssertTrue(vaults.library.load().isEmpty)

        await settle(ed)
        let remote = await liveRemote()
        XCTAssertEqual(remote, ["A.md", "B.md"], "the remote vault is untouched")
        XCTAssertEqual(files(desk), ["A.md", "B.md"], "other devices keep everything")
    }

    func testKeySharedWithAPickedFolderSurvivesDisconnect() throws {
        let store = MemoryStore()
        let vaults = makeVaults(store)
        let v = try vaults.connect(binding: binding("Phone"), key: key)
        // The same remote vault also connected to a folder the user picked (path-hash state).
        let picked = tmp.appendingPathComponent("Picked")
        try SyncState(binding: binding("Mac")).save(SyncStorage.stateURL(for: picked, library: vaults.library, supportDir: vaults.supportDir))
        vaults.disconnect(v)
        XCTAssertEqual(store.vaultKey("remote-1"), key)
    }

    func testStateLocations() throws {
        let vaults = makeVaults()
        let v = try vaults.connect(binding: binding("Phone"), key: key)
        let managed = SyncStorage.stateURL(for: vaults.folder(v), library: vaults.library, supportDir: vaults.supportDir)
        XCTAssertEqual(managed.lastPathComponent, "vault-remote-1.json")
        XCTAssertEqual(managed, vaults.stateURL(v))
        let other = SyncStorage.stateURL(for: tmp.appendingPathComponent("Picked"), library: vaults.library, supportDir: vaults.supportDir)
        XCTAssertTrue(other.lastPathComponent.range(of: #"^[0-9a-f]{16}\.json$"#, options: .regularExpression) != nil)
        XCTAssertEqual(SyncStorage.backupDir(forState: managed).path, vaults.supportDir.appendingPathComponent("Backups/vault-remote-1").path)
    }

    func testUnlockChecksThePasswordWithTheServer() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [CaptureProtocol.self]
        CaptureProtocol.seen = []; CaptureProtocol.responses = ["{}"]
        let api = ObsidianAPI(baseURL: URL(string: "https://api.example.invalid")!, session: URLSession(configuration: cfg))
        let json = #"{"id":"remote-1","name":"Throwaway","host":"sync-1.obsidian.md","salt":"0123456789abcdef0123456789abcdef","encryption_version":3}"#
        let remote = try JSONDecoder().decode(ObsidianAPI.RemoteVault.self, from: Data(json.utf8))
        let r = try await SyncOnlyVaults.unlock(api: api, token: "tok", vault: remote, password: "correct horse", deviceName: "Phone", accountEmail: "t@example.com")
        let expected = try ObsidianCrypto.deriveVaultKey(password: "correct horse", salt: remote.salt!)
        XCTAssertEqual(r.key, expected)
        XCTAssertEqual(r.binding, SyncBinding(vaultID: "remote-1", vaultName: "Throwaway", host: "sync-1.obsidian.md", salt: remote.salt!,
                                              encryptionVersion: 3, deviceName: "Phone", accountEmail: "t@example.com"))
        let post = try XCTUnwrap(CaptureProtocol.seen.last)
        XCTAssertEqual(post.url, "https://api.example.invalid/vault/access")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: post.body ?? Data()) as? [String: Any])
        XCTAssertEqual(body["keyhash"] as? String, try ObsidianCrypto.provider(version: 3, key: expected, salt: remote.salt!).keyHash)
        XCTAssertEqual(body["vault_uid"] as? String, "remote-1")
        XCTAssertEqual(body["token"] as? String, "tok")

        do {
            _ = try await SyncOnlyVaults.unlock(api: api, token: "tok", vault: remote, password: "", deviceName: "Phone", accountEmail: "")
            XCTFail("an end-to-end vault needs its password")
        } catch {}
    }
}
