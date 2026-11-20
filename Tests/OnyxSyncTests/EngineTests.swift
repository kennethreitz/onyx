import XCTest
@testable import OnyxSync

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = Date(timeIntervalSince1970: 1_763_600_000)
    var now: Date { lock.lock(); defer { lock.unlock() }; return t }
    func advance(_ s: TimeInterval) { lock.lock(); t += s; lock.unlock() }
}

/// Two "devices" (temp folders + engines) syncing through the in-process mock Obsidian Sync host.
/// Everything lives under /tmp; nothing here touches a real vault or the network.
final class EngineTests: XCTestCase {
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
        tmp = URL(fileURLWithPath: "/tmp/onyx-sync-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDown() async throws {
        server.stop()
        try? FileManager.default.removeItem(at: tmp)
    }

    func vault(_ name: String, _ files: [String: String] = [:]) throws -> URL {
        let u = tmp.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        for (p, c) in files { try write(u, p, c) }
        return u
    }
    func write(_ v: URL, _ p: String, _ c: String) throws {
        let f = v.appendingPathComponent(p)
        try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(c.utf8).write(to: f)
    }
    func read(_ v: URL, _ p: String) -> String? { try? String(contentsOf: v.appendingPathComponent(p), encoding: .utf8) }
    func files(_ v: URL) -> Set<String> {
        var out = Set<String>()
        let e = FileManager.default.enumerator(at: v, includingPropertiesForKeys: [.isDirectoryKey])!
        for case let u as URL in e where (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false {
            out.insert(String(u.resolvingSymlinksInPath().path.dropFirst(v.resolvingSymlinksInPath().path.count + 1)))
        }
        return out
    }

    func binding(_ device: String) -> SyncBinding {
        SyncBinding(vaultID: "v1", vaultName: "Throwaway", host: "127.0.0.1:\(server.port)", salt: salt,
                    encryptionVersion: 3, deviceName: device, accountEmail: "test@example.com")
    }
    func engine(_ v: URL, _ device: String, configure: (inout SyncState) -> Void = { _ in }) -> SyncEngine {
        var st = SyncState(binding: binding(device))
        configure(&st)
        var o = SyncEngine.Options()
        o.allowLocalHost = true; o.deleteMode = .remove
        o.backupDir = tmp.appendingPathComponent("backups-\(device)")
        let c = clock
        o.now = { c.now }
        return SyncEngine(root: v, state: st, crypto: crypto, token: "t", stateURL: tmp.appendingPathComponent("state-\(device).json"), options: o)
    }

    /// Run passes until the engine is quiet: synced, no pending server records, with time moving past debounces.
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

    // MARK: -

    func testFirstConnectPlanAndKeepBoth() async throws {
        let a = try vault("A", ["Shared.md": "from A\n", "OnlyA.md": "a\n", "Daily/2026-11-20.md": "day\n",
                                ".obsidian/app.json": "{\n  \"x\": 1\n}", ".obsidian/workspace.json": "{}",
                                "pic.png": "PNG", "data.xyz": "unsupported", ".git/HEAD": "ref", ".trash/old.md": "trash"])
        let ea = engine(a, "DevA")
        await settle(ea)
        let afterA = await server.snapshot().records.filter { !$0.deleted }.count
        XCTAssertEqual(afterA, 5 + 1, "Shared, OnlyA, Daily/…, app.json, pic.png + Daily folder")

        let b = try vault("B", ["Shared.md": "from B\n", "OnlyB.md": "b\n"])
        let plan = try await InitialPlan.compute(root: b, filter: SyncFilter(), crypto: crypto, binding: binding("DevB"), token: "t", allowLocalHost: true)
        XCTAssertEqual(plan.toDownload, [".obsidian/app.json", "Daily/2026-11-20.md", "OnlyA.md", "pic.png"])
        XCTAssertEqual(plan.toUpload, ["OnlyB.md"])
        XCTAssertEqual(plan.keepBoth, ["Shared.md"])
        XCTAssertEqual(plan.identical, 0)
        XCTAssertTrue(plan.summary.contains("Nothing is deleted"))

        let eb = engine(b, "DevB")
        await settle(eb, ea)
        let fb = files(b)
        XCTAssertEqual(read(b, "Shared.md"), "from B\n", "local version stays at its path")
        let copy = try XCTUnwrap(fb.first { $0.hasPrefix("Shared (Conflicted copy DevB ") && $0.hasSuffix(").md") })
        XCTAssertEqual(read(b, copy), "from A\n", "remote version kept beside it")
        XCTAssertEqual(read(b, "OnlyA.md"), "a\n")
        XCTAssertEqual(read(b, ".obsidian/app.json"), "{\n  \"x\": 1\n}")
        XCTAssertFalse(fb.contains(".obsidian/workspace.json")); XCTAssertFalse(fb.contains("data.xyz"))
        XCTAssertTrue(fb.contains("pic.png"))
        // A picks up B's side; A's unchanged Shared.md takes B's newer version; nothing deleted anywhere.
        XCTAssertEqual(read(a, "OnlyB.md"), "b\n")
        XCTAssertEqual(read(a, "Shared.md"), "from B\n")
        XCTAssertEqual(read(a, copy), "from A\n")
        XCTAssertTrue(files(a).isSuperset(of: ["OnlyA.md", "Daily/2026-11-20.md", "data.xyz", ".obsidian/workspace.json"]))
        let st = await eb.state
        XCTAssertFalse(st.initialMerge, "initial merge ends after the first complete pass")
    }

    func testInitialMergeNeverDeletes() async throws {
        let a = try vault("A", ["Gone.md": "x\n", "Keep.md": "k\n"])
        let ea = engine(a, "DevA")
        await settle(ea)
        try FileManager.default.removeItem(at: a.appendingPathComponent("Gone.md"))
        await settle(ea)
        let gone = await server.snapshot().records.last { $0.deleted }
        XCTAssertNotNil(gone, "A's deletion reached the server")

        // B has an old copy of Gone.md; the remote deletion must not touch it on first connect, and B re-uploads it.
        let b = try vault("B", ["Gone.md": "x\n"])
        let eb = engine(b, "DevB")
        await settle(eb, ea)
        XCTAssertEqual(read(b, "Gone.md"), "x\n")
        XCTAssertEqual(read(a, "Gone.md"), "x\n", "restored to A too: nothing lost")
        XCTAssertEqual(read(b, "Keep.md"), "k\n")
    }

    func testSteadyStateEditDeleteRename() async throws {
        let a = try vault("A", ["Note.md": "one\n", "Folder/Inner.md": "inner\n", "Old name.md": "rename me\n"])
        let b = try vault("B")
        let ea = engine(a, "DevA"), eb = engine(b, "DevB")
        await settle(ea, eb)
        XCTAssertEqual(read(b, "Folder/Inner.md"), "inner\n")

        try write(a, "Note.md", "one\ntwo\n")
        await settle(ea, eb)
        XCTAssertEqual(read(b, "Note.md"), "one\ntwo\n")

        try FileManager.default.removeItem(at: b.appendingPathComponent("Folder/Inner.md"))
        await settle(eb, ea)
        XCTAssertNil(read(a, "Folder/Inner.md"), "deletion propagates once past the initial merge")

        try FileManager.default.moveItem(at: a.appendingPathComponent("Old name.md"), to: a.appendingPathComponent("New name.md"))
        await settle(ea, eb)
        XCTAssertNil(read(b, "Old name.md"))
        XCTAssertEqual(read(b, "New name.md"), "rename me\n")
        let renamed = await server.snapshot().log.contains { ($0["op"] as? String) == "push" && !($0["relatedpath"] is NSNull) && $0["relatedpath"] != nil }
        XCTAssertTrue(renamed, "rename sent relatedpath (version history follows the file)")
    }

    func testThreeWayMergeLikeObsidian() async throws {
        let base = "# Groceries\n\n- eggs\n- milk\n- bread\n\nNotes about the week go here.\nSecond paragraph stays.\n"
        let a = try vault("A", ["List.md": base]); let b = try vault("B")
        let ea = engine(a, "DevA"), eb = engine(b, "DevB")
        await settle(ea, eb)
        XCTAssertEqual(read(b, "List.md"), base)
        // Both edit while apart: A syncs first, then B (which changed a different line) receives A's version.
        let local = base.replacingOccurrences(of: "- milk", with: "- oat milk")
        let remote = base.replacingOccurrences(of: "Second paragraph stays.", with: "Second paragraph stays, edited remotely.")
        try write(a, "List.md", remote)
        await settle(ea)
        try write(b, "List.md", local)
        await settle(eb, ea)
        let expected = TextMerge.shared.merge(base: base, local: local, remote: remote)
        XCTAssertEqual(expected, "# Groceries\n\n- eggs\n- oat milk\n- bread\n\nNotes about the week go here.\nSecond paragraph stays, edited remotely.\n")
        XCTAssertEqual(read(b, "List.md"), expected)
        XCTAssertEqual(read(a, "List.md"), expected, "merged result flows back")
        XCTAssertFalse(files(b).contains { $0.contains("Conflicted copy") })
        let backups = files(tmp.appendingPathComponent("backups-DevB"))
        XCTAssertTrue(backups.contains { $0.hasSuffix("List.md") }, "pre-merge text backed up")
    }

    func testConflictStrategyKeepsCopy() async throws {
        let a = try vault("A", ["N.md": "base\n"]); let b = try vault("B")
        let ea = engine(a, "DevA"), eb = engine(b, "DevB") { $0.conflictStrategy = .conflict }
        await settle(ea, eb)
        try write(a, "N.md", "remote edit\n"); await settle(ea)
        try write(b, "N.md", "local edit\n"); await settle(eb)
        XCTAssertEqual(read(b, "N.md"), "remote edit\n")
        let copy = try XCTUnwrap(files(b).first { $0.hasPrefix("N (Conflicted copy DevB ") })
        XCTAssertEqual(read(b, copy), "local edit\n")
    }

    func testMassDeletionPausesUntilConfirmed() async throws {
        var many: [String: String] = [:]
        for i in 0..<30 { many["n\(i).md"] = "\(i)\n" }
        let a = try vault("A", many); let b = try vault("B")
        let ea = engine(a, "DevA"), eb = engine(b, "DevB")
        await settle(ea, eb)
        XCTAssertEqual(files(b).count, 30)
        for i in 0..<25 { try FileManager.default.removeItem(at: a.appendingPathComponent("n\(i).md")) }
        await settle(ea)
        guard case .needsAttention = await ea.syncNow() else { return XCTFail("should stop for confirmation") }
        XCTAssertEqual(files(b).count, 30)
        let st = await ea.state; XCTAssertTrue(st.paused)
        await ea.confirmPendingAction()
        await settle(ea, eb)
        XCTAssertEqual(files(b).count, 5)
    }

    func testEmptiedFolderPauses() async throws {
        let a = try vault("A", ["x.md": "x\n", "y.md": "y\n"])
        let ea = engine(a, "DevA")
        await settle(ea)
        for f in files(a) { try FileManager.default.removeItem(at: a.appendingPathComponent(f)) }
        await settle(ea)
        let live = await server.snapshot().records.filter { !$0.deleted && !$0.folder }.count
        XCTAssertEqual(live, 2, "nothing deleted remotely")
        let st = await ea.state; XCTAssertTrue(st.paused)
    }

    func testReconnectsAfterDrop() async throws {
        let a = try vault("A", ["x.md": "x\n"]); let b = try vault("B")
        let ea = engine(a, "DevA"), eb = engine(b, "DevB")
        await settle(ea, eb)
        await server.dropAll()
        try? await Task.sleep(nanoseconds: 200_000_000)
        try write(a, "x.md", "x2\n")
        // Backoff: first retry is immediate-ish (5 s × jitter); real time must pass, so poll for a while.
        var ok = false
        for _ in 0..<80 where !ok {
            await settle(ea, eb, rounds: 1)
            ok = read(b, "x.md") == "x2\n"
            if !ok { try? await Task.sleep(nanoseconds: 100_000_000) }
        }
        XCTAssertTrue(ok, "both reconnected and synced")
    }
}

final class FilterAndMergeTests: XCTestCase {
    func testObsidianDefaults() {
        let f = SyncFilter()
        XCTAssertTrue(f.allows("a/b.md", folder: false)); XCTAssertTrue(f.allows("x.canvas", folder: false)); XCTAssertTrue(f.allows("x.base", folder: false))
        XCTAssertTrue(f.allows("img.PNG", folder: false)); XCTAssertTrue(f.allows("s.mp3", folder: false)); XCTAssertTrue(f.allows("d.pdf", folder: false))
        XCTAssertTrue(f.allows("v.webm", folder: false)); XCTAssertFalse(f.allows("x.zip", folder: false))
        XCTAssertFalse(f.allows(".trash/x.md", folder: false)); XCTAssertFalse(f.allows("a/.hidden/x.md", folder: false))
        XCTAssertTrue(f.allows(".obsidian/app.json", folder: false)); XCTAssertTrue(f.allows(".obsidian/appearance.json", folder: false))
        XCTAssertTrue(f.allows(".obsidian/hotkeys.json", folder: false)); XCTAssertTrue(f.allows(".obsidian/core-plugins.json", folder: false))
        XCTAssertTrue(f.allows(".obsidian/daily-notes.json", folder: false), "core-plugin-data")
        XCTAssertTrue(f.allows(".obsidian/snippets/a.css", folder: false)); XCTAssertTrue(f.allows(".obsidian/themes/T/theme.css", folder: false))
        XCTAssertFalse(f.allows(".obsidian/workspace.json", folder: false)); XCTAssertFalse(f.allows(".obsidian/workspace-mobile.json", folder: false))
        XCTAssertFalse(f.allows(".obsidian/community-plugins.json", folder: false))
        XCTAssertFalse(f.allows(".obsidian/plugins/p/main.js", folder: false))
        XCTAssertFalse(f.allows(".obsidian/plugins/p/node_modules/x.json", folder: false))
        XCTAssertFalse(f.allows(".obsidian", folder: true))
        var g = f; g.ignoreFolders = ["Private"]
        XCTAssertFalse(g.allows("Private/x.md", folder: false)); XCTAssertFalse(g.allows("Private", folder: true)); XCTAssertTrue(g.allows("Privateer.md", folder: false))
    }

