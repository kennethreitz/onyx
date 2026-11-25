import XCTest
@testable import OnyxCore

final class EditCommandsTests: XCTestCase {
    private func r(_ l: Int, _ n: Int = 0) -> NSRange { NSRange(location: l, length: n) }

    func testWrapAndUnwrap() {
        let t = "say hello now"
        let e = EditCommands.toggleWrap(t, r(4, 5), open: "**")
        XCTAssertEqual(e.applied(to: t), "say **hello** now")
        XCTAssertEqual(e.selection, r(6, 5))
        let t2 = e.applied(to: t)
        XCTAssertEqual(EditCommands.toggleWrap(t2, e.selection, open: "**").applied(to: t2), t)          // markers outside
        XCTAssertEqual(EditCommands.toggleWrap(t2, r(4, 9), open: "**").applied(to: t2), t)              // markers inside
        let empty = EditCommands.toggleWrap("ab", r(1), open: "==")
        XCTAssertEqual(empty.applied(to: "ab"), "a====b"); XCTAssertEqual(empty.selection, r(3))
        XCTAssertEqual(EditCommands.toggleWrap("a====b", r(3), open: "==").applied(to: "a====b"), "ab")
        // italic doesn't strip half of a bold pair
        XCTAssertEqual(EditCommands.toggleWrap("**x**", r(2, 1), open: "*").applied(to: "**x**"), "***x***")
        XCTAssertEqual(EditCommands.toggleWrap("hi", r(0, 2), open: "%%").applied(to: "hi"), "%%hi%%")
    }

    func testToggleItalic() {
        let t = "say hello now"
        let e = EditCommands.toggleItalic(t, r(4, 5))
        XCTAssertEqual(e.applied(to: t), "say *hello* now")
        XCTAssertEqual(e.selection, r(5, 5))
        let starred = e.applied(to: t)
        XCTAssertEqual(EditCommands.toggleItalic(starred, e.selection).applied(to: starred), t)   // * outside
        XCTAssertEqual(EditCommands.toggleItalic(starred, r(4, 7)).applied(to: starred), t)       // * inside
        let underscored = "say _hello_ now"
        XCTAssertEqual(EditCommands.toggleItalic(underscored, r(5, 5)).applied(to: underscored), t)
        XCTAssertEqual(EditCommands.toggleItalic(underscored, r(4, 7)).applied(to: underscored), t)
        // no selection: *|* , and a second press removes the empty pair
        let empty = EditCommands.toggleItalic("ab", r(1))
        XCTAssertEqual(empty.applied(to: "ab"), "a**b")
        XCTAssertEqual(empty.selection, r(2))
        XCTAssertEqual(EditCommands.toggleItalic("a**b", r(2)).applied(to: "a**b"), "ab")
        XCTAssertEqual(EditCommands.toggleItalic("a__b", r(2)).applied(to: "a__b"), "ab")
        // * / _ don't strip half of a bold pair
        XCTAssertEqual(EditCommands.toggleItalic("**x**", r(2, 1)).applied(to: "**x**"), "***x***")
        XCTAssertEqual(EditCommands.toggleItalic("__x__", r(2, 1)).applied(to: "__x__"), "__*x*__")
    }

    func testToggleBold() {
        let t = "say hello now"
        let e = EditCommands.toggleBold(t, r(4, 5))
        XCTAssertEqual(e.applied(to: t), "say **hello** now")
        XCTAssertEqual(e.selection, r(6, 5))
        let wrapped = e.applied(to: t)
        XCTAssertEqual(EditCommands.toggleBold(wrapped, e.selection).applied(to: wrapped), t)
        XCTAssertEqual(EditCommands.toggleBold(wrapped, r(4, 9)).applied(to: wrapped), t)
        let underscored = "say __hello__ now"
        XCTAssertEqual(EditCommands.toggleBold(underscored, r(6, 5)).applied(to: underscored), t)
        XCTAssertEqual(EditCommands.toggleBold(underscored, r(4, 9)).applied(to: underscored), t)
        let empty = EditCommands.toggleBold("ab", r(1))
        XCTAssertEqual(empty.applied(to: "ab"), "a****b")
        XCTAssertEqual(empty.selection, r(3))
        XCTAssertEqual(EditCommands.toggleBold("a****b", r(3)).applied(to: "a****b"), "ab")
        XCTAssertEqual(EditCommands.toggleBold("a____b", r(3)).applied(to: "a____b"), "ab")
    }

    func testLinks() {
        XCTAssertEqual(EditCommands.insertWikilink("a b", r(2, 1)).applied(to: "a b"), "a [[b]]")
        let m = EditCommands.insertMarkdownLink("go", r(0, 2))
        XCTAssertEqual(m.applied(to: "go"), "[go]()"); XCTAssertEqual(m.selection, r(5))
    }

