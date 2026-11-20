import XCTest
@testable import OnyxCore

final class GitTextTests: XCTestCase {
    typealias G = GitText
    func testParse() {
        let c = G.parseNameStatus("M\tKnowledge/Mercury.md\nA\tDaily/2026-11-20.md\nD\tOld.md\nR100\tA.md\tFolder/A.md\n")
        XCTAssertEqual(c, [G.Change(status: "M", path: "Knowledge/Mercury.md"), G.Change(status: "A", path: "Daily/2026-11-20.md"),
                           G.Change(status: "D", path: "Old.md"), G.Change(status: "R", path: "Folder/A.md", from: "A.md")])
    }
    func testMessages() {
        XCTAssertEqual(G.commitMessage([G.Change(status: "M", path: "Knowledge/Mercury.md")]), "Edit Mercury")
        let two = G.commitMessage([G.Change(status: "M", path: "a/Mercury.md"), G.Change(status: "M", path: "b/Venus.md")])
        XCTAssertTrue(two.hasPrefix("Edit Mercury, Venus\n\nM a/Mercury.md\nM b/Venus.md"))
        let mixed = G.commitMessage([G.Change(status: "A", path: "Daily/2026-11-20.md"), G.Change(status: "M", path: "Mercury.md")])
        XCTAssertTrue(mixed.hasPrefix("Add 2026-11-20; edit Mercury"))
        XCTAssertEqual(G.commitMessage([G.Change(status: "R", path: "Notes/B.md", from: "Notes/A.md")]), "Rename A → B")
        XCTAssertEqual(G.commitMessage([G.Change(status: "R", path: "Archive/A.md", from: "Notes/A.md")]), "Move A → Archive")
        XCTAssertEqual(G.commitMessage([G.Change(status: "D", path: "Old Note.md")]), "Delete Old Note")
        let many = G.commitMessage((1...7).map { G.Change(status: "M", path: "N\($0).md") })
        XCTAssertTrue(many.hasPrefix("Edit 7 notes: N1, N2, N3, …\n\n"))
        XCTAssertTrue(G.commitMessage([G.Change(status: "D", path: "x.md")], reason: "Delete x").hasPrefix("Delete x"))
        let long = G.commitMessage([G.Change(status: "M", path: String(repeating: "Long name ", count: 12) + ".md")])
        XCTAssertLessThanOrEqual(long.split(separator: "\n").first!.count, 72)
    }
    func testErrors() {
        XCTAssertTrue(G.isNetworkError("fatal: unable to access 'https://github.com/x/y/': Could not resolve host: github.com"))
        XCTAssertTrue(G.isNetworkError("ssh: connect to host github.com port 22: Operation timed out\nfatal: Could not read from remote repository."))
        XCTAssertFalse(G.isNetworkError("error: failed to push some refs\nhint: Updates were rejected because the remote contains work"))
        XCTAssertTrue(G.isNonFastForward(" ! [rejected]        master -> master (fetch first)"))
    }
    func testConflictCopy() {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 20; c.hour = 14; c.minute = 32
        let d = Calendar.current.date(from: c)!
        XCTAssertEqual(G.conflictCopy("Knowledge/Mercury.md", date: d), "Knowledge/Mercury (conflict 2026-11-20 1432).md")
        XCTAssertEqual(G.conflictCopy("a.md", date: d, exists: { $0 == "a (conflict 2026-11-20 1432).md" }), "a (conflict 2026-11-20 1432 2).md")
    }
    func testBackoff() {
        XCTAssertEqual(G.backoff(1), 5); XCTAssertEqual(G.backoff(2), 10); XCTAssertEqual(G.backoff(3), 20); XCTAssertEqual(G.backoff(20), 300)
    }
}
