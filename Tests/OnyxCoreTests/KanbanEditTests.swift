import XCTest
@testable import OnyxCore

final class KanbanEditTests: XCTestCase {
    // The plugin's own layout (frontmatter with blank lines, lanes, trailing blanks, settings).
    let board = "---\n\nkanban-plugin: board\n\n---\n\n## ToDo\n\n- [ ] [[alpha]] — one\n- [ ] beta / two\n\n\n## Doing\n\n- [ ] gamma\n    second line\n\n\n## Empty\n\n\n\n## Done\n\n- [x] delta\n- [ ] eps\n\n\n\n\n%% kanban:settings\n```\n{\"kanban-plugin\":\"board\",\"list-collapse\":[false,false,false,false]}\n```\n%%"

    func testRoundTripIsByteIdentical() {
        let d = KanbanDoc(board)
        XCTAssertEqual(d.text, board)
        XCTAssertEqual(d.lanes.map(\.title), ["ToDo", "Doing", "Empty", "Done"])
        XCTAssertEqual(d.lanes.map { $0.cards.count }, [2, 1, 0, 2])
        XCTAssertEqual(d.cardText(d.lanes[1].cards[0]), "gamma\nsecond line")
        XCTAssertEqual(d.lanes[3].cards.map(\.done), [true, false])
        // agrees with the reader's parser
        XCTAssertEqual(KanbanBoard.parse(board).lanes.map { $0.cards.count }, [2, 1, 0, 2])
    }

    func testToggleTwiceRestores() {
        var d = KanbanDoc(board)
        d.toggle(lane: 0, card: 1)
        XCTAssertTrue(d.text.contains("- [x] beta / two"))
        d.toggle(lane: 0, card: 1)
        XCTAssertEqual(d.text, board)
    }

    func testMoveAndBack() {
        var d = KanbanDoc(board)
        d.move(lane: 1, card: 0, toLane: 2, index: 0)          // multi-line card into an empty lane
        XCTAssertTrue(d.text.contains("## Doing\n\n\n\n## Empty\n\n- [ ] gamma\n    second line\n\n\n## Done"))
        d.move(lane: 2, card: 0, toLane: 1, index: 0)
        XCTAssertEqual(d.text, board)
        d.move(lane: 0, card: 0, toLane: 0, index: 1)          // reorder within a lane
        XCTAssertTrue(d.text.contains("- [ ] beta / two\n- [ ] [[alpha]] — one\n\n\n## Doing"))
        d.move(lane: 0, card: 1, toLane: 0, index: 0)
        XCTAssertEqual(d.text, board)
        d.move(lane: 3, card: 1, toLane: 0, index: 2)          // to the end of another lane
        XCTAssertTrue(d.text.contains("- [ ] beta / two\n- [ ] eps\n\n\n## Doing"))
        XCTAssertTrue(d.text.contains("- [x] delta\n\n\n\n\n%% kanban:settings"))
    }

    func testAddEditDelete() {
        var d = KanbanDoc(board)
        d.add(lane: 2, text: "new idea")
        XCTAssertTrue(d.text.contains("## Empty\n\n- [ ] new idea\n\n\n## Done"))
        d.edit(lane: 2, card: 0, text: "renamed\nwith detail")
        XCTAssertTrue(d.text.contains("## Empty\n\n- [ ] renamed\n    with detail\n\n\n## Done"))
        d.delete(lane: 2, card: 0)
        XCTAssertEqual(d.text, board)
        XCTAssertFalse(d.edit(lane: 3, card: 0, text: "delta"))   // unchanged text: no edit
        d.edit(lane: 3, card: 0, text: "delta 2")
        XCTAssertTrue(d.text.contains("- [x] delta 2\n"))          // keeps the check
    }