    func testListToggles() {
        let t = "one\ntwo\n\nthree"
        let all = r(0, (t as NSString).length)
        let b = EditCommands.toggleLines(t, all, .bullet).applied(to: t)
        XCTAssertEqual(b, "- one\n- two\n\n- three")
        XCTAssertEqual(EditCommands.toggleLines(b, r(0, (b as NSString).length), .bullet).applied(to: b), t)
        XCTAssertEqual(EditCommands.toggleLines(b, r(0, (b as NSString).length), .numbered).applied(to: b), "1. one\n2. two\n\n3. three")
        XCTAssertEqual(EditCommands.toggleLines("  item", r(3), .checklist).applied(to: "  item"), "  - [ ] item")
        XCTAssertEqual(EditCommands.toggleLines("> q", r(2), .quote).applied(to: "> q"), "q")
        XCTAssertEqual(EditCommands.toggleLines("q", r(0), .quote).applied(to: "q"), "> q")
        // the caret stays with its text
        XCTAssertEqual(EditCommands.toggleLines("abc", r(2), .bullet).selection, r(4))
    }

    func testCycleCheckbox() {
        XCTAssertEqual(EditCommands.cycleCheckbox("task", r(0)).applied(to: "task"), "- [ ] task")
        XCTAssertEqual(EditCommands.cycleCheckbox("- task", r(0)).applied(to: "- task"), "- [ ] task")
        XCTAssertEqual(EditCommands.cycleCheckbox("- [ ] task", r(0)).applied(to: "- [ ] task"), "- [x] task")
        XCTAssertEqual(EditCommands.cycleCheckbox("\t- [x] task", r(0)).applied(to: "\t- [x] task"), "\t- [ ] task")
    }

    func testHeadings() {
        XCTAssertEqual(EditCommands.heading("Title", r(0), level: 2).applied(to: "Title"), "## Title")
        XCTAssertEqual(EditCommands.heading("## Title", r(3), level: 2).applied(to: "## Title"), "Title")
        XCTAssertEqual(EditCommands.heading("# Title", r(3), level: 3).applied(to: "# Title"), "### Title")
    }

    func testIndentOutdent() {
        let t = "a\nb"
        let i = EditCommands.indent(t, r(0, 3)).applied(to: t)
        XCTAssertEqual(i, "\ta\n\tb")
        XCTAssertEqual(EditCommands.outdent(i, r(0, 5)).applied(to: i), t)
        XCTAssertEqual(EditCommands.outdent("      x", r(0)).applied(to: "      x"), "  x")
    }

    func testMoveLines() {
        let t = "a\nb\nc"
        let down = EditCommands.moveLines(t, r(0), up: false)!
        XCTAssertEqual(down.applied(to: t), "b\na\nc"); XCTAssertEqual(down.selection, r(2))
        let up = EditCommands.moveLines(t, r(4), up: true)!
        XCTAssertEqual(up.applied(to: t), "a\nc\nb"); XCTAssertEqual(up.selection, r(2))
        XCTAssertNil(EditCommands.moveLines(t, r(0), up: true))
        XCTAssertNil(EditCommands.moveLines(t, r(4), up: false))
        // two selected lines move together; a selection ending at a line start excludes that line
        XCTAssertEqual(EditCommands.moveLines(t, r(0, 4), up: false)!.applied(to: t), "c\na\nb")
        XCTAssertEqual(EditCommands.moveLines(t, r(2, 2), up: true)!.applied(to: t), "b\na\nc")
    }

    func testDuplicateAndDeleteLines() {
        let t = "a\nbb\nc"
        let d = EditCommands.duplicateLines(t, r(3))
        XCTAssertEqual(d.applied(to: t), "a\nbb\nbb\nc"); XCTAssertEqual(d.selection, r(6))
        XCTAssertEqual(EditCommands.deleteLines(t, r(3)).applied(to: t), "a\nc")
        XCTAssertEqual(EditCommands.deleteLines(t, r(6)).applied(to: t), "a\nbb")
        XCTAssertEqual(EditCommands.deleteLines("only", r(1)).applied(to: "only"), "")
    }

    func testBlocks() {
        let c = EditCommands.codeBlock("ab", r(1))
        XCTAssertEqual(c.applied(to: "ab"), "a\n```\n\n```\nb"); XCTAssertEqual(c.selection, r(6))
        XCTAssertEqual(EditCommands.codeBlock("x", r(0, 1)).applied(to: "x"), "```\nx\n```")
        XCTAssertEqual(EditCommands.horizontalRule("", r(0)).applied(to: ""), "---\n")
        XCTAssertEqual(EditCommands.callout("hi\nyo", r(0, 5)).applied(to: "hi\nyo"), "> [!note]\n> hi\n> yo")
        let tb = EditCommands.table("", r(0))
        XCTAssertTrue(tb.applied(to: "").hasPrefix("|  |  |\n| --- | --- |")); XCTAssertEqual(tb.selection, r(2))
    }
}
