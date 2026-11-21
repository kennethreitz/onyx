
import XCTest
@testable import OnyxCore

final class DataviewJSTests: XCTestCase {
    let now: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 21; c.hour = 15; c.minute = 30
        return Calendar.current.date(from: c)!
    }()

    func snap() -> VaultSnapshot {
        var s = VaultSnapshot(root: URL(fileURLWithPath: "/tmp/none"))
        let files = [
            "Knowledge/Astrology/Planets/Sun.md": "---\ntype: planet\norder: 1\nmetal: Gold\n---\n# Sun\n[[Moon]]\n- [ ] Watch sunrise\n",
            "Knowledge/Astrology/Planets/Moon.md": "---\ntype: planet\norder: 2\nmetal: Silver\n---\n# Moon\n[[Sun]]\n",
            "Projects/Launch.md": "---\ntype: project\n---\n# Launch\n",
        ]
        for (p, c) in files { s.notes[p] = VaultSnapshot.makeRecord(rel: p, content: c, mtime: now, ctime: now, size: c.utf8.count) }
        s.rebuildDerived()
        return s
    }

    func html(_ src: String, from path: String = "Knowledge/Astrology/Planets/Sun.md") -> String {
        switch DataviewJS.run(src, in: snap(), from: path, now: now) {
        case .html(let h): return h
        case .error(let e): return "ERROR:" + e
        }
    }

    func testPagesCurrentAndPage() {
        let h = html("""
        dv.list(dv.pages('"Knowledge/Astrology/Planets"').where(p => p.type == "planet").sortBy(p => p.order).map(p => p.file.name))
        """)
        XCTAssertTrue(h.contains("Sun"))
        XCTAssertTrue(h.contains("Moon"))
        XCTAssertFalse(h.contains("Launch"))
        let cur = html("dv.paragraph(dv.current().file.name)")
        XCTAssertTrue(cur.contains("Sun"))
        let page = html("dv.paragraph(dv.page('Moon').metal)")
        XCTAssertTrue(page.contains("Silver"))
    }

    func testTableListHeaderAndDate() {
        let h = html("""
        dv.header("Planets", 3)
        dv.table(["Name", "Metal"], dv.pages('#none or "Knowledge"').where(p => p.metal).sortBy(p => p.file.name).map(p => [p.file.link, p.metal]))
        const d = dv.date("today"); dv.paragraph("today is " + d.getFullYear() + "-" + String(d.getMonth()+1).padStart(2,"0") + "-" + String(d.getDate()).padStart(2,"0"))
        """)
        XCTAssertTrue(h.contains("<h3>Planets</h3>"))
        XCTAssertTrue(h.contains("<table"))
        XCTAssertTrue(h.contains("Gold"))
        XCTAssertTrue(h.contains("Silver"))
        XCTAssertTrue(h.contains("internal-link"))
        XCTAssertTrue(h.contains("today is 2026-11-21"))
    }

    func testGroupByLimitAndTaskList() {
        let h = html("""
        const groups = dv.pages().groupBy(p => p.type).limit(10)
        dv.list(groups.map(g => g.key + ": " + g.rows.length))
        dv.taskList(dv.current().file.tasks)
        """)
        XCTAssertTrue(h.contains("planet:"))
        XCTAssertTrue(h.contains("data-dv-task"))
        XCTAssertTrue(h.contains("Watch sunrise"))
    }

    func testErrorsUseMessage() {
        switch DataviewJS.run("dv.nope()", in: snap(), from: "Knowledge/Astrology/Planets/Sun.md", now: now) {
        case .html: XCTFail("should be an error")
        case .error(let e): XCTAssertFalse(e.isEmpty)
        }
        switch DataviewJS.run("throw new Error('boom')", in: snap(), from: "Knowledge/Astrology/Planets/Sun.md", now: now) {
        case .html: XCTFail("should be an error")
        case .error(let e): XCTAssertTrue(e.contains("boom"))
        }
    }

    func testNoWriteAPI() {
        let h = html("dv.paragraph(typeof dv.io + ' ' + typeof dv.fileWrite)")
        XCTAssertTrue(h.contains("undefined undefined"))
    }

    func testInlineExpr() {
        let s = snap()
        let path = "Knowledge/Astrology/Planets/Sun.md"
        XCTAssertEqual(DataviewJS.evalInline("dv.current().file.name", in: s, from: path, now: now), "Sun")
        XCTAssertEqual(DataviewJS.evalInline("1 + 2", in: s, from: path, now: now), "3")
        XCTAssertTrue(DataviewJS.evalInline("@@@", in: s, from: path, now: now).contains("dataview-inline-error"))
    }

    func testElAndSpan() {
        let h = html("""
        dv.span('hello')
        dv.el('strong', 'world')
        """)
        XCTAssertTrue(h.contains("<span>hello</span>"))
        XCTAssertTrue(h.contains("<strong>world</strong>"))
    }
}
