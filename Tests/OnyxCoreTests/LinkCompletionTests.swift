import XCTest
@testable import OnyxCore

final class LinkCompletionTests: XCTestCase {
    typealias LC = LinkCompletion
    func ctx(_ s: String) -> LC.Context? {
        // "¦" marks the caret
        let r = s.range(of: "¦")!
        let caret = s.utf16.distance(from: s.utf16.startIndex, to: r.lowerBound.samePosition(in: s.utf16)!)
        let line = s.replacingCharacters(in: r, with: "")
        return LC.context(line: line, caret: caret)
    }

    func testNoteQuery() {
        let c = ctx("see [[Merc¦]]")!
        XCTAssertEqual(c.query, "Merc"); XCTAssertEqual(c.part, .note); XCTAssertEqual(c.queryStart, 6); XCTAssertEqual(c.open, 4)
        XCTAssertEqual(ctx("[[¦]]")?.query, "")
        XCTAssertEqual(ctx("[[two words¦]]")?.query, "two words")
        XCTAssertTrue(ctx("![[Pic¦]]")!.embed)
    }
    func testOutsideLinks() {
        XCTAssertNil(ctx("plain text¦"))
        XCTAssertNil(ctx("[[Done]] after¦"))              // moved out past ]]
        XCTAssertNil(ctx("[[Done]¦"))                     // typed the first ]
        XCTAssertNil(ctx("[single¦"))
        XCTAssertNil(ctx("¦[[Later]]"))
    }
    func testHeadingBlockAlias() {
        XCTAssertEqual(ctx("[[Mercury#Sym¦]]")?.part, .heading(note: "Mercury"))
        XCTAssertEqual(ctx("[[Mercury#Sym¦]]")?.query, "Sym")
        XCTAssertEqual(ctx("[[#Local¦]]")?.part, .heading(note: ""))
        XCTAssertEqual(ctx("[[Mercury#^abc¦]]")?.part, .block)
        let a = ctx("[[Mercury|Merc¦]]")!
        XCTAssertEqual(a.part, .alias); XCTAssertEqual(a.query, "Merc")
        XCTAssertEqual(ctx("[[Mercury#Sym|Alias¦]]")?.part, .alias)
    }
    func testUnicodeOffsets() {
        let c = ctx("☿ [[Café¦]]")!
        XCTAssertEqual(c.query, "Café"); XCTAssertEqual(c.queryStart, 4)
    }
    func testHighlightAndKeys() {
        XCTAssertNil(LC.defaultHighlight(topIsExact: false))
        XCTAssertEqual(LC.defaultHighlight(topIsExact: true), 0)
        XCTAssertEqual(LC.move(nil, by: 1, count: 5), 0)
        XCTAssertEqual(LC.move(nil, by: -1, count: 5), 4)
        XCTAssertEqual(LC.move(4, by: 1, count: 5), 4)
        XCTAssertNil(LC.move(nil, by: 1, count: 0))
        XCTAssertEqual(LC.action(for: .returnKey, highlighted: nil), .leave)
        XCTAssertEqual(LC.action(for: .tab, highlighted: nil), .leave)
        XCTAssertEqual(LC.action(for: .returnKey, highlighted: 2), .accept(2))
        XCTAssertEqual(LC.action(for: .escape, highlighted: 1), .dismiss)
        XCTAssertEqual(LC.action(for: .other, highlighted: 1), .pass)
    }
    func testLinkText() {
        XCTAssertEqual(LC.linkText(path: "Knowledge/Mercury.md", name: "Mercury", nameIsUnique: true), "Mercury")
        XCTAssertEqual(LC.linkText(path: "Knowledge/Mercury.md", name: "Mercury", nameIsUnique: false), "Knowledge/Mercury")
    }
}
