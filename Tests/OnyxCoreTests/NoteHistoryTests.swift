import XCTest
@testable import OnyxCore

final class NoteHistoryTests: XCTestCase {

    // MARK: Parse

    func testParseLogEmpty() {
        XCTAssertEqual(NoteHistory.parseLog(""), [])
        XCTAssertEqual(NoteHistory.parseLog("\n"), [])
    }

    func testParseLogRecords() {
        let date1 = NoteHistory.parseDate("2026-11-25T16:00:00-05:00")!
        let date2 = NoteHistory.parseDate("2026-11-20T10:00:00-05:00")!
        let out = """
        \u{1e}aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\u{1f}2026-11-25T16:00:00-05:00\u{1f}Ada\u{1f}Move Mercury → Knowledge
        Knowledge/Mercury.md

        \u{1e}bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\u{1f}2026-11-20T10:00:00-05:00\u{1f}Ada\u{1f}Add Mercury
        Notes/Mercury.md
        """
        let e = NoteHistory.parseLog(out)
        XCTAssertEqual(e.count, 2)
        XCTAssertEqual(e[0].hash, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        XCTAssertEqual(e[0].shortHash, "aaaaaaa")
        XCTAssertEqual(e[0].date, date1)
        XCTAssertEqual(e[0].author, "Ada")
        XCTAssertEqual(e[0].subject, "Move Mercury → Knowledge")
        XCTAssertEqual(e[0].path, "Knowledge/Mercury.md")
        XCTAssertEqual(e[1].date, date2)
        XCTAssertEqual(e[1].path, "Notes/Mercury.md")
        XCTAssertEqual(e[1].subject, "Add Mercury")
    }

    func testParseDate() {
        let d = NoteHistory.parseDate("2026-11-25T16:00:00-05:00")
        XCTAssertNotNil(d)
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 25; c.hour = 16; c.minute = 0
        c.timeZone = TimeZone(secondsFromGMT: -5 * 3600)
        let expected = Calendar(identifier: .gregorian).date(from: c)!
        XCTAssertEqual(d, expected)
        XCTAssertNotNil(NoteHistory.parseDate("2026-11-25T21:00:00Z"))
        XCTAssertNotNil(NoteHistory.parseDate("2026-11-25T16:00:00.500-05:00"))
        XCTAssertNil(NoteHistory.parseDate("nope"))
    }

    func testDetectNonRepo() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("onyx-note-history-nongit-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertFalse(NoteHistory.isRepository(dir))
        XCTAssertNil(NoteHistoryStore.detect(dir))
    }

    // MARK: Diff

    func testDiffIdenticalAndEmpty() {
        XCTAssertEqual(NoteDiff.lines(old: "", new: ""), [])
        XCTAssertEqual(NoteDiff.lines(old: "a\nb\n", new: "a\nb\n"), [.same("a"), .same("b")])
        XCTAssertEqual(NoteDiff.unified(old: "a\n", new: "a\n"), "")
        XCTAssertTrue(NoteDiff.isIdentical("x", "x"))
        XCTAssertFalse(NoteDiff.isIdentical("x", "y"))
    }

    func testDiffInsertDeleteReplace() {
        XCTAssertEqual(NoteDiff.lines(old: "", new: "a\nb"), [.insert("a"), .insert("b")])
        XCTAssertEqual(NoteDiff.lines(old: "a\nb", new: ""), [.delete("a"), .delete("b")])
        XCTAssertEqual(
            NoteDiff.lines(old: "keep\nold\nkeep", new: "keep\nnew\nkeep"),
            [.same("keep"), .delete("old"), .insert("new"), .same("keep")]
        )
        let u = NoteDiff.unified(old: "a\nb\n", new: "a\nc\n", oldLabel: "then", newLabel: "now")
        XCTAssertTrue(u.hasPrefix("--- then\n+++ now\n"))
        XCTAssertTrue(u.contains(" a\n"))
        XCTAssertTrue(u.contains("-b\n"))
        XCTAssertTrue(u.contains("+c\n"))
    }

    func testDiffPrefixSuffixAndMiddle() {
        let old = (1...10).map { "line \($0)" }.joined(separator: "\n")
        var parts = (1...10).map { "line \($0)" }
        parts[4] = "changed"
        let new = parts.joined(separator: "\n")
        let rows = NoteDiff.lines(old: old, new: new)
        XCTAssertEqual(rows[0], .same("line 1"))
        XCTAssertEqual(rows[3], .same("line 4"))
        XCTAssertEqual(rows[4], .delete("line 5"))
        XCTAssertEqual(rows[5], .insert("changed"))
        XCTAssertEqual(rows[6], .same("line 6"))
        XCTAssertEqual(rows.last, .same("line 10"))
    }

    // MARK: Real git repo

    func testRepoHistoryFollowRestoreIsReadOnly() throws {
        try skipIfNoGit()
        try withRepo { dir, store in
            func write(_ rel: String, _ text: String) throws {
                let url = dir.appendingPathComponent(rel)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: url, atomically: true, encoding: .utf8)
            }
            try write("Notes/Mercury.md", "one\n")
            git(dir, ["add", "Notes/Mercury.md"])
            git(dir, ["commit", "-m", "Add Mercury"], date: "2026-11-20T10:00:00-05:00")

            try write("Notes/Mercury.md", "one\ntwo\n")
            git(dir, ["add", "Notes/Mercury.md"])
            git(dir, ["commit", "-m", "Edit Mercury"], date: "2026-11-25T15:00:00-05:00")

            try FileManager.default.createDirectory(at: dir.appendingPathComponent("Knowledge"), withIntermediateDirectories: true)
            git(dir, ["mv", "Notes/Mercury.md", "Knowledge/Mercury.md"])
            git(dir, ["commit", "-m", "Move Mercury → Knowledge"], date: "2026-11-25T16:00:00-05:00")

            let entries = store.entries(for: "Knowledge/Mercury.md")
            XCTAssertEqual(entries.count, 3, entries.map(\.subject).description)
            XCTAssertEqual(entries[0].subject, "Move Mercury → Knowledge")
            XCTAssertEqual(entries[0].author, "Ada")
            XCTAssertEqual(entries[0].path, "Knowledge/Mercury.md")
            XCTAssertEqual(entries[0].date, NoteHistory.parseDate("2026-11-25T16:00:00-05:00"))
            XCTAssertEqual(entries[1].subject, "Edit Mercury")
            XCTAssertEqual(entries[1].path, "Notes/Mercury.md")
            XCTAssertEqual(entries[2].subject, "Add Mercury")
            XCTAssertEqual(entries[2].path, "Notes/Mercury.md")

            XCTAssertEqual(store.content(of: entries[0]), .text("one\ntwo\n"))
            XCTAssertEqual(store.content(of: entries[1]), .text("one\ntwo\n"))
            XCTAssertEqual(store.content(of: entries[2]), .text("one\n"))

            // Reading history never checks out or resets the work tree.
            let latest = try String(contentsOf: dir.appendingPathComponent("Knowledge/Mercury.md"), encoding: .utf8)
            XCTAssertEqual(latest, "one\ntwo\n")
            XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Notes/Mercury.md").path))
            let head = git(dir, ["rev-parse", "HEAD"]).out.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(entries[0].hash, head)

            // An uncommitted edit stays put after we read an older version.
            try write("Knowledge/Mercury.md", "one\ntwo\nunsaved\n")
            XCTAssertEqual(store.content(of: entries[2]), .text("one\n"))
            let still = try String(contentsOf: dir.appendingPathComponent("Knowledge/Mercury.md"), encoding: .utf8)
            XCTAssertEqual(still, "one\ntwo\nunsaved\n")
            let headAfter = git(dir, ["rev-parse", "HEAD"]).out.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(headAfter, head)

            // A path with no commits, and a missing blob.
            XCTAssertEqual(store.entries(for: "Never.md"), [])
            let ghost = NoteHistoryEntry(hash: entries[0].hash, date: entries[0].date, author: "Ada", subject: "x", path: "nope.md")
            XCTAssertEqual(store.content(of: ghost), .missing)

            // "Restore" is just the historical text — the caller writes the editor, not git.
            if case .text(let restored) = store.content(of: entries[2]) {
                XCTAssertEqual(restored, "one\n")
                XCTAssertNotEqual(restored, still)
            } else {
                XCTFail("expected text")
            }
        }
    }

