
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
        let h = html("dv.paragraph(typeof dv.io + ' ' + typeof dv.io.load + ' ' + typeof dv.fileWrite + ' ' + typeof dv.io.write)")
        XCTAssertTrue(h.contains("object function undefined undefined"), h)
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

    func testLinkSourcesAndPagePaths() {
        let names = html("""
        dv.list(dv.pages('outgoing([[Sun]])').map(p => p.file.name))
        """)
        XCTAssertTrue(names.contains("Moon"), names)
        XCTAssertFalse(names.contains("Launch"), names)
        let incoming = html("""
        dv.list(dv.pages('incoming([[Sun]])').map(p => p.file.name))
        """)
        XCTAssertTrue(incoming.contains("Moon"), incoming)
        let wiki = html("""
        dv.list(dv.pages('[[Sun]]').map(p => p.file.name))
        """)
        XCTAssertTrue(wiki.contains("Moon"), wiki)
        let selfLinks = html("""
        dv.list(dv.pages('[[]]').map(p => p.file.name))
        """, from: "Knowledge/Astrology/Planets/Sun.md")
        XCTAssertTrue(selfLinks.contains("Moon"), selfLinks)
        let paths = html("dv.paragraph(dv.pagePaths('\"Knowledge/Astrology/Planets\"').length)")
        XCTAssertTrue(paths.contains("2"), paths)
    }

    func testQueryExecuteEvaluateAndMarkdown() {
        let h = html("""
        const q = await dv.query('LIST FROM outgoing([[Sun]])');
        dv.paragraph(q.successful + ' ' + q.value.type + ' ' + q.value.values.length);
        const md = await dv.queryMarkdown('LIST FROM "Projects"');
        dv.paragraph(md.value);
        dv.execute('LIST FROM "Projects"');
        dv.executeJs('dv.span("from-exec")');
        dv.paragraph(String(dv.tryEvaluate("2 + 2")));
        dv.paragraph(String(dv.tryEvaluate("x + 2", {x: 3})));
        dv.paragraph(dv.markdownList([1, 2, 3]));
        """)
        XCTAssertTrue(h.contains("true list"), h)
        XCTAssertTrue(h.contains("[[Launch]]") || h.contains("Launch"), h)
        XCTAssertTrue(h.contains("from-exec"), h)
        XCTAssertTrue(h.contains("4"), h)
        XCTAssertTrue(h.contains("5"), h)
        XCTAssertTrue(h.contains("- 1"), h)
    }

    func testTryQueryThrows() {
        let h = html("""
        try { await dv.tryQuery('CHART file.day FROM "Daily"'); dv.paragraph("ok"); }
        catch (e) { dv.paragraph("caught " + e); }
        """)
        XCTAssertTrue(h.contains("caught"), h)
        XCTAssertFalse(h.contains(">ok<") || h.contains(">ok</p>"), h)
    }

    func testUtilitiesParseLinksAndDuration() {
        let h = html("""
        dv.paragraph(dv.isArray(dv.array(1)) + ' ' + dv.equal(1, 1) + ' ' + (dv.compare(1, 2) < 0));
        const link = dv.fileLink("Moon", false, "The Moon");
        dv.paragraph(link.name);
        const d = dv.duration("8 minutes");
        dv.paragraph(d && d.minutes);
        const parsed = dv.parse("2020-08-14");
        dv.paragraph(parsed instanceof Date ? parsed.toISOString().slice(0, 10) : "nope");
        """)
        XCTAssertTrue(h.contains("true true true"), h)
        XCTAssertTrue(h.contains("The Moon"), h)
        XCTAssertTrue(h.contains("8"), h)
        XCTAssertTrue(h.contains("2020-08-14"), h)
    }

    func testIOAndViewFromTempVault() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("onyx-dvjs-\(UUID().uuidString)")
        let views = root.appendingPathComponent("views/custom", isDirectory: true)
        try FileManager.default.createDirectory(at: views, withIntermediateDirectories: true)
        try "name,metal\nSun,Gold\nMoon,Silver\n".write(to: root.appendingPathComponent("planets.csv"), atomically: true, encoding: .utf8)
        try "dv.paragraph('view-arg-' + input.label);".write(to: views.appendingPathComponent("view.js"), atomically: true, encoding: .utf8)
        try "p.view-color { color: #123; }".write(to: views.appendingPathComponent("view.css"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        var s = snap()
        s.root = root
        let path = "Knowledge/Astrology/Planets/Sun.md"
        func run(_ src: String) -> String {
            switch DataviewJS.run(src, in: s, from: path, now: now) {
            case .html(let h): return h
            case .error(let e): return "ERROR:" + e
            }
        }

        let io = run("""
        const text = await dv.io.load("Sun");
        dv.paragraph(text.includes("Gold") ? "loaded" : "missing");
        const rows = await dv.io.csv("planets.csv");
        dv.paragraph(rows.map(r => r.metal).join(","));
        dv.paragraph(dv.io.normalize("planets.csv"));
        await dv.view("views/custom", { label: "ok" });
        """)
        XCTAssertTrue(io.contains("loaded"), io)
        XCTAssertTrue(io.contains("Gold,Silver") || io.contains("Gold, Silver"), io)
        XCTAssertTrue(io.contains("planets.csv"), io)
        XCTAssertTrue(io.contains("view-arg-ok"), io)
        XCTAssertTrue(io.contains("<style>") && io.contains("view-color"), io)

        let escape = run("""
        const a = await dv.io.load("../../../../etc/passwd");
        const b = await dv.io.load("/etc/passwd");
        dv.paragraph(String(a) + " " + String(b) + " " + String(dv.io.normalize("../../etc/passwd")));
        """)
        XCTAssertTrue(escape.contains("undefined undefined undefined") || (escape.contains("undefined") && !escape.contains("root:")), escape)

        let hidden = run("""
        try { await dv.view(".hidden/view", {}); dv.paragraph("opened"); }
        catch (e) { dv.paragraph("hidden " + e); }
        """)
        XCTAssertTrue(hidden.contains("hidden"), hidden)
        XCTAssertFalse(hidden.contains("opened"), hidden)
    }

    func testDataviewAliasAndOfficialHeader() {
        let h = html("""
        dataview.header(3, "Planets");
        """)
        XCTAssertTrue(h.contains("<h3>Planets</h3>"), h)
    }
}
