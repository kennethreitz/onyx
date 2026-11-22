import XCTest
@testable import OnyxCore

final class FoldingTests: XCTestCase {
    private func hidden(_ text: String, _ r: FoldRegion) -> String { (text as NSString).substring(with: r.hidden) }
    private func header(_ text: String, _ r: FoldRegion) -> String { (text as NSString).substring(with: r.header) }
    private func headings(_ text: String) -> [FoldRegion] { MarkdownFolds.regions(in: text).filter { $0.kind == .heading } }

    func testNestedHeadingsCloseAtSameOrHigherLevel() {
        let t = "# A\na\n## B\nb\n### C\nc\n## D\nd\n# E\ne"
        let rs = headings(t)
        XCTAssertEqual(rs.map { header(t, $0) }, ["# A", "## B", "### C", "## D", "# E"])
        XCTAssertEqual(hidden(t, rs[0]), "\na\n## B\nb\n### C\nc\n## D\nd")
        XCTAssertEqual(hidden(t, rs[1]), "\nb\n### C\nc")
        XCTAssertEqual(hidden(t, rs[2]), "\nc")
        XCTAssertEqual(hidden(t, rs[3]), "\nd")
        XCTAssertEqual(hidden(t, rs[4]), "\ne")
        XCTAssertEqual(rs.map(\.level), [1, 2, 3, 2, 1])
        XCTAssertEqual(rs.map(\.line), [0, 2, 4, 6, 8])
    }

    func testHiddenTextKeepsTheLastLineBreakAndTrailingBlankLinesVisible() {
        let t = "# A\nbody\n\n\n# B\nx\n"
        let rs = headings(t)
        XCTAssertEqual(hidden(t, rs[0]), "\nbody")
        XCTAssertEqual(hidden(t, rs[1]), "\nx")   // final newline stays: the heading line still ends
    }

    func testEOFWithoutNewlineAndEmptySections() {
        XCTAssertEqual(headings("# A\nlast").map { hidden("# A\nlast", $0) }, ["\nlast"])
        XCTAssertTrue(headings("# A").isEmpty)
        XCTAssertTrue(headings("# A\n").isEmpty)
        XCTAssertTrue(headings("# A\n\n\n# B\n").isEmpty)   // blank-only section: no chevron
        XCTAssertTrue(MarkdownFolds.regions(in: "").isEmpty)
    }

    func testCodeFencesAreOpaque() {
        let t = "# A\n```python\n# not a heading\n## nor this\n```\n## B\nb\n~~~\n# x\n~~~\n"
        let rs = headings(t)
        XCTAssertEqual(rs.map { header(t, $0) }, ["# A", "## B"])
        XCTAssertEqual(hidden(t, rs[0]), "\n```python\n# not a heading\n## nor this\n```\n## B\nb\n~~~\n# x\n~~~")
    }

    func testFenceRulesLongerClosersAndUnclosedFence() {
        let t = "# A\n````\n```\n# inside\n````\n# B\nb\n"
        XCTAssertEqual(headings(t).map { header(t, $0) }, ["# A", "# B"])
        let open = "# A\nx\n```\n# never closed\n"
        XCTAssertEqual(headings(open).map { header(open, $0) }, ["# A"])
        XCTAssertEqual(hidden(open, headings(open)[0]), "\nx\n```\n# never closed")
    }

    func testFrontmatterIsNeverFoldedOrParsed() {
        let t = "---\ntitle: x\n# comment: y\n---\n# A\nbody\n"
        let rs = headings(t)
        XCTAssertEqual(rs.map { header(t, $0) }, ["# A"])
        XCTAssertEqual(rs[0].line, 4)
    }

    func testSetextHeadings() {
        let t = "Title\n=====\nintro\nPart\n---\nmore\n"
        let rs = headings(t)
        XCTAssertEqual(rs.map { header(t, $0) }, ["Title\n=====", "Part\n---"])
        XCTAssertEqual(rs.map(\.level), [1, 2])
        XCTAssertEqual(hidden(t, rs[0]), "\nintro\nPart\n---\nmore")
        XCTAssertEqual(hidden(t, rs[1]), "\nmore")
    }

    func testThematicBreaksListsAndQuotesAreNotSetext() {
        for t in ["para\n\n---\nafter\n", "- item\n---\nafter\n", "> quote\n---\nafter\n", "***\n---\nx\n"] {
            XCTAssertTrue(headings(t).isEmpty, t)
        }
    }

    func testATXRulesMatchMarkdown() {
        XCTAssertTrue(headings("#tag\nbody\n").isEmpty)
        XCTAssertTrue(headings("####### seven\nbody\n").isEmpty)
        XCTAssertTrue(headings("    # indented code\nbody\n").isEmpty)
        XCTAssertEqual(headings("   ## three spaces\nbody\n").count, 1)
        XCTAssertEqual(headings("#\nbody\n").count, 1)   // empty ATX heading is still a heading
    }