    func testUntrackedNoteHasNoHistory() throws {
        try skipIfNoGit()
        try withRepo { dir, store in
            let url = dir.appendingPathComponent("Draft.md")
            try "draft\n".write(to: url, atomically: true, encoding: .utf8)
            XCTAssertEqual(store.entries(for: "Draft.md"), [])
        }
    }

    // MARK: Helpers

    private func skipIfNoGit() throws {
        if NoteHistory.gitBinary() == nil {
            throw XCTSkip("git is not installed")
        }
    }

    private func withRepo(_ body: (URL, NoteHistoryStore) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("onyx-note-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        git(dir, ["init", "-q"])
        git(dir, ["config", "user.name", "Ada"])
        git(dir, ["config", "user.email", "ada@example.com"])
        git(dir, ["config", "commit.gpgsign", "false"])
        git(dir, ["config", "init.defaultBranch", "main"])
        // Older git init may have already created master; either is fine.
        guard let store = NoteHistoryStore.detect(dir) else {
            XCTFail("expected a store for \(dir.path)")
            return
        }
        try body(dir, store)
    }

    @discardableResult
    private func git(_ dir: URL, _ args: [String], date: String? = nil) -> NoteHistoryStore.Out {
        var env: [String: String] = [:]
        if let date {
            env["GIT_AUTHOR_DATE"] = date
            env["GIT_COMMITTER_DATE"] = date
        }
        let store = NoteHistoryStore(root: dir, git: NoteHistory.gitBinary()!)
        // run() doesn't take env, so use Process here for dates.
        if env.isEmpty {
            let r = store.run(args)
            XCTAssertEqual(r.code, 0, "git \(args.joined(separator: " ")) failed:\n\(r.out)")
            return r
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: store.git)
        p.arguments = ["-C", dir.path] + args
        var e = ProcessInfo.processInfo.environment
        e["GIT_TERMINAL_PROMPT"] = "0"
        e["GIT_EDITOR"] = "true"
        e["commit.gpgsign"] = "false"
        for (k, v) in env { e[k] = v }
        p.environment = e
        let o = Pipe()
        p.standardOutput = o; p.standardError = o; p.standardInput = FileHandle.nullDevice
        try! p.run(); p.waitUntilExit()
        let data = o.fileHandleForReading.readDataToEndOfFile()
        let out = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(p.terminationStatus, 0, "git \(args.joined(separator: " ")) failed:\n\(out)")
        return .init(code: p.terminationStatus, out: out, data: data)
    }
}
