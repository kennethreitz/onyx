import XCTest
@testable import OnyxCore

final class FindReplaceTests: XCTestCase {

    let opts = FindReplace.Options()

    func found(of q: String, replacement: String, in s: String, path: String = "", options: FindReplace.Options = FindReplace.Options()) -> [FindReplace.Match] {
        guard let ms = FindReplace.matches(of: q, replacement: replacement, in: s, path: path, options: options) else {
            XCTFail("unexpected invalid pattern: \(q)")
            return []
        }
        return ms
    }

    func ranges(_ q: String, in s: String, options: FindReplace.Options = FindReplace.Options()) -> [NSRange] {
        found(of: q, replacement: "", in: s, options: options).map(\.range)
    }

    func testLiteralCaseAndNonOverlapping() {
        let s = "Stone stone STONE aaaa (x)"
        XCTAssertEqual(ranges("stone", in: s).count, 3)
        XCTAssertEqual(ranges("stone", in: s, options: .init(matchCase: true)).map(\.location), [6])
        XCTAssertEqual(ranges("aa", in: s).count, 2)
        XCTAssertEqual(ranges("(x)", in: s).count, 1)   // literal, not regex
        XCTAssertEqual(ranges("", in: s).count, 0)
        XCTAssertEqual(ranges("$1", in: "pay $1 now").count, 1)
    }

    func testWholeWord() {
        let s = "cat catalog cat. scatter cat"
        let w = FindReplace.Options(wholeWord: true)
        let ms = found(of: "cat", replacement: "dog", in: s, options: w)
        XCTAssertEqual(ms.map(\.text), ["cat", "cat", "cat"])
        XCTAssertEqual(ms.map(\.range.location), [0, 12, 25])
        // punctuation and start/end are boundaries; letters/digits/underscore are not
        XCTAssertEqual(ranges("well", in: "well-known well", options: w).count, 2)
        XCTAssertEqual(ranges("a_b", in: "a_b a b", options: w).count, 1)
    }

