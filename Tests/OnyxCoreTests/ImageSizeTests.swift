import XCTest
@testable import OnyxCore

final class ImageSizeTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(ImageSize.parse("300"), EmbedSize(width: 300))
        XCTAssertEqual(ImageSize.parse("300x200"), EmbedSize(width: 300, height: 200))
        XCTAssertEqual(ImageSize.parse(" 120 "), EmbedSize(width: 120))
        for bad in ["", "x", "300x", "x200", "0", "3.5", "abc", "300X200", "１２", "300x200x1", "-5"] { XCTAssertNil(ImageSize.parse(bad), bad) }
    }

    func testSplit() {
        XCTAssertEqual(ImageSize.split("300").size, EmbedSize(width: 300))
        XCTAssertNil(ImageSize.split("300").alt)
        let a = ImageSize.split("A caption|300x200")
        XCTAssertEqual(a.alt, "A caption"); XCTAssertEqual(a.size, EmbedSize(width: 300, height: 200))
        let b = ImageSize.split("Doug Engelbart")
        XCTAssertEqual(b.alt, "Doug Engelbart"); XCTAssertNil(b.size)
        let c = ImageSize.split("one|two")
        XCTAssertEqual(c.alt, "one|two"); XCTAssertNil(c.size)
        XCTAssertEqual(ImageSize.split("cap\\|300").alt, "cap")
    }

    func testWikiAddReplaceRemove() {
        let t = "# Note\n\n![[photo.png]]\n"
        XCTAssertEqual(ImageSize.resize(t, line: 2, lines: 1, kind: "wiki", target: "photo.png", occurrence: 0, width: 300), "# Note\n\n![[photo.png|300]]\n")
        XCTAssertEqual(ImageSize.resize("![[photo.png|120x80]]", line: 0, lines: 1, kind: "wiki", target: "photo.png", occurrence: 0, width: 300), "![[photo.png|300]]")
        XCTAssertEqual(ImageSize.resize("![[photo.png|Cap|120]]", line: 0, lines: 1, kind: "wiki", target: "photo.png", occurrence: 0, width: 64), "![[photo.png|Cap|64]]")
        XCTAssertEqual(ImageSize.resize("![[photo.png|Cap]]", line: 0, lines: 1, kind: "wiki", target: "photo.png", occurrence: 0, width: 64), "![[photo.png|Cap|64]]")
        XCTAssertEqual(ImageSize.resize("![[photo.png|Cap|120]]", line: 0, lines: 1, kind: "wiki", target: "photo.png", occurrence: 0, width: nil), "![[photo.png|Cap]]")
        XCTAssertEqual(ImageSize.resize("![[photo.png|120]]", line: 0, lines: 1, kind: "wiki", target: "PHOTO.png", occurrence: 0, width: nil), "![[photo.png]]")
        XCTAssertEqual(ImageSize.resize("![[Diagram.png#outline|50]]", line: 0, lines: 1, kind: "wiki", target: "diagram.png", occurrence: 0, width: 90), "![[Diagram.png#outline|90]]")
        XCTAssertNil(ImageSize.resize("![[other.png]]", line: 0, lines: 1, kind: "wiki", target: "photo.png", occurrence: 0, width: 90))
    }

    func testDuplicatesUseTheOccurrenceAndTheBlock() {
        let t = "![[a.png]] and ![[a.png|10]]\n\n![[a.png]]\n"
        XCTAssertEqual(ImageSize.resize(t, line: 0, lines: 1, kind: "wiki", target: "a.png", occurrence: 1, width: 200), "![[a.png]] and ![[a.png|200]]\n\n![[a.png]]\n")
        XCTAssertEqual(ImageSize.resize(t, line: 0, lines: 1, kind: "wiki", target: "a.png", occurrence: 0, width: 200), "![[a.png|200]] and ![[a.png|10]]\n\n![[a.png]]\n")
        XCTAssertEqual(ImageSize.resize(t, line: 2, lines: 1, kind: "wiki", target: "a.png", occurrence: 0, width: 200), "![[a.png]] and ![[a.png|10]]\n\n![[a.png|200]]\n")
        XCTAssertNil(ImageSize.resize(t, line: 2, lines: 1, kind: "wiki", target: "a.png", occurrence: 1, width: 200))
        // A code span or %%comment%% in the block isn't rendered, so it doesn't count.
        let c = "`![[a.png]]` %%![[a.png]]%% ![[a.png]]"
        XCTAssertEqual(ImageSize.resize(c, line: 0, lines: 1, kind: "wiki", target: "a.png", occurrence: 0, width: 5), "`![[a.png]]` %%![[a.png]]%% ![[a.png|5]]")
        // Multi-line blocks (a list) search every line of the block.
        let l = "- one\n- ![[a.png]]\n- ![[a.png]]\n"
        XCTAssertEqual(ImageSize.resize(l, line: 0, lines: 3, kind: "wiki", target: "a.png", occurrence: 1, width: 7), "- one\n- ![[a.png]]\n- ![[a.png|7]]\n")
    }

    func testMarkdown() {
        XCTAssertEqual(ImageSize.resize("![](img.png)", line: 0, lines: 1, kind: "md", target: "img.png", occurrence: 0, width: 250), "![250](img.png)")
        XCTAssertEqual(ImageSize.resize("![Doug](img.png)", line: 0, lines: 1, kind: "md", target: "img.png", occurrence: 0, width: 250), "![Doug|250](img.png)")
        XCTAssertEqual(ImageSize.resize("![Doug|100x145](img.png \"t\")", line: 0, lines: 1, kind: "md", target: "img.png", occurrence: 0, width: 250), "![Doug|250](img.png \"t\")")
        XCTAssertEqual(ImageSize.resize("![100](img.png)", line: 0, lines: 1, kind: "md", target: "img.png", occurrence: 0, width: nil), "![](img.png)")
        XCTAssertEqual(ImageSize.resize("![Doug|100](img.png)", line: 0, lines: 1, kind: "md", target: "img.png", occurrence: 0, width: nil), "![Doug](img.png)")
        XCTAssertEqual(ImageSize.resize("![](My%20Pic.png) ![](<My Pic.png>)", line: 0, lines: 1, kind: "md", target: "My Pic.png", occurrence: 1, width: 9), "![](My%20Pic.png) ![9](<My Pic.png>)")
        XCTAssertEqual(ImageSize.resize("![](My%20Pic.png)", line: 0, lines: 1, kind: "md", target: "My%20Pic.png", occurrence: 0, width: 9), "![9](My%20Pic.png)")
    }

    func testTablesEscapeThePipe() {
        let t = "| a | b |\n| - | - |\n| ![[p.png]] | x |\n"
        XCTAssertEqual(ImageSize.resize(t, line: 0, lines: 3, kind: "wiki", target: "p.png", occurrence: 0, width: 40), "| a | b |\n| - | - |\n| ![[p.png\\|40]] | x |\n")
        XCTAssertEqual(ImageSize.resize("| ![[p.png\\|40]] |", line: 0, lines: 1, kind: "wiki", target: "p.png", occurrence: 0, width: 80), "| ![[p.png\\|80]] |")
        XCTAssertEqual(ImageSize.resize("| ![[p.png\\|40]] |", line: 0, lines: 1, kind: "wiki", target: "p.png", occurrence: 0, width: nil), "| ![[p.png]] |")
        XCTAssertEqual(ImageSize.resize("| ![cap](p.png) |", line: 0, lines: 1, kind: "md", target: "p.png", occurrence: 0, width: 8), "| ![cap\\|8](p.png) |")
    }

    func testUnicodeOffsets() {
        let t = "Café 🌶️ ![[ü.png]]\n"
        XCTAssertEqual(ImageSize.resize(t, line: 0, lines: 1, kind: "wiki", target: "ü.png", occurrence: 0, width: 3), "Café 🌶️ ![[ü.png|3]]\n")
    }
}