    func testCRLF() {
        let t = "# A\r\nbody\r\n# B\r\nx\r\n"
        let rs = headings(t)
        XCTAssertEqual(hidden(t, rs[0]), "\r\nbody")
        XCTAssertEqual(header(t, rs[0]), "# A")
    }

    func testListsFoldOnlyWithNestedItems() {
        let t = "- a\n  - b\n    - c\n  - d\n- e\n  continuation\n- f\n"
        let rs = MarkdownFolds.regions(in: t).filter { $0.kind == .list }
        XCTAssertEqual(rs.map { header(t, $0) }, ["- a", "  - b"])
        XCTAssertEqual(hidden(t, rs[0]), "\n  - b\n    - c\n  - d")
        XCTAssertEqual(hidden(t, rs[1]), "\n    - c")
    }

    func testListsInsideHeadingsAndEndingAtHeadings() {
        let t = "# H\n1. one\n   - nested\n2. two\n## Next\n- x\n\t- tab nested\n"
        let rs = MarkdownFolds.regions(in: t)
        XCTAssertEqual(rs.map { header(t, $0) }, ["# H", "1. one", "## Next", "- x"])
        XCTAssertEqual(hidden(t, rs[1]), "\n   - nested")
        XCTAssertEqual(hidden(t, rs[3]), "\n\t- tab nested")
    }

    func testListLooseBlankLinesAndListsInCode() {
        let t = "- a\n\n  - b\n\nafter\n```\n- x\n  - y\n```\n"
        let rs = MarkdownFolds.regions(in: t)
        XCTAssertEqual(rs.map { header(t, $0) }, ["- a"])
        XCTAssertEqual(hidden(t, rs[0]), "\n\n  - b")
    }

    func testAnchorsAreSignaturePlusOccurrence() {
        let t = "## Notes\na\n## Notes\nb\n"
        let rs = headings(t)
        XCTAssertEqual(rs.map(\.anchor), [FoldAnchor(signature: "heading:## Notes", occurrence: 0), FoldAnchor(signature: "heading:## Notes", occurrence: 1)])
    }

    func testUnicodeOffsetsAreUTF16() {
        let t = "# Café 🌿\nbody 🎉\n# B\nx"
        let rs = headings(t)
        XCTAssertEqual(header(t, rs[0]), "# Café 🌿")
        XCTAssertEqual(hidden(t, rs[0]), "\nbody 🎉")
    }

    // MARK: edit remapping

    private func apply(_ text: String, _ range: NSRange, _ s: String) -> (String, NSRange, Int) {
        let new = (text as NSString).replacingCharacters(in: range, with: s)
        return (new, NSRange(location: range.location, length: (s as NSString).length), (s as NSString).length - range.length)
    }
    private func remap(_ text: String, fold: String, _ range: NSRange, _ s: String) -> [String] {
        let rs = MarkdownFolds.regions(in: text)
        let f = rs.filter { header(text, $0) == fold }
        let (new, edited, delta) = apply(text, range, s)
        let nr = MarkdownFolds.regions(in: new)
        let anchors = FoldEdits.remap(f, edit: edited, delta: delta, into: nr)
        return nr.filter { anchors.contains($0.anchor) }.map { header(new, $0) }
    }

    func testEditsAboveShiftFolds() {
        let t = "intro\n# A\nbody\n"
        XCTAssertEqual(remap(t, fold: "# A", NSRange(location: 0, length: 0), "more\n\n"), ["# A"])
        XCTAssertEqual(remap(t, fold: "# A", NSRange(location: 0, length: 6), ""), ["# A"])
    }

    func testEditingTheHeadingKeepsTheFold() {
        let t = "# A\nbody\n"
        XCTAssertEqual(remap(t, fold: "# A", NSRange(location: 3, length: 0), "BC"), ["# ABC"])
        XCTAssertEqual(remap(t, fold: "# A", NSRange(location: 0, length: 0), "#"), ["## A"])
        XCTAssertEqual(remap(t, fold: "# A", NSRange(location: 0, length: 3), "## Renamed"), ["## Renamed"])
        XCTAssertEqual(remap(t, fold: "# A", NSRange(location: 0, length: 0), "\n"), ["# A"])   // ↩ before it
    }

    func testDeletingTheHeadingDropsTheFold() {
        let t = "x\n# A\nbody\n# B\nb\n"
        XCTAssertEqual(remap(t, fold: "# A", NSRange(location: 2, length: 4), ""), [])          // whole line
        XCTAssertEqual(remap(t, fold: "# A", NSRange(location: 1, length: 1), ""), [])          // merged up
        XCTAssertEqual(remap(t, fold: "# A", NSRange(location: 2, length: 1), ""), [])          // no longer a heading
        XCTAssertEqual(remap(t, fold: "# A", NSRange(location: 2, length: 2), "- "), [])        // became a list item
    }

