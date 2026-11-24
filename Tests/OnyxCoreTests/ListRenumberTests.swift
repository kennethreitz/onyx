import XCTest
@testable import OnyxCore

final class ListRenumberTests: XCTestCase {
    private func r(_ l: Int, _ n: Int = 0) -> NSRange { NSRange(location: l, length: n) }
    private func end(_ s: String) -> NSRange { r((s as NSString).length) }
    private func at(_ prefix: String) -> NSRange { end(prefix) }
    private func utf(_ s: String) -> Int { (s as NSString).length }

    private func enter(_ t: String, _ sel: NSRange) -> TextEdit {
        ListRenumber.applying(ListContinue.newline(t, sel)!, to: t)
    }
    private func indent(_ t: String, _ sel: NSRange) -> TextEdit {
        ListRenumber.applying(EditCommands.indent(t, sel), to: t)
    }
    private func outdent(_ t: String, _ sel: NSRange) -> TextEdit {
        ListRenumber.applying(EditCommands.outdent(t, sel), to: t)
    }
    private func deleteLines(_ t: String, _ sel: NSRange) -> TextEdit {
        ListRenumber.applying(EditCommands.deleteLines(t, sel), to: t)
    }

    // MARK: Return

    func testReturnRenumbersFollowing() {
        let t = "1. a\n2. b\n3. c"
        let e = enter(t, end("1. a"))
        XCTAssertEqual(e.applied(to: t), "1. a\n2. \n3. b\n4. c")
        XCTAssertEqual(e.selection, end("1. a\n2. "))
    }

    func testReturnRespectsStartingNumberAndDelimiter() {
        let t = "5. a\n6. b"
        XCTAssertEqual(enter(t, end("5. a")).applied(to: t), "5. a\n6. \n7. b")
        let p = "5) a\n6) b"
        XCTAssertEqual(enter(p, end("5) a")).applied(to: p), "5) a\n6) \n7) b")
    }

    func testReturnKeepsMixedDelimiters() {
        let t = "1. a\n2) b\n3. c"
        XCTAssertEqual(enter(t, end("1. a")).applied(to: t), "1. a\n2. \n3) b\n4. c")
    }

    func testNestedListsNumberIndependently() {
        let t = "1. a\n\t1. x\n\t2. y\n2. b"
        let e = enter(t, end("1. a\n\t1. x"))
        XCTAssertEqual(e.applied(to: t), "1. a\n\t1. x\n\t2. \n\t3. y\n2. b")
        XCTAssertEqual(e.selection, end("1. a\n\t1. x\n\t2. "))
    }

    func testQuotedList() {
        let t = "> 1. a\n> 2. b\n> 3. c"
        XCTAssertEqual(enter(t, end("> 1. a")).applied(to: t), "> 1. a\n> 2. \n> 3. b\n> 4. c")
    }

    func testBlankLineSeparatesLists() {
        let t = "1. a\n2. b\n\n1. x\n2. y"
        XCTAssertEqual(enter(t, end("1. a")).applied(to: t), "1. a\n2. \n3. b\n\n1. x\n2. y")
    }

    func testEmptyItemEndsWithoutCrossingBlank() {
        let t = "1. a\n2. \n3. c"
        let e = enter(t, end("1. a\n2. "))
        XCTAssertEqual(e.applied(to: t), "1. a\n\n3. c")
        XCTAssertEqual(e.selection, end("1. a\n"))
    }

    func testEmptyNestedOutdentRenumbersParent() {
        let t = "1. a\n\t1. \n2. b"
        let e = enter(t, end("1. a\n\t1. "))
        XCTAssertEqual(e.applied(to: t), "1. a\n2. \n3. b")
        XCTAssertEqual(e.selection, end("1. a\n2. "))
    }

    func testBulletListUnchanged() {
        let t = "- a\n- b\n- c"
        let e = ListRenumber.applying(ListContinue.newline(t, end("- a"))!, to: t)
        XCTAssertEqual(e.applied(to: t), "- a\n- \n- b\n- c")
    }

    // MARK: Indent / outdent

    func testIndentStartsNestedAtOneAndRenumbersLevelLeft() {
        let t = "1. a\n2. b\n3. c"
        let e = indent(t, at("1. a\n2. b"))
        XCTAssertEqual(e.applied(to: t), "1. a\n\t1. b\n2. c")
    }

    func testIndentJoinsExistingNestedList() {
        let t = "1. a\n\t1. x\n2. b\n3. c"
        let e = indent(t, at("1. a\n\t1. x\n2. b"))
        XCTAssertEqual(e.applied(to: t), "1. a\n\t1. x\n\t2. b\n2. c")
    }

    func testIndentFirstItemRenumbersSiblingsLeftBehind() {
        let t = "1. a\n2. b\n3. c"
        let e = indent(t, at("1. a"))
        XCTAssertEqual(e.applied(to: t), "\t1. a\n1. b\n2. c")
    }

