import XCTest
@testable import OnyxCore

final class ListContinueTests: XCTestCase {
    private func r(_ l: Int, _ n: Int = 0) -> NSRange { NSRange(location: l, length: n) }
    private func end(_ s: String) -> NSRange { r((s as NSString).length) }
    private func apply(_ t: String, _ sel: NSRange) -> String? {
        ListContinue.newline(t, sel)?.applied(to: t)
    }
    private func caret(_ t: String, _ sel: NSRange) -> Int? {
        ListContinue.newline(t, sel)?.selection.location
    }

    func testBulletsContinue() {
        for m in ["- ", "* ", "+ "] {
            let t = "\(m)item"
            let e = ListContinue.newline(t, end(t))!
            XCTAssertEqual(e.applied(to: t), "\(m)item\n\(m)")
            XCTAssertEqual(e.selection, end("\(m)item\n\(m)"))
        }
    }

    func testNumberedIncrements() {
        XCTAssertEqual(apply("1. item", end("1. item")), "1. item\n2. ")
        XCTAssertEqual(apply("2. item", end("2. item")), "2. item\n3. ")
        XCTAssertEqual(apply("9. item", end("9. item")), "9. item\n10. ")
        XCTAssertEqual(apply("1) item", end("1) item")), "1) item\n2) ")
        XCTAssertEqual(apply("10) tenth", end("10) tenth")), "10) tenth\n11) ")
    }

    func testTasksContinueUnchecked() {
        XCTAssertEqual(apply("- [ ] task", end("- [ ] task")), "- [ ] task\n- [ ] ")
        XCTAssertEqual(apply("- [x] done", end("- [x] done")), "- [x] done\n- [ ] ")
        XCTAssertEqual(apply("* [X] done", end("* [X] done")), "* [X] done\n* [ ] ")
        XCTAssertEqual(apply("+ [?] odd", end("+ [?] odd")), "+ [?] odd\n+ [ ] ")
    }

    func testIndentPreserved() {
        XCTAssertEqual(apply("  - item", end("  - item")), "  - item\n  - ")
        XCTAssertEqual(apply("\t- item", end("\t- item")), "\t- item\n\t- ")
        XCTAssertEqual(apply("    1. item", end("    1. item")), "    1. item\n    2. ")
    }

    func testBlockquotedList() {
        XCTAssertEqual(apply("> - item", end("> - item")), "> - item\n> - ")
        XCTAssertEqual(apply("> 1. item", end("> 1. item")), "> 1. item\n> 2. ")
        XCTAssertEqual(apply("> - [x] task", end("> - [x] task")), "> - [x] task\n> - [ ] ")
        XCTAssertEqual(apply(">> - item", end(">> - item")), ">> - item\n>> - ")
        XCTAssertEqual(apply(">- item", end(">- item")), ">- item\n>- ")
    }

    func testSplitMiddle() {
        let t = "- hello world"
        // caret between "hello " and "world"
        let at = ("- hello " as NSString).length
        let e = ListContinue.newline(t, r(at))!
        XCTAssertEqual(e.applied(to: t), "- hello \n- world")
        XCTAssertEqual(e.selection, end("- hello \n- "))
        // a selection in the middle is deleted
        let t2 = "- abcdef"
        let e2 = ListContinue.newline(t2, r(4, 2))!   // "cd"
        XCTAssertEqual(e2.applied(to: t2), "- ab\n- ef")
    }

    func testSplitKeepsEmojiOffsets() {
        let t = "- 🎉 ab"
        // "🎉" is two UTF-16 units; caret after the emoji (and the space)
        let at = ("- 🎉 " as NSString).length
        let e = ListContinue.newline(t, r(at))!
        XCTAssertEqual(e.applied(to: t), "- 🎉 \n- ab")
        XCTAssertEqual(e.selection, end("- 🎉 \n- "))
    }

    func testEmptyItemEndsList() {
        XCTAssertEqual(apply("- ", end("- ")), "")
        XCTAssertEqual(apply("- item\n- ", end("- item\n- ")), "- item\n")
        XCTAssertEqual(apply("- [ ] ", end("- [ ] ")), "")
        XCTAssertEqual(apply("1. ", end("1. ")), "")
        // trailing spaces on an empty item still end the list
        XCTAssertEqual(apply("-   ", end("-   ")), "")
    }