    func testEditsBelowLeaveTheFoldAlone() {
        let t = "# A\nbody\n# B\nb\n"
        XCTAssertEqual(remap(t, fold: "# A", NSRange(location: 15, length: 0), "more"), ["# A"])
    }

    // MARK: selection

    private let next: (Int) -> Int = { $0 + 1 }

    func testMergeNestedHidden() {
        XCTAssertEqual(FoldSelection.merge([NSRange(location: 10, length: 5), NSRange(location: 3, length: 20), NSRange(location: 30, length: 2)]),
                       [NSRange(location: 3, length: 20), NSRange(location: 30, length: 2)])
    }

    func testContainer() {
        let h = [NSRange(location: 10, length: 10)]
        XCTAssertNil(FoldSelection.container(of: 10, in: h))     // the header end is visible
        XCTAssertEqual(FoldSelection.container(of: 11, in: h), h[0])
        XCTAssertEqual(FoldSelection.container(of: 20, in: h), h[0])   // renders at the header end
        XCTAssertNil(FoldSelection.container(of: 21, in: h))
    }

    func testKeyboardStepsOverFoldsAndClicksStayOnTheHeader() {
        let h = [NSRange(location: 10, length: 10)]
        func caret(_ p: Int) -> NSRange { NSRange(location: p, length: 0) }
        // → from the header end jumps to the next visible line
        XCTAssertEqual(FoldSelection.adjust(caret(11), previous: caret(10), hidden: h, intent: .keyboard, nextLine: next).range, caret(21))
        // ← from the next line lands at the header end
        XCTAssertEqual(FoldSelection.adjust(caret(20), previous: caret(21), hidden: h, intent: .keyboard, nextLine: next).range, caret(10))
        // ↓ onto the header line (layout puts the caret after the hidden run) stays on the header
        XCTAssertEqual(FoldSelection.adjust(caret(20), previous: caret(2), hidden: h, intent: .keyboard, nextLine: next).range, caret(10))
        XCTAssertEqual(FoldSelection.adjust(caret(20), previous: nil, hidden: h, intent: .mouse, nextLine: next).range, caret(10))
        XCTAssertEqual(FoldSelection.adjust(caret(5), previous: nil, hidden: h, intent: .keyboard, nextLine: next).range, caret(5))
        // a fold at EOF has nowhere to step to
        XCTAssertEqual(FoldSelection.adjust(caret(11), previous: caret(10), hidden: h, intent: .keyboard, nextLine: { $0 }).range, caret(10))
    }

    func testRangesGrowToWholeFolds() {
        let h = [NSRange(location: 10, length: 10)]
        let r = FoldSelection.adjust(NSRange(location: 2, length: 12), previous: nil, hidden: h, intent: .keyboard, nextLine: next)
        XCTAssertEqual(r.range, NSRange(location: 2, length: 18))
        let all = FoldSelection.adjust(NSRange(location: 0, length: 40), previous: nil, hidden: h, intent: .programmatic, nextLine: next)
        XCTAssertEqual(all, .init(range: NSRange(location: 0, length: 40), reveal: []))
    }

    func testProgrammaticSelectionsRevealInsteadOfMoving() {
        let h = [NSRange(location: 10, length: 10)]
        let r = FoldSelection.adjust(NSRange(location: 13, length: 3), previous: nil, hidden: h, intent: .programmatic, nextLine: next)
        XCTAssertEqual(r.range, NSRange(location: 13, length: 3))
        XCTAssertEqual(r.reveal, [13, 16])
    }

    // MARK: store

    func testStoreRoundTripsAndFollowsRenames() {
        let d = UserDefaults(suiteName: "onyx.folding.tests.\(UUID().uuidString)")!
        let a = FoldAnchor(signature: "heading:# A", occurrence: 0)
        let s = FoldStore(vault: "/v", defaults: d)
        s.set([a], for: "x.md")
        XCTAssertEqual(FoldStore(vault: "/v", defaults: d).anchors(for: "x.md"), [a])
        XCTAssertTrue(FoldStore(vault: "/other", defaults: d).anchors(for: "x.md").isEmpty)
        s.remapPaths(["x.md": "Folder/y.md"])
        let reloaded = FoldStore(vault: "/v", defaults: d)
        XCTAssertTrue(reloaded.anchors(for: "x.md").isEmpty)
        XCTAssertEqual(reloaded.anchors(for: "Folder/y.md"), [a])
        reloaded.set([], for: "Folder/y.md")
        XCTAssertTrue(FoldStore(vault: "/v", defaults: d).anchors(for: "Folder/y.md").isEmpty)
    }

    func testLargeNoteIsLinearEnough() {
        var s = ""
        for i in 0..<4000 { s += "## Section \(i)\n- item\n  - child \(i)\n\ntext with # not a heading\n\n" }
        let t0 = Date()
        let rs = MarkdownFolds.regions(in: s)
        XCTAssertEqual(rs.count, 8000)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 1.0)
    }
}
