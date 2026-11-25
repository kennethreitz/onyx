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

    func edit(_ path: String, old: String?, new: String?, status: Character = "M") -> G.FileEdit {
        G.FileEdit(change: G.Change(status: status, path: path), oldText: old, newText: new)
    }

    func testDescriptiveSingleEdit() {
        let heading = edit("Knowledge/Mercury.md",
                           old: "# Mercury\n\nThe messenger.\n",
                           new: "# Mercury\n\n## Orbit\n\nThe messenger.\n")
        XCTAssertEqual(G.commitMessage([heading]), "Update Mercury: add Orbit")

        let task = edit("Mercury.md",
                        old: "- [ ] write tests\n",
                        new: "- [x] write tests\n")
        XCTAssertEqual(G.commitMessage([task]), "Update Mercury: check 1 task")

        let fm = edit("Mercury.md",
                      old: "---\nstatus: draft\nupdated: 2026-01-01\n---\n\nBody.\n",
                      new: "---\nstatus: published\nupdated: 2026-11-25\n---\n\nBody.\n")
        XCTAssertEqual(G.commitMessage([fm]), "Update Mercury: change status")

        let link = edit("Mercury.md",
                        old: "See also.\n",
                        new: "See also [[Venus]].\n")
        XCTAssertEqual(G.commitMessage([link]), "Update Mercury: add link to Venus")
    }

    func testDescriptiveKeepsGenericEditWithoutStructure() {
        let prose = edit("Mercury.md", old: "The messenger.\n", new: "The messenger of the gods.\n")
        XCTAssertEqual(G.commitMessage([prose]), "Edit Mercury")
    }

    func testDescriptiveMultiFileBody() {
        let a = edit("Mercury.md", old: "# Mercury\n", new: "# Mercury\n\n## Orbit\n")
        let b = edit("Venus.md", old: "- [ ] observe\n", new: "- [x] observe\n")
        let c = edit("Mars.md", old: "plain\n", new: "plain [[Venus]]\n")
        let msg = G.commitMessage([a, b, c])
        XCTAssertTrue(msg.hasPrefix("Edit Mercury, Venus, Mars\n\n"), msg)
        XCTAssertTrue(msg.contains("Mercury: add Orbit"), msg)
        XCTAssertTrue(msg.contains("Venus: check 1 task"), msg)
        XCTAssertTrue(msg.contains("Mars: add link to Venus"), msg)
        let subject = String(msg.split(separator: "\n").first!)
        XCTAssertLessThanOrEqual(subject.count, 72)
    }

    func testDescriptiveAddDeleteRenameUnchanged() {
        XCTAssertEqual(G.commitMessage([G.Change(status: "A", path: "Venus.md")]), "Add Venus")
        XCTAssertEqual(G.commitMessage([edit("Venus.md", old: nil, new: "# Venus\n\n## Atmosphere\n", status: "A")]), "Add Venus")
        XCTAssertEqual(G.commitMessage([G.Change(status: "D", path: "Old Note.md")]), "Delete Old Note")
        XCTAssertEqual(G.commitMessage([G.Change(status: "R", path: "Notes/B.md", from: "Notes/A.md")]), "Rename A → B")
    }

    func testDescriptiveSubjectStaysShort() {
        let longHeads = (1...8).map { "A very long heading name \($0) that should be counted" }
        let old = "# Note\n"
        let new = "# Note\n\n" + longHeads.map { "## \($0)\n" }.joined()
        let msg = G.commitMessage([edit("Note.md", old: old, new: new)])
        let subject = String(msg.split(separator: "\n").first!)
        XCTAssertLessThanOrEqual(subject.count, 72)
        XCTAssertTrue(subject.hasPrefix("Update Note:"), subject)
        XCTAssertTrue(subject.contains("headings"), subject)
    }
}