    func testEmptyNestedOutdents() {
        XCTAssertEqual(apply("  - ", end("  - ")), "- ")
        XCTAssertEqual(apply("    - ", end("    - ")), "- ")
        XCTAssertEqual(apply("      - ", end("      - ")), "  - ")
        XCTAssertEqual(apply("\t- ", end("\t- ")), "- ")
        XCTAssertEqual(apply("\t\t- ", end("\t\t- ")), "\t- ")
        // two Returns: nested empty, then top-level empty
        let once = apply("  - ", end("  - "))!
        XCTAssertEqual(once, "- ")
        XCTAssertEqual(apply(once, end(once)), "")
    }

    func testEmptyQuoted() {
        XCTAssertEqual(apply("> - ", end("> - ")), "> ")
        XCTAssertEqual(apply(">   - ", end(">   - ")), "> - ")
        XCTAssertEqual(apply(">\t- ", end(">\t- ")), ">- ")   // keeps the original `>` prefix (no space before the tab)
    }

    func testCaretInPrefixMovesContentDown() {
        let t = "- item"
        let e = ListContinue.newline(t, r(0))!
        XCTAssertEqual(e.applied(to: t), "- \n- item")
        XCTAssertEqual(e.selection, end("- \n- "))
    }

    func testNotAList() {
        XCTAssertNil(ListContinue.newline("hello", end("hello")))
        XCTAssertNil(ListContinue.newline("-item", end("-item")))
        XCTAssertNil(ListContinue.newline("1.item", end("1.item")))
        XCTAssertNil(ListContinue.newline("> just a quote", end("> just a quote")))
        XCTAssertNil(ListContinue.newline("", r(0)))
    }

    func testMultilineSelectionFallsThrough() {
        let t = "- a\n- b"
        XCTAssertNil(ListContinue.newline(t, r(0, (t as NSString).length)))
        XCTAssertNil(ListContinue.newline(t, r(2, 3)))   // crosses the newline
    }

    func testSkipsFences() {
        let t = "```\n- item\n```"
        let inside = ("```\n- item" as NSString).length
        XCTAssertNil(ListContinue.newline(t, r(inside)))
        let t2 = "```\n- item\n```\n- real"
        XCTAssertEqual(apply(t2, end(t2)), "```\n- item\n```\n- real\n- ")
        // unclosed fence through EOF
        XCTAssertNil(ListContinue.newline("```\n- item", end("```\n- item")))
        // tilde fences too
        XCTAssertNil(ListContinue.newline("~~~\n- item\n~~~", end("~~~\n- item")))
    }

    func testSkipsFrontmatter() {
        let t = "---\ntags:\n  - a\n---\n- real"
        XCTAssertNil(ListContinue.newline(t, r(("---\ntags:\n  - a" as NSString).length)))
        XCTAssertEqual(apply(t, end(t)), "---\ntags:\n  - a\n---\n- real\n- ")
        // unclosed frontmatter is not detected, so a list-looking line still continues
        XCTAssertEqual(apply("---\n- item", end("---\n- item")), "---\n- item\n- ")
    }

    func testIsListSelection() {
        XCTAssertTrue(ListContinue.isListSelection("- a", r(0)))
        XCTAssertTrue(ListContinue.isListSelection("  * a", end("  * a")))
        XCTAssertTrue(ListContinue.isListSelection("1. a\n2. b", r(0, 9)))
        XCTAssertTrue(ListContinue.isListSelection("- a\n\n- b", r(0, 8)))
        XCTAssertFalse(ListContinue.isListSelection("hello", r(0)))
        XCTAssertFalse(ListContinue.isListSelection("- a\nplain", r(0, 10)))
        XCTAssertFalse(ListContinue.isListSelection("", r(0)))
        XCTAssertFalse(ListContinue.isListSelection("```\n- a\n```", r(4)))
        XCTAssertFalse(ListContinue.isListSelection("---\n- a\n---\n", r(4)))
    }

    func testCaretAtEndOfLineBeforeLaterText() {
        let t = "- item\n\npara"
        let at = ("- item" as NSString).length
        XCTAssertEqual(apply(t, r(at)), "- item\n- \n\npara")
    }
}
