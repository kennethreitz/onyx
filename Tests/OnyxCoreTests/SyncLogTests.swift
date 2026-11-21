import XCTest
@testable import OnyxCore

@MainActor
final class SyncLogTests: XCTestCase {
    func tempLog() throws -> (URL, SyncLogStore) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("onyx-synclog-\(UUID().uuidString).log")
        let store = SyncLogStore(fileURL: url, capacity: 5)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return (url, store)
    }

    func testAppendAndOrder() throws {
        let (_, s) = try tempLog()
        s.append(source: .git, event: .commit, detail: "Edit Home", date: Date(timeIntervalSince1970: 1))
        s.append(source: .obsidian, event: .downloaded, detail: "A.md", date: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(s.entries.count, 2)
        XCTAssertEqual(s.entries[0].source, .git)
        XCTAssertEqual(s.entries[0].event, .commit)
        XCTAssertEqual(s.entries[0].detail, "Edit Home")
        XCTAssertEqual(s.entries[1].source, .obsidian)
        XCTAssertEqual(s.entries[1].event, .downloaded)
    }

    func testCapacityIsARing() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("onyx-synclog-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }
        let s = SyncLogStore(fileURL: url, capacity: 3)
        for i in 1...5 { s.append(source: .git, event: .commit, detail: "c\(i)", date: Date(timeIntervalSince1970: TimeInterval(i))) }
        XCTAssertEqual(s.entries.map(\.detail), ["c3", "c4", "c5"])
        let disk = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(disk.contains("c1"))
        XCTAssertFalse(disk.contains("c2"))
        XCTAssertTrue(disk.contains("c5"))
    }

    func testPersistsAndReloads() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("onyx-synclog-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }
        let s = SyncLogStore(fileURL: url, capacity: 50)
        s.append(source: .git, event: .push, detail: "Pushed 1 commit", date: Date(timeIntervalSince1970: 1_737_000_000))
        s.append(source: .obsidian, event: .error, detail: "Timed out", date: Date(timeIntervalSince1970: 1_737_000_030))
        let text = s.renderedText()
        XCTAssertTrue(text.contains("git\tpush\tPushed 1 commit"))
        XCTAssertTrue(text.contains("obsidian\terror\tTimed out"))
        let reloaded = SyncLogStore(fileURL: url, capacity: 50)
        XCTAssertEqual(reloaded.entries.count, 2)
        XCTAssertEqual(reloaded.entries[0].source, .git)
        XCTAssertEqual(reloaded.entries[0].event, .push)
        XCTAssertEqual(reloaded.entries[0].detail, "Pushed 1 commit")
        XCTAssertEqual(reloaded.entries[1].event, .error)
        XCTAssertEqual(reloaded.entries[1].detail, "Timed out")
        XCTAssertEqual(reloaded.renderedText(), text)
    }

    func testParseSkipsGarbageAndKeepsLastCapacity() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("onyx-synclog-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }
        let body = """
        not a log line
        2026-11-20 21:00:00\tgit\tcommit\tEdit A
        2026-11-20 21:00:01\tnope\tcommit\tEdit B
        2026-11-20 21:00:02\tgit\tpull\tReceived 2 commits
        2026-11-20 21:00:03\tobsidian\tconnected\t

        """
        try body.write(to: url, atomically: true, encoding: .utf8)
        let s = SyncLogStore(fileURL: url, capacity: 10)
        XCTAssertEqual(s.entries.map { "\($0.event.rawValue):\($0.detail)" }, ["commit:Edit A", "pull:Received 2 commits", "connected:"])
        let tight = SyncLogStore(fileURL: url, capacity: 1)
        XCTAssertEqual(tight.entries.map(\.event), [.connected])
    }

    func testLineRoundTripStripsTabsInDetail() {
        let e = SyncLogEntry(date: Date(timeIntervalSince1970: 1_737_000_000), source: .git, event: .commit, detail: "Edit\tHome\nagain")
        XCTAssertEqual(e.detail, "Edit Home again")
        let parsed = SyncLogStore.parseLine(SyncLogStore.line(e))
        XCTAssertEqual(parsed?.source, .git)
        XCTAssertEqual(parsed?.event, .commit)
        XCTAssertEqual(parsed?.detail, "Edit Home again")
    }

    func testVaultFileURLIsStableAndPerVault() {
        let a = URL(fileURLWithPath: "/tmp/onyx-vault-a")
        let b = URL(fileURLWithPath: "/tmp/onyx-vault-b")
        let ua = SyncLogStore.fileURL(forVault: a)
        let ub = SyncLogStore.fileURL(forVault: b)
        XCTAssertNotEqual(ua, ub)
        XCTAssertEqual(ua, SyncLogStore.fileURL(forVault: a))
        XCTAssertTrue(ua.path.contains("/Onyx/Logs/"))
        XCTAssertTrue(ua.pathExtension == "log")
        XCTAssertEqual(SyncLogStore.vaultID(for: a).count, 16)
    }

    func testObsidianClassification() {
        let keep: [(String, String?, SyncLogEvent, String)] = [
            ("Connected", nil, .connected, ""),
            ("Connect failed timeout", nil, .error, "timeout"),
            ("Disconnected waiting", nil, .disconnected, "waiting"),
            ("Downloading file", "A.md", .downloaded, "A.md"),
            ("Upload complete", "B.md", .uploaded, "B.md"),
            ("Renaming conflicted file", "C.md", .conflict, "Renaming conflicted file: C.md"),
            ("Kept remote version as C (Conflicted copy).md", "C.md", .conflict, "Kept remote version as C (Conflicted copy).md: C.md"),
            ("Merging conflicted file", "C.md", .conflict, "Merging conflicted file: C.md"),
            ("Conflicted copy stored", "C.md", .conflict, "Conflicted copy stored: C.md"),
            ("Merge failed", "C.md", .error, "Merge failed: C.md"),
            ("Error no data", "D.md", .error, "no data: D.md"),
            ("Deleting", "E.md", .pull, "Deleted: E.md"),
            ("Deleting remote", "F.md", .push, "Deleted: F.md"),
            ("File too large to sync", "Big.bin", .error, "Too large to sync: Big.bin"),
            ("Rejected server change", "G.md", .conflict, "Rejected server change: G.md"),
        ]
        for (msg, path, event, detail) in keep {
            let r = SyncLogStore.fromObsidian(message: msg, path: path)
            XCTAssertEqual(r?.event, event, msg)
            XCTAssertEqual(r?.detail, detail, msg)
        }
        XCTAssertNil(SyncLogStore.fromObsidian(message: "Fully synced", path: nil))
        XCTAssertNil(SyncLogStore.fromObsidian(message: "Accepted", path: "A.md"))
        XCTAssertNil(SyncLogStore.fromObsidian(message: "Skipped", path: "A.md"))
        XCTAssertNil(SyncLogStore.fromObsidian(message: "Uploading", path: "A.md"))
        XCTAssertNil(SyncLogStore.fromObsidian(message: "Uploading file", path: "A.md"))
        XCTAssertNil(SyncLogStore.fromObsidian(message: "Initial merge complete", path: nil))
        XCTAssertTrue(SyncLogEvent.error.isAlert)
        XCTAssertTrue(SyncLogEvent.conflict.isAlert)
        XCTAssertFalse(SyncLogEvent.commit.isAlert)
    }

    func testSeedPreviewOnlyWhenEmpty() throws {
        let t = Date(timeIntervalSince1970: 1_737_100_000)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("onyx-synclog-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }
        let s = SyncLogStore(fileURL: url, capacity: 50, now: { t })
        s.seedPreviewIfEmpty()
        XCTAssertEqual(s.entries.count, 8)
        XCTAssertEqual(s.entries.first?.event, .commit)
        XCTAssertEqual(s.entries.last?.event, .error)
        XCTAssertTrue(s.entries.contains { $0.source == .obsidian && $0.event == .conflict })
        let n = s.entries.count
        s.seedPreviewIfEmpty()
        XCTAssertEqual(s.entries.count, n)
    }

    func testDefaultCapacity() {
        XCTAssertEqual(SyncLogStore.defaultCapacity, 500)
    }
}
