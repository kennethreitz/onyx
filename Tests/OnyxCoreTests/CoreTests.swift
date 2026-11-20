import XCTest
@testable import OnyxCore

final class CoreTests: XCTestCase {
    func testFrontmatter() {
        let fm = Frontmatter.parse("---\ntype: planet\norder: 3\ntags: [a, \"b c\"]\naliases:\n  - Sol\n  - Sun\n---\n# Body\n")
        XCTAssertEqual(fm["type"], .string("planet"))
        XCTAssertEqual(fm["order"], .number(3))
        XCTAssertEqual(fm["tags"], .list(["a", "b c"]))
        XCTAssertEqual(fm["aliases"], .list(["Sol", "Sun"]))
        XCTAssertEqual(fm.lineCount, 8)
    }

    func testLinksTagsHeadings() {
        let s = NoteParser.summarize("---\ntags: [x]\n---\n# Title\nSee [[Note A#Part|alias]] and ![[pic.png]] #tag/sub\n```\n[[NotALink]] #nottag\n```\n## Two")
        XCTAssertEqual(s.links.map(\.target), ["Note A", "pic.png"])
        XCTAssertEqual(s.links[0].heading, "Part"); XCTAssertEqual(s.links[0].alias, "alias")
        XCTAssertTrue(s.links[1].isEmbed)
        XCTAssertEqual(Set(s.tags), ["x", "tag/sub"])
        XCTAssertEqual(s.headings.map(\.text), ["Title", "Two"])
    }

    func snapshot() -> VaultSnapshot {
        var snap = VaultSnapshot(root: URL(fileURLWithPath: "/tmp/none"))
        let files = [
            "Knowledge/Astrology/Planets/Sun.md": "---\ntype: planet\norder: 1\nmetal: Gold\n---\n# Sun\n[[Moon]]",
            "Knowledge/Astrology/Planets/Moon.md": "---\ntype: planet\norder: 2\nmetal: Silver\n---\n# Moon\n[[Sun]] [[Missing]]",
            "Knowledge/Astrology/Planets/Planets.md": "# Planets",
            "Projects/Moon.md": "# other moon",
        ]
        for (p, c) in files { snap.notes[p] = VaultSnapshot.makeRecord(rel: p, content: c) }
        snap.rebuildDerived()
        return snap
    }

    func testResolveAndBacklinks() {
        let snap = snapshot()
        XCTAssertEqual(snap.resolve("Moon", from: "Knowledge/Astrology/Planets/Sun.md"), "Knowledge/Astrology/Planets/Moon.md")
        XCTAssertEqual(snap.resolve("Projects/Moon"), "Projects/Moon.md")
        XCTAssertEqual(snap.backlinks["Knowledge/Astrology/Planets/Sun.md"], ["Knowledge/Astrology/Planets/Moon.md"])
        XCTAssertNotNil(snap.unresolved["Missing"])
        XCTAssertEqual(snap.tree.children?.map(\.name), ["Knowledge", "Projects"])
    }

    func testDataview() throws {
        let snap = snapshot()
        let r = try Dataview.run("TABLE WITHOUT ID file.link AS \"Planet\", metal AS \"Metal\"\nFROM \"Knowledge/Astrology/Planets\"\nWHERE type = \"planet\"\nSORT order DESC", in: snap)
        XCTAssertEqual(r.headers, ["Planet", "Metal"])
        XCTAssertEqual(r.rows.map { $0[1].text }, ["Silver", "Gold"])
        let l = try Dataview.run("LIST FROM \"Projects\"", in: snap)
        XCTAssertEqual(l.rows.count, 1)
        let c = try Dataview.run("TABLE choice(metal, metal, \"—\") AS M FROM \"Knowledge\" SORT file.name ASC", in: snap)
        XCTAssertEqual(c.rows.map { $0[1].text }, ["Silver", "—", "Gold"])
    }

    func testSearchAndFuzzy() {
        let snap = snapshot()
        XCTAssertEqual(snap.search("silver").first?.name, "Moon")
        XCTAssertEqual(snap.search("tag:nothing").count, 0)
        XCTAssertNotNil(Fuzzy.score("tbc", "Table of Correspondences"))
        XCTAssertNil(Fuzzy.score("zzz", "Table"))
        XCTAssertGreaterThan(Fuzzy.score("sun", "Sun")!, Fuzzy.score("sun", "Sunday Notes about planets")!)
    }

    func testKanbanAndDaily() {
        let b = KanbanBoard.parse("---\nkanban-plugin: board\n---\n\n## ToDo\n\n- [ ] one\n- [x] two\n\n## Done\n\n- [x] three\n\n%% kanban:settings\n```\n{}\n```\n%%")
        XCTAssertEqual(b.lanes.map(\.title), ["ToDo", "Done"])
        XCTAssertEqual(b.lanes[0].cards.map(\.done), [false, true])
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 25
        let d = Calendar.current.date(from: c)!
        XCTAssertEqual(DailyNotes.fileName(for: d), "2026-10-25.md")
        XCTAssertTrue(DailyNotes.template(for: d).contains("# Sunday, October 25, 2026"))
    }

    func testRhymeMask() {
        let m = RhymePad.mask("---\na: b\n---\nline `code` end\n```\nx\n```\nlast")
        XCTAssertEqual(m.components(separatedBy: "\n"), ["", "", "", "line        end", "", "", "", "last"])
    }

    func testGraphLayout() {
        var g = GraphData.build(snapshot())
        XCTAssertEqual(g.ids.count, 4)
        XCTAssertEqual(g.edges.count, 1)
        g.layout(iterations: 50)
        XCTAssertTrue(g.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }
}