    func testRegexAndCaptureGroups() {
        let s = "alpha-1 beta-2"
        let o = FindReplace.Options(regex: true)
        let ms = found(of: #"(\w+)-(\d+)"#, replacement: "$2:$1", in: s, options: o)
        XCTAssertEqual(ms.map(\.replacement), ["1:alpha", "2:beta"])
        let slash = found(of: #"(\w+)-(\d+)"#, replacement: #"\2:\1"#, in: s, options: o)
        XCTAssertEqual(slash.map(\.replacement), ["1:alpha", "2:beta"])
        let whole = found(of: #"alpha-\d+"#, replacement: "[$0]", in: s, options: o)
        XCTAssertEqual(whole.first?.replacement, "[alpha-1]")
        let amp = found(of: #"alpha-\d+"#, replacement: #"\&!"#, in: s, options: o)
        XCTAssertEqual(amp.first?.replacement, "alpha-1!")
    }

    func testLiteralDoesNotInterpolateDollars() {
        let s = "name"
        let ms = found(of: "name", replacement: "$1 or $0", in: s)
        XCTAssertEqual(ms.first?.replacement, "$1 or $0")
    }

    func testInvalidRegex() {
        XCTAssertNil(FindReplace.matches(of: "(", replacement: "", in: "x", options: .init(regex: true)))
        let preview = FindReplace.preview(query: "(", replacement: "y",
                                          notes: [(path: "A.md", text: "x")],
                                          options: .init(regex: true))
        XCTAssertEqual(preview.error, "Invalid regular expression.")
        XCTAssertTrue(preview.groups.isEmpty)
    }

    func testZeroLengthRegexIsSkipped() {
        let s = "ab"
        let ms = found(of: "x?", replacement: "z", in: s, options: .init(regex: true))
        // `x?` can match empty strings between characters; those are dropped. "no x" matches are empty.
        XCTAssertTrue(ms.allSatisfy { $0.range.length > 0 })
        XCTAssertTrue(ms.isEmpty || ms.allSatisfy { $0.text == "x" })
    }

    func testFrontmatterInclusion() {
        let s = """
        ---
        title: Stone
        ---
        The stone at the door.
        """
        let all = found(of: "stone", replacement: "rock", in: s)
        XCTAssertEqual(all.count, 2)
        let body = found(of: "stone", replacement: "rock", in: s,
                                            options: .init(includeFrontmatter: false))
        XCTAssertEqual(body.count, 1)
        XCTAssertTrue(body[0].lineText.contains("door"))
        XCTAssertEqual(body[0].replacement, "rock")
    }

    func testScopeFolderAndNote() {
        XCTAssertTrue(FindReplace.Scope.vault.contains("A.md"))
        XCTAssertTrue(FindReplace.Scope.vault.contains("Knowledge/Tarot.md"))
        XCTAssertTrue(FindReplace.Scope.note("A.md").contains("A.md"))
        XCTAssertFalse(FindReplace.Scope.note("A.md").contains("B.md"))
        XCTAssertTrue(FindReplace.Scope.folder("Knowledge").contains("Knowledge/Tarot.md"))
        XCTAssertTrue(FindReplace.Scope.folder("Knowledge").contains("Knowledge/Deck/Card.md"))
        XCTAssertFalse(FindReplace.Scope.folder("Knowledge").contains("Journal.md"))
        XCTAssertFalse(FindReplace.Scope.folder("Knowledge").contains("Knowledgeable.md"))
        XCTAssertTrue(FindReplace.Scope.folder("").contains("Root.md"))
        XCTAssertFalse(FindReplace.Scope.folder("").contains("Knowledge/Tarot.md"))
    }

    func testPreviewGroupsAndSelectedPlan() {
        let notes = [
            (path: "A.md", text: "alpha alpha beta"),
            (path: "B.md", text: "alpha"),
            (path: "C.md", text: "zeta")
        ]
        let preview = FindReplace.preview(query: "alpha", replacement: "A", notes: notes, options: .init())
        XCTAssertEqual(preview.fileCount, 2)
        XCTAssertEqual(preview.matchCount, 3)
        XCTAssertEqual(preview.groups.map(\.path), ["A.md", "B.md"])
        XCTAssertEqual(preview.groups[0].matches.count, 2)
        XCTAssertFalse(preview.truncated)

        let selected = [preview.groups[0].matches[1], preview.groups[1].matches[0]]   // 2nd in A, the one in B
        let texts = Dictionary(uniqueKeysWithValues: notes.map { ($0.path, $0.text) })
        let plan = FindReplace.plan(matches: selected, texts: texts)
        XCTAssertEqual(plan.fileCount, 2)
        XCTAssertEqual(plan.matchCount, 2)
        XCTAssertEqual(plan.edits[0].after, "alpha A beta")
        XCTAssertEqual(plan.edits[1].after, "A")
        XCTAssertEqual(plan.edits[0].before, "alpha alpha beta")
    }

    func testApplyAllAndReverseOrder() {
        let text = "one two one"
        let ms = found(of: "one", replacement: "ONE", in: text)
        XCTAssertEqual(FindReplace.applying(ms, to: text), "ONE two ONE")
        // Longer replacement must not shift later (already-applied-from-the-right) ranges
        let grown = found(of: "one", replacement: "oneself", in: text)
        XCTAssertEqual(FindReplace.applying(grown, to: text), "oneself two oneself")
    }

    func testRegexApplyAcrossFile() {
        let text = "See [[Alpha]] and [[Beta]]."
        let o = FindReplace.Options(regex: true)
        let ms = found(of: #"\[\[(\w+)\]\]"#, replacement: "[[$1.md]]", in: text, options: o)
        XCTAssertEqual(FindReplace.applying(ms, to: text), "See [[Alpha.md]] and [[Beta.md]].")
    }

    func testUTF16Ranges() {
        let s = "🜍 Mercury 🜍 mercury"
        let ms = found(of: "mercury", replacement: "Hg", in: s)
        XCTAssertEqual(ms.count, 2)
        XCTAssertEqual((s as NSString).substring(with: ms[1].range), "mercury")
        XCTAssertEqual(FindReplace.applying(ms, to: s), "🜍 Hg 🜍 Hg")
    }

    func testLineNumbersAndContext() {
        let s = "first\nsecond stone\nthird"
        let ms = found(of: "stone", replacement: "rock", in: s)
        XCTAssertEqual(ms[0].line, 2)
        XCTAssertEqual(ms[0].prefix, "second ")
        XCTAssertEqual(ms[0].suffix, "")
        XCTAssertEqual(ms[0].lineText, "second stone")
    }

    func testPreviewCapTruncates() {
        let text = Array(repeating: "x", count: 20).joined(separator: " ")
        let preview = FindReplace.preview(query: "x", replacement: "y",
                                          notes: [(path: "A.md", text: text)],
                                          options: .init(), cap: 5)
        XCTAssertEqual(preview.matchCount, 5)
        XCTAssertTrue(preview.truncated)
    }

    func testSnapshotPreviewUsesOverridesAndScope() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("onyx-findreplace-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try! "alpha in root".write(to: dir.appendingPathComponent("Root.md"), atomically: true, encoding: .utf8)
        try! FileManager.default.createDirectory(at: dir.appendingPathComponent("Sub"), withIntermediateDirectories: true)
        try! "alpha in sub".write(to: dir.appendingPathComponent("Sub/Note.md"), atomically: true, encoding: .utf8)
        var snap = VaultSnapshot(root: dir)
        snap.refresh(paths: ["Root.md", "Sub/Note.md"])

        let vault = FindReplace.preview(query: "alpha", replacement: "A", in: snap, options: .init())
        XCTAssertEqual(vault.matchCount, 2)

        let folder = FindReplace.preview(query: "alpha", replacement: "A", in: snap,
                                         options: .init(scope: .folder("Sub")))
        XCTAssertEqual(folder.groups.map(\.path), ["Sub/Note.md"])

        let note = FindReplace.preview(query: "alpha", replacement: "A", in: snap,
                                       options: .init(scope: .note("Root.md")))
        XCTAssertEqual(note.matchCount, 1)

        // Open editor buffer wins over the snapshot
        let live = FindReplace.preview(query: "alpha", replacement: "A", in: snap,
                                       options: .init(), contents: ["Root.md": "nope", "Sub/Note.md": "alpha alpha"])
        XCTAssertEqual(live.matchCount, 2)
        XCTAssertEqual(live.groups.map(\.path), ["Sub/Note.md"])
        XCTAssertEqual(live.groups[0].matches.count, 2)
    }

    func testDollarTemplate() {
        XCTAssertEqual(FindReplace.dollarTemplate(#"\1-\2 \& ok"#), "$1-$2 $0 ok")
        XCTAssertEqual(FindReplace.dollarTemplate(#"$& and $1"#), "$0 and $1")
        XCTAssertEqual(FindReplace.dollarTemplate(#"\\1"#), #"\1"#)   // escaped backslash then 1? \\ is one backslash, then 1 stays
    }

    func testNoopPlanIsEmpty() {
        let text = "same"
        let ms = found(of: "same", replacement: "same", in: text)
        let plan = FindReplace.plan(matches: ms, texts: ["A.md": text])
        XCTAssertTrue(plan.edits.isEmpty)
        XCTAssertEqual(plan.matchCount, 0)
    }
}