    func testOutdentJoinsParentAndRenumbersBothLevels() {
        let t = "1. a\n\t1. b\n\t2. c\n2. d"
        let e = outdent(t, at("1. a\n\t1. b\n\t2. c"))
        XCTAssertEqual(e.applied(to: t), "1. a\n\t1. b\n2. c\n3. d")
    }

    // MARK: Delete

    func testDeleteLineRenumbersRemainder() {
        let t = "1. a\n2. b\n3. c"
        let e = deleteLines(t, at("1. a\n2. b"))
        XCTAssertEqual(e.applied(to: t), "1. a\n2. c")
    }

    func testDeleteFirstItemKeepsOriginalStart() {
        let t = "1. a\n2. b\n3. c"
        XCTAssertEqual(deleteLines(t, at("1. a")).applied(to: t), "1. b\n2. c")
        let t2 = "5. a\n6. b\n7. c"
        XCTAssertEqual(deleteLines(t2, at("5. a")).applied(to: t2), "5. b\n6. c")
    }

    func testAfterChangeWithBeforeKeepsOriginalStart() {
        let before = "1. a\n2. b\n3. c"
        let after = "2. b\n3. c"
        let e = ListRenumber.afterChange(after, selection: r(0), from: before)!
        XCTAssertEqual(e.applied(to: after), "1. b\n2. c")
    }

    func testAfterChangeRenumbersAtCaret() {
        let t = "1. a\n3. c"
        let e = ListRenumber.afterChange(t, selection: end("1. a\n"))!
        XCTAssertEqual(e.applied(to: t), "1. a\n2. c")
    }

    func testAfterChangeNilWhenAlreadyInOrder() {
        XCTAssertNil(ListRenumber.afterChange("1. a\n2. b", selection: end("1. a\n2. b")))
        XCTAssertNil(ListRenumber.afterChange("5. a\n6. b", selection: end("5. a")))
    }

    // MARK: Caret / width

    func testDigitsWidenAdjustsCaret() {
        let t = "9. a\n9. b"
        let e = ListRenumber.afterChange(t, selection: end(t))!
        XCTAssertEqual(e.applied(to: t), "9. a\n10. b")
        XCTAssertEqual(e.selection, end("9. a\n10. b"))
        // caret in the item text of the second line moves with the extra digit
        let inText = utf("9. a\n9. ")
        let e2 = ListRenumber.afterChange(t, selection: r(inText))!
        XCTAssertEqual(e2.selection, end("9. a\n10. "))
        // caret on the first line is unchanged
        let e3 = ListRenumber.afterChange(t, selection: end("9. a"))!
        XCTAssertEqual(e3.selection, end("9. a"))
    }

    func testReturnWideningIsOneEdit() {
        let t = "8. a\n9. b"
        let e = enter(t, end("8. a"))
        XCTAssertEqual(e.applied(to: t), "8. a\n9. \n10. b")
        XCTAssertEqual(e.selection, end("8. a\n9. "))
        // the combined edit covers both the new item and the later 9 → 10
        XCTAssertGreaterThan(e.range.length + utf(e.replacement), utf("\n9. "))
    }

    // MARK: Opaque regions

    func testSkipsFences() {
        let t = "```\n1. a\n3. b\n```"
        XCTAssertNil(ListRenumber.afterChange(t, selection: at("```\n1. a")))
        let t2 = "1. a\n3. b\n\n```\n1. x\n3. y\n```"
        let e = ListRenumber.afterChange(t2, selection: at("1. a\n"))!
        XCTAssertEqual(e.applied(to: t2), "1. a\n2. b\n\n```\n1. x\n3. y\n```")
    }

    func testSkipsFrontmatter() {
        let t = "---\n1. a\n3. b\n---\n1. a\n3. c"
        let e = ListRenumber.afterChange(t, selection: end(t))!
        XCTAssertEqual(e.applied(to: t), "---\n1. a\n3. b\n---\n1. a\n2. c")
    }

    func testNonListAndDifferentIndentStopTheList() {
        let t = "1. a\n2. b\nplain\n3. c"
        XCTAssertEqual(enter(t, end("1. a")).applied(to: t), "1. a\n2. \n3. b\nplain\n3. c")
        let t2 = "1. a\n2. b\n- bullet\n3. c"
        XCTAssertEqual(enter(t2, end("1. a")).applied(to: t2), "1. a\n2. \n3. b\n- bullet\n3. c")
    }

    func testIndentedContinuationDoesNotBreakParent() {
        let t = "1. a\n   still\n2. b"
        XCTAssertEqual(enter(t, end("1. a")).applied(to: t), "1. a\n2. \n   still\n3. b")
    }
}
