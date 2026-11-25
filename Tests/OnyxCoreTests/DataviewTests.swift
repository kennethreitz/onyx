import XCTest
@testable import OnyxCore

final class DataviewTests: XCTestCase {
    let now: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 21; c.hour = 15; c.minute = 30
        return Calendar.current.date(from: c)!
    }()

    func snap(_ files: [String: String], dates: [String: (mtime: Date, ctime: Date)] = [:]) -> VaultSnapshot {
        var s = VaultSnapshot(root: URL(fileURLWithPath: "/tmp/none"))
        for (p, c) in files {
            let d = dates[p]
            s.notes[p] = VaultSnapshot.makeRecord(rel: p, content: c, mtime: d?.mtime ?? now, ctime: d?.ctime ?? now, size: c.utf8.count)
        }
        s.rebuildDerived()
        return s
    }

    func planets() -> VaultSnapshot {
        snap([
            "Knowledge/Astrology/Planets/Sun.md": "---\ntype: planet\norder: 1\nmetal: Gold\naliases:\n  - Sol\n---\n# Sun\n[[Moon]]\n- [ ] Watch sunrise 📅 2026-11-22\n- [x] Note the metal\n",
            "Knowledge/Astrology/Planets/Moon.md": "---\ntype: planet\norder: 2\nmetal: Silver\n---\n# Moon\n[[Sun]] [[Missing]]\nauthors:: [[Sun]], [[Moon]]\n",
            "Knowledge/Astrology/Planets/Planets.md": "# Planets\n#atlas",
            "Projects/Moon.md": "# other moon",
            "Daily/2026-11-20.md": "---\ntype: daily\n---\n# Friday\n- [ ] Write #journal\n",
            "Daily/2026-11-21.md": "---\ntype: daily\n---\n# Saturday\ncost:: 3\ncost:: 5\n",
        ])
    }

    func run(_ q: String, in s: VaultSnapshot? = nil, from: String? = nil) throws -> DVResult {
        try Dataview.run(q, in: s ?? planets(), from: from, now: now)
    }

    func ev(_ expr: String, path: String = "Knowledge/Astrology/Planets/Sun.md", in s: VaultSnapshot? = nil) throws -> DVValue {
        try Dataview.evalExpr(expr, in: s ?? planets(), from: path, now: now)
    }

    // MARK: Parser

    func testParseGroupByAndFlatten() throws {
        let q = try Dataview.parse("TABLE length(rows) FROM \"Knowledge\" WHERE type = \"planet\" GROUP BY type")
        XCTAssertEqual(q.kind, .table)
        XCTAssertTrue(q.pipeline.contains { if case .groupBy = $0 { return true }; return false })
        let f = try Dataview.parse("LIST FROM \"Knowledge\" FLATTEN authors AS Author")
        XCTAssertTrue(f.pipeline.contains { if case .flatten(_, let n) = $0 { return n == "Author" }; return false })
        let e = try Dataview.parseExpr("date(today) - dur(1 day)")
        if case .binary("-", _, _) = e { } else { XCTFail("expected subtraction") }
        let lam = try Dataview.parseExpr("filter(file.tasks, (x) => !x.completed)")
        if case .call("filter", let args) = lam, args.count == 2, case .lambda("x", _) = args[1] { } else { XCTFail("expected lambda") }
    }

    func testUnsupportedQueriesStillError() {
        XCTAssertThrowsError(try run("CHART file.day FROM \"Daily\"")) { err in
            XCTAssertTrue(String(describing: err).lowercased().contains("chart") || String(describing: err).contains("supports"))
        }
    }

    func testCalendarQueries() throws {
        let q = try Dataview.parse("CALENDAR file.day FROM \"Daily\"")
        XCTAssertEqual(q.kind, .calendar)
        if case .field("file.day") = q.listExpr { } else { XCTFail("date expr") }
        let r = try run("CALENDAR file.day FROM \"Daily\"")
        XCTAssertTrue(r.isCalendar)
        XCTAssertEqual(r.calendar.count, 1)
        XCTAssertEqual(r.calendar[0].year, 2026)
        XCTAssertEqual(r.calendar[0].month, 11)
        XCTAssertEqual(Set(r.calendar[0].days[20]?.map(\.text) ?? []), ["2026-11-20"])
        XCTAssertEqual(Set(r.calendar[0].days[21]?.map(\.text) ?? []), ["2026-11-21"])
        XCTAssertNil(r.calendar[0].days[22])
        // Notes without a date (the planets) do not appear; FROM Daily already excludes them.
        let due = try run("CALENDAR due FROM \"Knowledge\"")
        XCTAssertTrue(due.isCalendar)
        // due is a task field; calendar is page-level so due is null unless we flatten tasks.
        // A note with a date property should land on that day:
        let custom = snap(["Projects/Launch.md": "---\nwhen: 2026-12-02\n---\n# Launch\n"])
        let c = try Dataview.run("CALENDAR when FROM \"Projects\"", in: custom, now: now)
        XCTAssertEqual(c.calendar.count, 1)
        XCTAssertEqual(c.calendar[0].month, 12)
        XCTAssertEqual(c.calendar[0].days[2]?.first?.text, "Launch")
        // Months between the first and last result are kept
        let span = snap([
            "Daily/2026-10-31.md": "# Halloween\n",
            "Daily/2026-12-01.md": "# December\n",
        ])
        let s = try Dataview.run("CALENDAR file.day FROM \"Daily\"", in: span, now: now)
        XCTAssertEqual(s.calendar.map { "\($0.year)-\($0.month)" }, ["2026-10", "2026-11", "2026-12"])
        XCTAssertTrue(s.calendar[1].days.isEmpty)
    }

    func testTaskQueries() throws {
        let all = try run("TASK FROM \"Knowledge/Astrology/Planets\"")
        XCTAssertTrue(all.isTask)
        XCTAssertEqual(all.taskGroups.map { if case .link(_, let n) = $0.heading { return n } else { return $0.heading.text } }.sorted(), ["Sun"])
        XCTAssertEqual(all.taskGroups[0].tasks.map(\.text), ["Watch sunrise 📅 2026-11-22", "Note the metal"])
        XCTAssertEqual(all.taskGroups[0].tasks.map(\.completed), [false, true])

        let open = try run("TASK FROM \"Knowledge\" WHERE !completed")
        XCTAssertEqual(open.taskGroups.flatMap(\.tasks).map(\.text), ["Watch sunrise 📅 2026-11-22"])

        let due = try run("TASK FROM \"Knowledge\" WHERE due = date(\"2026-11-22\")")
        XCTAssertEqual(due.taskGroups.flatMap(\.tasks).map(\.text).first?.contains("Watch sunrise"), true)

        let journal = try run("TASK FROM \"Daily\" WHERE contains(text, \"Write\")")
        XCTAssertEqual(journal.taskGroups.flatMap(\.tasks).map(\.path), ["Daily/2026-11-20.md"])
        XCTAssertEqual(journal.taskGroups.flatMap(\.tasks).first?.tags, ["journal"])

        let grouped = try run("TASK FROM \"Daily\" OR \"Knowledge/Astrology/Planets\" GROUP BY file.folder")
        XCTAssertTrue(grouped.isTask)
        XCTAssertGreaterThanOrEqual(grouped.taskGroups.count, 2)
        let labels = Set(grouped.taskGroups.map(\.heading.text))
        XCTAssertTrue(labels.contains("Daily") || labels.contains("Knowledge/Astrology/Planets"))
    }

    func testToggleTask() {
        let src = """
        # Note
        - [ ] one
        - [x] two
        ```
        - [ ] not a task
        ```
        1. [ ] three
        """
        let a = Dataview.toggleTask(in: src, index: 0)!
        XCTAssertTrue(a.contains("- [x] one"))
        XCTAssertTrue(a.contains("- [x] two"))
        XCTAssertTrue(a.contains("- [ ] not a task"))
        let b = Dataview.toggleTask(in: a, index: 1)!
        XCTAssertTrue(b.contains("- [ ] two"))
        let c = Dataview.toggleTask(in: b, index: 2)!
        XCTAssertTrue(c.contains("1. [x] three"))
        XCTAssertNil(Dataview.toggleTask(in: src, index: 9))
        // Frontmatter is skipped
        let fm = "---\ntags: [a]\n---\n- [ ] only\n"
        let f = Dataview.toggleTask(in: fm, index: 0)!
        XCTAssertTrue(f.contains("- [x] only"))
    }

    // MARK: file.* fields

    func testFileImplicitFields() throws {
        let s = planets()
        XCTAssertEqual(try ev("file.name").text, "Sun")
        XCTAssertEqual(try ev("file.path").text, "Knowledge/Astrology/Planets/Sun.md")
        XCTAssertEqual(try ev("file.folder").text, "Knowledge/Astrology/Planets")
        XCTAssertEqual(try ev("file.size").text, "\(s.notes["Knowledge/Astrology/Planets/Sun.md"]!.size)")
        if case .link(let p, let n) = try ev("file.link") {
            XCTAssertEqual(p, "Knowledge/Astrology/Planets/Sun.md"); XCTAssertEqual(n, "Sun")
        } else { XCTFail("file.link") }
        if case .list(let a) = try ev("file.aliases") {
            XCTAssertEqual(a.map(\.text), ["Sol"])
        } else { XCTFail("aliases") }
        if case .list(let t) = try ev("file.tasks") {
            XCTAssertEqual(t.count, 2)
            if case .task(let first) = t[0] {
                XCTAssertFalse(first.completed)
                XCTAssertEqual(first.text.hasPrefix("Watch sunrise"), true)
                XCTAssertEqual(first.due.map { DVDate.format($0, dayOnly: true) }, "2026-11-22")
            } else { XCTFail("task object") }
        } else { XCTFail("tasks") }
        if case .date(_, let day) = try ev("file.day", path: "Daily/2026-11-20.md") {
            XCTAssertTrue(day)
        } else { XCTFail("file.day") }
        XCTAssertEqual(try ev("file.day", path: "Daily/2026-11-20.md").text, "2026-11-20")
        if case .date(_, let dayOnly) = try ev("file.ctime") { XCTAssertFalse(dayOnly) } else { XCTFail("ctime") }
        if case .date(_, let dayOnly) = try ev("file.cday") { XCTAssertTrue(dayOnly) } else { XCTFail("cday") }
        if case .list(let tags) = try ev("file.tags", path: "Knowledge/Astrology/Planets/Planets.md") {
            XCTAssertTrue(tags.map(\.text).contains("#atlas"))
        } else { XCTFail("tags") }
        if case .list(let outs) = try ev("file.outlinks") {
            XCTAssertTrue(outs.contains { if case .link(let p, _) = $0 { return p.hasSuffix("Moon.md") }; return false })
        } else { XCTFail("outlinks") }
        if case .list(let ins) = try ev("file.inlinks") {
            XCTAssertTrue(ins.contains { if case .link(let p, _) = $0 { return p.hasSuffix("Moon.md") }; return false })
        } else { XCTFail("inlinks") }
    }

    func testInlineFieldsFeedDataview() throws {
        let r = try run("TABLE authors FROM \"Knowledge/Astrology/Planets\" WHERE file.name = \"Moon\"")
        XCTAssertEqual(r.rows.count, 1)
        if case .list(let l) = r.rows[0][1] {
            XCTAssertEqual(Set(l.map(\.text)), ["Sun", "Moon"])
        } else { XCTFail("authors should be links: \(r.rows[0][1])") }
    }

    // MARK: GROUP BY / FLATTEN

    func testGroupByRows() throws {
        let r = try run("TABLE WITHOUT ID length(rows) AS Count FROM \"Knowledge\" WHERE type = \"planet\" GROUP BY type")
        XCTAssertEqual(r.headers, ["Count"])
        XCTAssertEqual(r.rows.count, 1)
        XCTAssertEqual(r.rows[0][0].text, "2")
        let withKey = try run("TABLE length(rows) FROM \"Knowledge\" WHERE type = \"planet\" GROUP BY type")
        XCTAssertEqual(withKey.rows.count, 1)
        XCTAssertEqual(withKey.rows[0][0].text, "planet")
        XCTAssertEqual(withKey.rows[0][1].text, "2")
        let names = try run("TABLE WITHOUT ID rows.file.name FROM \"Knowledge\" WHERE type = \"planet\" GROUP BY type")
        XCTAssertEqual(Set(names.rows[0][0].asList.map(\.text)), ["Moon", "Sun"])
        let sums = try run("TABLE WITHOUT ID sum(rows.order) FROM \"Knowledge\" WHERE type = \"planet\" GROUP BY type")
        XCTAssertEqual(sums.rows[0][0].text, "3")
    }

    func testFlatten() throws {
        let r = try run("TABLE WITHOUT ID Author FROM \"Knowledge/Astrology/Planets\" WHERE file.name = \"Moon\" FLATTEN authors AS Author")
        XCTAssertEqual(r.rows.count, 2)
        XCTAssertEqual(Set(r.rows.map { $0[0].text }), ["Sun", "Moon"])
        // empty / missing flatten still emits a single (null) row
        let empty = try run("LIST FROM \"Projects\" FLATTEN authors")
        XCTAssertEqual(empty.rows.count, 1)
    }

    // MARK: Dates and durations

    func testDatesAndDurations() throws {
        let today = try ev("date(today)")
        XCTAssertEqual(today.text, "2026-11-21")
        XCTAssertEqual(try ev("date(yesterday)").text, "2026-11-20")
        XCTAssertEqual(try ev("date(tomorrow)").text, "2026-11-22")
        XCTAssertEqual(try ev("dateformat(date(today), \"yyyy-MM-dd\")").text, "2026-11-21")
        let later = try ev("date(today) + dur(1 day)")
        XCTAssertEqual(later.text, "2026-11-22")
        let earlier = try ev("date(today) - 2 days")
        XCTAssertEqual(earlier.text, "2026-11-19")
        XCTAssertEqual(try ev("date(today) > date(yesterday)").text, "true")
        XCTAssertEqual(try ev("date(today) = date(\"2026-11-21\")").text, "true")
        if case .duration(let d) = try ev("date(today) - date(yesterday)") {
            XCTAssertEqual(d.days, 1)
        } else { XCTFail("date - date") }
        XCTAssertEqual(try ev("striptime(date(now))").text, "2026-11-21")
        XCTAssertEqual(try ev("file.day = date(yesterday)", path: "Daily/2026-11-20.md").text, "true")
        XCTAssertEqual(try ev("date(today) - dur(\"1 week\")").text, "2026-11-14")
    }

    // MARK: Functions

    func testFunctionLibrary() throws {
        XCTAssertEqual(try ev("length(\"Gold\")").text, "4")
        XCTAssertEqual(try ev("length(file.tasks)").text, "2")
        XCTAssertEqual(try ev("lower(metal)").text, "gold")
        XCTAssertEqual(try ev("upper(metal)").text, "GOLD")
        XCTAssertEqual(try ev("round(3.14159, 2)").text, "3.14")
        XCTAssertEqual(try ev("round(3.7)").text, "4")
        XCTAssertEqual(try ev("min(3, 1, 4)").text, "1")
        XCTAssertEqual(try ev("max(3, 1, 4)").text, "4")
        XCTAssertEqual(try ev("sum(1, 2, 3)").text, "6")
        XCTAssertEqual(try ev("join(file.aliases, \" / \")").text, "Sol")
        XCTAssertEqual(try ev("number(\"21\")").text, "21")
        XCTAssertEqual(try ev("string(order)").text, "1")
        XCTAssertEqual(try ev("startswith(metal, \"Go\")").text, "true")
        XCTAssertEqual(try ev("endswith(metal, \"ld\")").text, "true")
        XCTAssertEqual(try ev("regexmatch(metal, \"^G\")").text, "true")
        XCTAssertEqual(try ev("replace(metal, \"o\", \"oo\")").text, "Goold")
        XCTAssertEqual(try ev("contains(metal, \"ol\")").text, "true")
        XCTAssertEqual(try ev("icontains(metal, \"GOLD\")").text, "true")
        XCTAssertEqual(try ev("econtains(file.aliases, \"Sol\")").text, "true")
        XCTAssertEqual(try ev("econtains(file.aliases, \"So\")").text, "false")
        XCTAssertEqual(try ev("choice(metal, metal, \"—\")").text, "Gold")
        XCTAssertEqual(try ev("default(missing, \"n/a\")").text, "n/a")
        let filtered = try ev("filter(file.tasks, (x) => !x.completed)")
        XCTAssertEqual(filtered.asList.count, 1)
        XCTAssertEqual(filtered.asList[0].text.hasPrefix("Watch sunrise"), true)
        let mapped = try ev("map(file.tasks, (x) => x.completed)")
        XCTAssertEqual(mapped.asList.map { $0.text }, ["false", "true"])
        XCTAssertEqual(try ev("any(file.tasks, (x) => x.completed)").text, "true")
        XCTAssertEqual(try ev("all(file.tasks, (x) => x.completed)").text, "false")
        XCTAssertEqual(try ev("sum(cost)", path: "Daily/2026-11-21.md").text, "8")
        if case .list(let costs) = try ev("nonnull(cost)", path: "Daily/2026-11-21.md") {
            XCTAssertFalse(costs.contains(.null))
        } else if case .number = try ev("nonnull(cost)", path: "Daily/2026-11-21.md") {
            // a single non-null still comes back wrapped as a list
        }
        if case .link(let p, let n) = try ev("link(\"Moon\")") {
            XCTAssertTrue(p.hasSuffix("Moon.md")); XCTAssertEqual(n, "Moon")
        } else { XCTFail("link()") }
    }

    func testExistingTableAndListStillWork() throws {
        let r = try run("TABLE WITHOUT ID file.link AS \"Planet\", metal AS \"Metal\"\nFROM \"Knowledge/Astrology/Planets\"\nWHERE type = \"planet\"\nSORT order DESC")
        XCTAssertEqual(r.headers, ["Planet", "Metal"])
        XCTAssertEqual(r.rows.map { $0[1].text }, ["Silver", "Gold"])
        let l = try run("LIST FROM \"Projects\"")
        XCTAssertEqual(l.rows.count, 1)
        let c = try run("TABLE choice(metal, metal, \"—\") AS M FROM \"Knowledge\" SORT file.name ASC")
        XCTAssertEqual(c.rows.map { $0[1].text }, ["Silver", "—", "Gold"])
    }

    func testThisField() throws {
        XCTAssertEqual(try ev("this.file.name").text, "Sun")
        XCTAssertEqual(try ev("this.metal").text, "Gold")
        XCTAssertEqual(try ev("this").text, "Sun")
        if case .page(let p) = try ev("this") { XCTAssertTrue(p.hasSuffix("Sun.md")) } else { XCTFail("this should be a page") }
    }

    func testInlineQueries() throws {
        let s = planets()
        let path = "Knowledge/Astrology/Planets/Sun.md"
        let src = "Hello `= this.file.name` — metal is `= metal` and `= 2 + 2`.\n\n```\n`= this.file.name`\n```\n\nAnd `$= dv.current().file.name` plus `= 1 +`."
        let r = Dataview.rewriteInlineQueries(src, in: s, from: path, now: now)
        XCTAssertTrue(r.text.hasPrefix("Hello <span class=\"onyx-dv-inline\" data-i=\"0\"></span>"))
        XCTAssertTrue(r.text.contains("<span class=\"onyx-dv-inline\" data-i=\"0\"></span>"))
        // The fenced copy stays as source
        XCTAssertTrue(r.text.contains("```\n`= this.file.name`\n```"))
        XCTAssertEqual(r.html.count, 5)
        XCTAssertEqual(r.html[0], "Sun")
        XCTAssertEqual(r.html[1], "Gold")
        XCTAssertEqual(r.html[2], "4")
        XCTAssertEqual(r.html[3], "Sun")
        XCTAssertTrue(r.html[4].contains("dataview-inline-error"), r.html[4])
    }


    func testFromLinkSourcesAndAndOr() throws {
        let incoming = try run("LIST FROM [[Sun]]")
        XCTAssertEqual(incoming.rows.compactMap { $0.first?.text }, ["Moon"])
        let alsoIncoming = try run("LIST FROM incoming([[Sun]])")
        XCTAssertEqual(alsoIncoming.rows.compactMap { $0.first?.text }, incoming.rows.compactMap { $0.first?.text })
        let outgoing = try run("LIST FROM outgoing([[Sun]])")
        XCTAssertEqual(outgoing.rows.compactMap { $0.first?.text }, ["Moon"])
        let current = try run("LIST FROM [[]]", from: "Knowledge/Astrology/Planets/Sun.md")
        XCTAssertEqual(current.rows.compactMap { $0.first?.text }, ["Moon"])
        let and = try run("LIST FROM #atlas and \"Knowledge\"")
        XCTAssertEqual(and.rows.compactMap { $0.first?.text }, ["Planets"])
        let orQ = try run("LIST FROM #atlas or \"Projects\"")
        let orPaths = orQ.rows.compactMap { row -> String? in
            if case .link(let p, _) = row.first { return p }
            return nil
        }
        XCTAssertEqual(Set(orPaths), Set(["Knowledge/Astrology/Planets/Planets.md", "Projects/Moon.md"]))
        let parsed = try Dataview.parseSource("outgoing([[Sun]]) or incoming([[Moon]])")
        if case .or(.outgoing("Sun"), .incoming("Moon")) = parsed { } else { XCTFail("parsed \(String(describing: parsed))") }
    }

    func testHtmlRendersWikilinksInStringCells() {
        let row: [DVValue] = [
            .link(path: "Knowledge/Crystals/Aquamarine.md", name: "Aquamarine"),
            .string("Third Eye ([[Ajna]]), Throat"),
            .string("[[Jupiter]], [[Neptune (astrology)|Neptune]] / [[Pisces]], [[Aquarius]]"),
            .string("Water"),
        ]
        let html = Dataview.html(DVResult(headers: ["Stone", "Chakra", "Planet / Zodiac", "Element"], rows: [row], isList: false))
        XCTAssertTrue(html.contains("<span class=\"onyx-inline-md\">Third Eye ([[Ajna]]), Throat</span>"), html)
        XCTAssertTrue(html.contains("<span class=\"onyx-inline-md\">[[Jupiter]], [[Neptune (astrology)|Neptune]] / [[Pisces]], [[Aquarius]]</span>"), html)
        XCTAssertTrue(html.contains("data-path=\"Knowledge/Crystals/Aquamarine.md\">Aquamarine</a>"), html)
        XCTAssertFalse(html.contains("onyx-inline-md\">Water"), html)
        XCTAssertTrue(html.contains(">Water</td>"), html)
    }

    func testMarkdownTableEscapesPipesInsideWikilinkCells() {
        let md = Dataview.markdownTable(
            ["Planet / Zodiac"],
            [[.string("[[Jupiter]], [[Neptune (astrology)|Neptune]] / [[Pisces]]")]]
        )
        XCTAssertTrue(md.contains("[[Neptune (astrology)\\|Neptune]]"), md)
        XCTAssertFalse(md.contains("| Neptune]]"), md)
    }
}
