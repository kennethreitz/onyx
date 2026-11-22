import XCTest
@testable import OnyxCore

/// The fast paths added for speed must give the same answers as the slow ones.
final class PerformanceTests: XCTestCase {
    func snapshot(_ files: [String: String]) -> VaultSnapshot {
        var snap = VaultSnapshot(root: URL(fileURLWithPath: "/tmp/none"))
        for (p, c) in files { snap.notes[p] = VaultSnapshot.makeRecord(rel: p, content: c) }
        snap.rebuildDerived()
        return snap
    }

    func assertSameDerived(_ a: VaultSnapshot, _ b: VaultSnapshot, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.backlinks, b.backlinks, "backlinks", file: file, line: line)
        XCTAssertEqual(a.unresolved, b.unresolved, "unresolved", file: file, line: line)
        XCTAssertEqual(a.tags, b.tags, "tags", file: file, line: line)
        XCTAssertEqual(a.relationsOut, b.relationsOut, "relationsOut", file: file, line: line)
        XCTAssertEqual(a.relationsIn, b.relationsIn, "relationsIn", file: file, line: line)
        XCTAssertEqual(a.tree, b.tree, "tree", file: file, line: line)
    }

    func testIncrementalUpdateMatchesFullRebuild() {
        let files = [
            "Home.md": "# Home\n[[A]] [[B]] #start\n[[Missing]]",
            "A.md": "partOf:: [[Home]]\nrelated:: [[B]]\n#tag/sub\n[md](B.md)",
            "B.md": "---\ntags: [x, y]\npartOf: \"[[Home]]\"\n---\n[[A#Heading|alias]]",
            "Sub/C.md": "[[A]] [[Ghost]] #c",
        ]
        let edits = [
            ("A.md", "no links now"),
            ("A.md", "partOf:: [[B]]\npartOf:: [[Home]]\n[[Sub/C]] #new"),
            ("B.md", "---\ntags: [z]\n---\n[[Ghost]] [[Other ghost]] related:: [[Home]]"),
            ("Home.md", ""),
            ("Sub/C.md", "```\n[[A]]\n```\n[[Home]] %% [[B]] %%"),
        ]
        var inc = snapshot(files)
        for (p, c) in edits {
            inc.update(path: p, content: c)
            var full = inc
            full.rebuildDerived()
            assertSameDerived(inc, full)
        }
    }

    func testRefreshOfEditedFilesIsIncrementalAndExact() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("onyx-perf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("F"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func write(_ p: String, _ s: String) throws { try s.write(to: dir.appendingPathComponent(p), atomically: true, encoding: .utf8) }
        try write("One.md", "[[Two]] #a"); try write("F/Two.md", "partOf:: [[One]]")
        var snap = VaultSnapshot.scan(root: dir)
        try write("One.md", "[[Nope]] #b")
        snap.refresh(paths: ["One.md"])
        var full = snap; full.rebuildDerived()
        assertSameDerived(snap, full)
        XCTAssertEqual(snap.unresolved["Nope"], ["One.md"])
        XCTAssertNil(snap.backlinks["F/Two.md"])
        try write("F/Three.md", "[[One]]")   // a new file is structural: full rebuild
        snap.refresh(paths: ["F/Three.md"])
        XCTAssertEqual(snap.backlinks["One.md"], ["F/Three.md", "F/Two.md"])
        XCTAssertTrue(snap.tree.children?.contains { $0.path == "F" } ?? false)
    }

    func testSearchScoresAndSnippets() {
        let s = snapshot([
            "Cats.md": "cats cats cats\nnothing\nmore cats here",
            "Dogs.md": "a dog and a cat",
            "Other.md": "nothing at all",
        ])
        let hits = s.search("cat")
        XCTAssertEqual(hits.map(\.path), ["Cats.md", "Dogs.md"])
        XCTAssertEqual(hits[0].score, 40 + 4)
        XCTAssertEqual(hits[0].snippets, ["cats cats cats", "more cats here"])
        XCTAssertEqual(s.search("cat dog").map(\.path), ["Dogs.md"])
        XCTAssertEqual(ByteSearch.count("aa", in: "aaaaa", cap: 20), 2)
        XCTAssertEqual(ByteSearch.count("é", in: "café é", cap: 1), 1)
        XCTAssertEqual(ByteSearch.count("x", in: "", cap: 5), 0)
    }

    func testBacklinkContextSkipsOnlyImpossibleLines() {
        let s = snapshot([
            "Target Note.md": "# T",
            "Src.md": "intro\nsee [[target note|here]]\nlater [[Target Note]]",
            "Enc.md": "x\n[[Target%20Note]]",
            "Field.md": "partOf:: Target Note",
        ])
        let b = s.backlinks(to: "Target Note.md")
        XCTAssertEqual(b.map(\.source), ["Enc.md", "Field.md", "Src.md", "Src.md"])
        XCTAssertEqual(b.filter { $0.source == "Src.md" }.map(\.line), [1, 2])
        XCTAssertEqual(b.first { $0.source == "Enc.md" }?.line, 1)
        XCTAssertEqual(b.first { $0.source == "Field.md" }?.context, "partOf:: Target Note")
    }

    func testDataviewNormAndDates() {
        XCTAssertEqual(Dataview.norm("Due Date_x"), "due-date-x")
        XCTAssertEqual(Dataview.norm("plain"), "plain")
        XCTAssertNotNil(DVDate.parse("2024-03-05"))
        XCTAssertNotNil(DVDate.parse("2024-03-05T10:20"))
        XCTAssertNil(DVDate.parse("alter"))
        XCTAssertNil(DVDate.parse("2024"))
    }

    func testLineRangesMatchNSString() {
        for text in ["", "a", "a\n", "a\nb", "a\r\nb\rc\u{2028}d\u{2029}e\u{85}f\n\n", "\n\n# h\n```\ncode\n```\n", "emoji 🙂\r\n🙂"] {
            let ns = text as NSString
            var want: [NSRange] = [], loc = 0
            while loc < ns.length { let r = ns.lineRange(for: NSRange(location: loc, length: 0)); want.append(r); loc = NSMaxRange(r) }
            XCTAssertEqual(NoteParser.lineRanges(Array(text.utf16)), want, text.debugDescription)
        }
        let doc = "x\n  ```swift\n# not heading\nkey:: [[A]]\n  ```\n# Real\nk:: v\n~~~\nz:: 1\n"
        XCTAssertEqual(NoteParser.codeRanges(doc).count, 2)
        XCTAssertEqual(NoteParser.parseHeadings(doc).map(\.text), ["Real"])
        XCTAssertEqual(NoteParser.parseHeadings(doc).map(\.line), [5])
        XCTAssertEqual(InlineFields.parse(doc).map(\.key), ["k"])
    }
}