    func testArchive() {
        var d = KanbanDoc(board)
        d.archive(lane: 3, card: 0)
        XCTAssertTrue(d.text.hasSuffix("- [ ] eps\n\n\n***\n\n## Archive\n\n- [x] delta\n\n\n\n\n%% kanban:settings\n```\n{\"kanban-plugin\":\"board\",\"list-collapse\":[false,false,false,false]}\n```\n%%"), d.text)
        XCTAssertEqual(d.lanes.count, 4)
        XCTAssertEqual(d.archive.count, 1)
        XCTAssertEqual(KanbanBoard.parse(d.text).lanes.count, 4)   // "## Archive" is not a lane
        d.archive(lane: 0, card: 0)
        XCTAssertTrue(d.text.contains("## Archive\n\n- [x] delta\n- [ ] [[alpha]] — one\n"))
        XCTAssertEqual(d.archive.count, 2)
        XCTAssertEqual(KanbanDoc(d.text).text, d.text)
    }

    func testCollapseRoundTripsThroughSettings() {
        var d = KanbanDoc(board)
        XCTAssertEqual(d.collapsed, [false, false, false, false])
        d.setCollapsed(lane: 1, true)
        XCTAssertTrue(d.text.contains("{\"kanban-plugin\":\"board\",\"list-collapse\":[false,true,false,false]}"))
        XCTAssertEqual(KanbanDoc(d.text).collapsed, [false, true, false, false])
        XCTAssertFalse(d.setCollapsed(lane: 1, true))            // already: no write
        d.setCollapsed([true, true, false, true])                // "collapse all except this"
        d.setCollapsed(lane: 0, false); d.setCollapsed(lane: 1, false); d.setCollapsed(lane: 3, false)
        XCTAssertEqual(d.text, board)                            // back to the exact bytes
        // a settings block without the key gains it; a board without settings gains one
        var e = KanbanDoc("---\nkanban-plugin: board\n---\n\n## A\n\n- [ ] x\n\n\n%% kanban:settings\n```\n{\"kanban-plugin\":\"board\"}\n```\n%%")
        e.setCollapsed(lane: 0, true)
        XCTAssertTrue(e.text.contains("{\"kanban-plugin\":\"board\",\"list-collapse\":[true]}"))
        var f = KanbanDoc("---\nkanban-plugin: board\n---\n\n## A\n\n- [ ] x\n\n\n")
        f.setCollapsed(lane: 0, true)
        XCTAssertEqual(KanbanDoc(f.text).collapsed, [true])
        XCTAssertEqual(KanbanDoc(f.text).lanes.map { $0.cards.count }, [1])
    }

    /// ONYX_KANBAN_FILE=/tmp/…/Ideas.md: a real board (a copy) must round-trip byte for byte,
    /// and every toggle/move undone must restore it exactly.
    func testRealBoardCopy() throws {
        guard let p = ProcessInfo.processInfo.environment["ONYX_KANBAN_FILE"] else { throw XCTSkip("set ONYX_KANBAN_FILE") }
        XCTAssertTrue(p.hasPrefix("/tmp/") || p.hasPrefix("/private/tmp/"), "only test copies")
        let data = try Data(contentsOf: URL(fileURLWithPath: p))
        let text = String(decoding: data, as: UTF8.self)
        let d = KanbanDoc(text)
        XCTAssertEqual(Data(d.text.utf8), data)
        XCTAssertFalse(d.lanes.isEmpty)
        for (li, l) in d.lanes.enumerated() {
            for ci in l.cards.indices {
                var t = d; t.toggle(lane: li, card: ci); t.toggle(lane: li, card: ci)
                XCTAssertEqual(t.text, text)
                for to in d.lanes.indices where to != li {
                    var m = d; m.move(lane: li, card: ci, toLane: to, index: 0); m.move(lane: to, card: 0, toLane: li, index: ci)
                    XCTAssertEqual(m.text, text, "move \(li):\(ci) → \(to) and back")
                }
            }
        }
        var c = d; c.setCollapsed(lane: 0, !d.collapsed[0]); c.setCollapsed(lane: 0, d.collapsed[0])
        XCTAssertEqual(c.text, text, "collapse and expand restores the bytes")
        print("[kanban] \(d.lanes.count) lanes, \(d.lanes.map { $0.cards.count }.reduce(0, +)) cards, round-trip identical")
    }
}
