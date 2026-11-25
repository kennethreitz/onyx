import XCTest
@testable import OnyxCore

final class SyncVaultLibraryTests: XCTestCase {
    var tmp: URL!
    var lib: SyncVaultLibrary!
    override func setUp() {
        tmp = URL(fileURLWithPath: "/tmp/onyx-vault-library-\(UUID().uuidString)")
        lib = SyncVaultLibrary(root: tmp.appendingPathComponent("Vaults"))
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    func testFolderNames() {
        XCTAssertEqual(SyncVaultLibrary.folderName(for: "Notes", taken: []), "Notes")
        XCTAssertEqual(SyncVaultLibrary.folderName(for: "Notes", taken: ["notes"]), "Notes 2")
        XCTAssertEqual(SyncVaultLibrary.folderName(for: "Notes", taken: ["Notes", "Notes 2"]), "Notes 3")
        XCTAssertEqual(SyncVaultLibrary.folderName(for: "../../etc/passwd", taken: []), "-..-etc-passwd")
        XCTAssertEqual(SyncVaultLibrary.folderName(for: ".hidden", taken: []), "hidden")
        XCTAssertEqual(SyncVaultLibrary.folderName(for: "a:b\\c\nd", taken: []), "a-b-c-d")
        XCTAssertEqual(SyncVaultLibrary.folderName(for: "   ", taken: []), "Vault")
        XCTAssertEqual(SyncVaultLibrary.folderName(for: "..", taken: []), "Vault")
        XCTAssertEqual(SyncVaultLibrary.folderName(for: String(repeating: "x", count: 200), taken: []).count, 80)
        XCTAssertEqual(SyncVaultLibrary.folderName(for: "Café ✍️", taken: []), "Café ✍️")
    }

    func testPrepareCreatesOnceAndReusesForTheSameRemote() throws {
        let a = try lib.prepare(remoteID: "r1", name: "Notes", accountEmail: "a@example.com")
        XCTAssertEqual(a.folder, "Notes")
        XCTAssertTrue(SyncVaultLibrary.isEmptyFolder(lib.url(for: a)))
        try Data("x".utf8).write(to: lib.url(for: a).appendingPathComponent("n.md"))
        let again = try lib.prepare(remoteID: "r1", name: "Renamed remotely", accountEmail: "a@example.com")
        XCTAssertEqual(again, a, "reconnecting the same remote reuses its copy")
        let b = try lib.prepare(remoteID: "r2", name: "notes", accountEmail: "a@example.com")
        XCTAssertEqual(b.folder, "notes 2")
        XCTAssertEqual(lib.load().map(\.id), ["r1", "r2"])
        XCTAssertEqual(lib.vault(at: lib.url(for: b))?.id, "r2")
        XCTAssertEqual(lib.vault(at: URL(fileURLWithPath: lib.url(for: b).path + "/")), b)
        XCTAssertNil(lib.vault(at: tmp))
        // A stray folder that isn't in the manifest still blocks its name.
        try FileManager.default.createDirectory(at: lib.root.appendingPathComponent("Work"), withIntermediateDirectories: true)
        XCTAssertEqual(try lib.prepare(remoteID: "r3", name: "Work", accountEmail: "").folder, "Work 2")
    }

    func testRemoveLocalCopyOnlyDeletesManagedFolders() throws {
        let a = try lib.prepare(remoteID: "r1", name: "Notes", accountEmail: "")
        let b = try lib.prepare(remoteID: "r2", name: "Other", accountEmail: "")
        try Data("x".utf8).write(to: lib.url(for: a).appendingPathComponent("n.md"))
        try lib.removeLocalCopy(a)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lib.url(for: a).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lib.url(for: b).path))
        XCTAssertEqual(lib.load(), [b])

        // Not in the manifest, or tampered with: refused, nothing deleted.
        let outside = tmp.appendingPathComponent("Precious")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        var forged = b; forged.folder = "../Precious"
        XCTAssertThrowsError(try lib.removeLocalCopy(forged))
        var unknown = b; unknown.id = "nope"
        XCTAssertThrowsError(try lib.removeLocalCopy(unknown))
        var manifest = lib.load(); manifest[0].folder = "../Precious"; try lib.save(manifest)
        XCTAssertThrowsError(try lib.removeLocalCopy(manifest[0]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))

        // A managed folder replaced by a symlink to somewhere else: refused.
        manifest[0].folder = "Other"; try lib.save(manifest)
        try FileManager.default.removeItem(at: lib.url(for: b))
        try FileManager.default.createSymbolicLink(at: lib.url(for: b), withDestinationURL: outside)
        XCTAssertThrowsError(try lib.removeLocalCopy(b))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testForgetKeepsFiles() throws {
        let a = try lib.prepare(remoteID: "r1", name: "Notes", accountEmail: "")
        try Data("x".utf8).write(to: lib.url(for: a).appendingPathComponent("n.md"))
        try lib.forget(a)
        XCTAssertTrue(lib.load().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lib.url(for: a).appendingPathComponent("n.md").path))
    }
}