    func testMergeMatchesObsidianVectors() throws {
        struct V: Decodable { struct C: Decodable { let base, local, remote, merged: String }; let cases: [C] }
        let url = Bundle.module.url(forResource: "obsidian-merge-vectors", withExtension: "json")!
        let v = try JSONDecoder().decode(V.self, from: Data(contentsOf: url))
        XCTAssertGreaterThan(v.cases.count, 40)
        for c in v.cases { XCTAssertEqual(TextMerge.shared.merge(base: c.base, local: c.local, remote: c.remote), c.merged) }
    }

    func testJSONConfigMergeAndCorePlugins() {
        XCTAssertEqual(TextMerge.shared.mergeJSONObjects(local: #"{"b":1,"a":2}"#, remote: #"{"a":3,"c":[1]}"#), "{\n  \"b\": 1,\n  \"a\": 3,\n  \"c\": [\n    1\n  ]\n}")
        XCTAssertNil(TextMerge.shared.mergeJSONObjects(local: "[1]", remote: "{}"))
        XCTAssertEqual(TextMerge.shared.patchCorePlugins(#"["graph"]"#), "[\n  \"graph\",\n  \"sync\"\n]")
        XCTAssertEqual(TextMerge.shared.patchCorePlugins(#"["sync"]"#), #"["sync"]"#)
        XCTAssertEqual(TextMerge.shared.patchCorePlugins(#"{"sync":false}"#), "{\n  \"sync\": true\n}")
    }

    func testPaths() {
        XCTAssertEqual(SyncPath.stripExt("a.b/c.md"), "a.b/c")
        XCTAssertEqual(SyncPath.ext(".gitignore"), "")
        XCTAssertFalse(SyncPath.isValidRemoteName("../x.md")); XCTAssertFalse(SyncPath.isValidRemoteName("/abs.md"))
        XCTAssertFalse(SyncPath.isValidRemoteName("file:///x")); XCTAssertTrue(SyncPath.isValidRemoteName("a/b c.md"))
        XCTAssertEqual(SyncPath.sanitize("Ken's Mac: Pro/2"), "Ken's Mac_ Pro_2")
    }
}
