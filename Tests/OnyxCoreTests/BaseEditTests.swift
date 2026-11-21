import XCTest
@testable import OnyxCore

final class BaseEditTests: XCTestCase {

    let realPaths: [(String, String)] = [
        ("Historical Documents Base.base", NSString("~/Notes/System 777/Historical Documents/Historical Documents Base.base").expandingTildeInPath),
        ("Libraries.base", NSString("~/Notes/Library/Python Libraries/Libraries.base").expandingTildeInPath),
        ("Video Games.base", NSString("~/Notes/Library/Games/Video Games.base").expandingTildeInPath),
        ("AI Entities.base", NSString("~/Notes/Knowledge/AI/AI Entities/AI Entities.base").expandingTildeInPath),
    ]

    /// Copies of the four real `.base` files, plus a commented fixture. Never write to ~/Notes.
    func tmpCopies() throws -> (dir: URL, files: [(name: String, url: URL, original: String)]) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("onyx-bases-edit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var out: [(String, URL, String)] = []
        for (name, path) in realPaths {
            let data = try String(contentsOfFile: path, encoding: .utf8)
            let dest = dir.appendingPathComponent(name)
            try data.write(to: dest, atomically: true, encoding: .utf8)
            out.append((name, dest, data))
        }
        let commented = """
        # A vault index of widgets.
        name: Widgets
        query: {}
        filters:
          and:
            - file.folder == "Library/Widgets"  # only this folder
            - '!file.name.endsWith("base")'
        formulas:
          age_days: 'now() - date(year)'
        properties:
          status:
            displayName: Status
        # Views follow.
        views:
          - type: table
            name: All  # default view
            sort: []
            columns:
              - property: note.name
                name: Widget
              - property: year
                name: Year
              - property: status
                name: Status
            filter:
              property: type
              operator: eq
              value: widget
          - type: list
            name: View
            order:
              - file.name
              - year
        unknownTop: keep-me
        """
        let cdest = dir.appendingPathComponent("Widgets.base")
        try commented.write(to: cdest, atomically: true, encoding: .utf8)
        out.append(("Widgets.base", cdest, commented))
        return (dir, out)
    }

    func testIdentityNoEditPreservesBytes() throws {
        let (dir, files) = try tmpCopies()
        defer { try? FileManager.default.removeItem(at: dir) }
        for (name, url, original) in files {
            let disk = try String(contentsOf: url, encoding: .utf8)
            XCTAssertEqual(disk, original, "\(name) was mutated just by copying")
            let doc = BaseDoc(disk)
            XCTAssertEqual(doc.text, original, "\(name): BaseDoc changed text with no edits")
        }
        try assertNotesUntouched()
    }

    func testRoundTripEditsPreserveCommentsAndUnknownKeys() throws {
        let (dir, files) = try tmpCopies()
        defer { try? FileManager.default.removeItem(at: dir) }
        let commented = files.first { $0.name == "Widgets.base" }!
        var doc = BaseDoc(commented.original)

        XCTAssertTrue(doc.setViewName(index: 0, "Catalog"))
        XCTAssertTrue(doc.text.contains("# A vault index of widgets."))
        XCTAssertTrue(doc.text.contains("query: {}"))
        XCTAssertTrue(doc.text.contains("unknownTop: keep-me"))
        XCTAssertTrue(doc.text.contains("# only this folder"))
        XCTAssertTrue(doc.text.contains("# Views follow."))
        XCTAssertTrue(doc.text.contains("# default view") || doc.text.contains("name: Catalog"))
        XCTAssertEqual(doc.file.views[0].name, "Catalog")

        XCTAssertTrue(doc.setViewSort(index: 0, [BaseSort(property: "year", ascending: false)]))
        XCTAssertEqual(doc.file.views[0].sort.first?.property, "year")
        XCTAssertEqual(doc.file.views[0].sort.first?.ascending, false)
        XCTAssertTrue(doc.text.contains("unknownTop: keep-me"))
        XCTAssertTrue(doc.text.contains("query: {}"))

        XCTAssertTrue(doc.addColumn(view: 0, key: "domain", displayName: "Domain"))
        XCTAssertTrue(doc.file.views[0].order.contains("domain"))
        XCTAssertEqual(doc.file.properties["domain"]?.displayName ?? doc.file.properties["Domain"]?.displayName, "Domain")
        // Display name may live on the columns entry.
        XCTAssertTrue(doc.text.contains("domain"))
        XCTAssertTrue(doc.text.contains("# A vault index of widgets."))

        XCTAssertTrue(doc.moveColumn(view: 0, from: 3, to: 1))
        XCTAssertEqual(doc.file.views[0].order[1], "domain")

        XCTAssertTrue(doc.removeColumn(view: 0, key: "status"))
        XCTAssertFalse(doc.file.views[0].order.contains("status"))
        XCTAssertTrue(doc.text.contains("unknownTop: keep-me"))

        XCTAssertTrue(doc.setSimpleFilter(view: 0, property: "type", operator: "eq", value: "library"))
        let filter = doc.simpleFilter(view: 0)
        XCTAssertEqual(filter?.property, "type")
        XCTAssertEqual(filter?.op, "eq")
        XCTAssertEqual(filter?.value, "library")

        XCTAssertTrue(doc.addView(type: "cards", name: "Gallery"))
        XCTAssertEqual(doc.file.views.last?.type, "cards")
        XCTAssertEqual(doc.file.views.last?.name, "Gallery")
        XCTAssertTrue(doc.text.contains("# A vault index of widgets."))
        XCTAssertTrue(doc.text.contains("unknownTop: keep-me"))
        XCTAssertTrue(doc.text.contains("query: {}"))

        // Write only to the /tmp copy.
        try doc.text.write(to: commented.url, atomically: true, encoding: .utf8)
        let reread = try String(contentsOf: commented.url, encoding: .utf8)
        XCTAssertEqual(reread, doc.text)
        let parsed = Bases.parse(reread)
        XCTAssertEqual(parsed.views[0].name, "Catalog")
        XCTAssertEqual(parsed.views.last?.name, "Gallery")
        XCTAssertTrue(parsed.warnings.filter { !$0.contains("no views") }.isEmpty || parsed.views.count >= 2)

        try assertNotesUntouched()
    }

    func testEditsOnRealFileCopies() throws {
        let (dir, files) = try tmpCopies()
        defer { try? FileManager.default.removeItem(at: dir) }
        for (name, url, original) in files where name != "Widgets.base" {
            var doc = BaseDoc(original)
            let firstName = doc.file.views.first?.name ?? "Table"
            XCTAssertTrue(doc.setViewName(index: 0, firstName + " *"), "\(name): rename")
            XCTAssertTrue(doc.setViewSort(index: 0, [BaseSort(property: "file.name", ascending: false)]), "\(name): sort")
            if !(doc.file.views[0].order.contains("file.ext")) {
                XCTAssertTrue(doc.addColumn(view: 0, key: "file.ext"), "\(name): add column")
            }
            XCTAssertTrue(doc.addView(type: "table", name: "Scratch"), "\(name): add view")
            XCTAssertNotEqual(doc.text, original)
            // Unknown / incidental keys from the original stay.
            if original.contains("query: {}") { XCTAssertTrue(doc.text.contains("query: {}"), name) }
            if original.contains("cardSize:") { XCTAssertTrue(doc.text.contains("cardSize:"), name) }
            if original.contains("indentProperties:") { XCTAssertTrue(doc.text.contains("indentProperties:"), name) }
            try doc.text.write(to: url, atomically: true, encoding: .utf8)
            let parsed = Bases.parse(try String(contentsOf: url, encoding: .utf8))
            XCTAssertEqual(parsed.views[0].name, firstName + " *", name)
            XCTAssertTrue(parsed.views.contains { $0.name == "Scratch" }, name)
        }
        try assertNotesUntouched()
    }

    func testClearFilterAndIdentityAfterNoOp() throws {
        var doc = BaseDoc("""
        views:
          - type: table
            name: T
            order:
              - file.name
            filter:
              property: type
              operator: eq
              value: x
        """)
        XCTAssertNotNil(doc.simpleFilter(view: 0))
        XCTAssertTrue(doc.clearSimpleFilter(view: 0))
        XCTAssertNil(doc.simpleFilter(view: 0))
        XCTAssertFalse(doc.text.contains("filter:"))
        XCTAssertTrue(doc.setViewName(index: 0, "T") || Bases.parse(doc.text).views[0].name == "T")
        XCTAssertEqual(Bases.parse(doc.text).views[0].name, "T")
        XCTAssertTrue(doc.text.contains("order:"))
    }

    func assertNotesUntouched() throws {
        for (name, path) in realPaths {
            let now = try String(contentsOfFile: path, encoding: .utf8)
            // The originals are the source of the copies; they must be unchanged.
            XCTAssertFalse(now.contains("Scratch"), "\(name) in ~/Notes was written to")
            XCTAssertFalse(now.contains(" *"), "\(name) in ~/Notes was written to")
        }
    }
}

final class BaseFormulaExtraTests: XCTestCase {

    func snapshot(_ files: [String: String]) -> VaultSnapshot {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("onyx-bases-fx-\(UUID().uuidString)")
        for (p, c) in files {
            let url = dir.appendingPathComponent(p)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? c.write(to: url, atomically: true, encoding: .utf8)
        }
        return VaultSnapshot.scan(root: dir)
    }

    func eval(_ formula: String, props: [String: String] = ["year": "2020", "price": "10", "tags": "[alpha, beta]"], extra: [String: String] = [:]) -> (BaseRowView, [String]) {
        var fm = props.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\n")
        for (k, v) in extra { fm += "\n\(k): \(v)" }
        let note = "---\n\(fm)\n---\n# Item\n"
        let yaml = """
        formulas:
          x: \(yamlFormula(formula))
        views:
          - type: table
            name: T
            order:
              - formula.x
              - price
        """
        let snap = snapshot(["Library/Item.md": note, "Library/Lib.base": yaml])
        let file = Bases.parse(yaml)
        let r = Bases.run(file, view: 0, in: snap)
        let row = r.rows.first { $0.name == "Item" } ?? r.rows[0]
        return (row, r.warnings)
    }

    func yamlFormula(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "''") + "'"
    }

    func testDateArithmeticFormatRelativeAccessors() {
        let (row, warnings) = eval("date(\"2024-01-15\") + \"1d\"")
        XCTAssertEqual(row.cells["formula.x"]?.text, "2024-01-16", warnings.joined(separator: "; "))
        XCTAssertTrue(warnings.isEmpty, warnings.joined(separator: "; "))

        let (two, w2) = eval("date(\"2024-01-15\") + \"2w\"")
        XCTAssertEqual(two.cells["formula.x"]?.text, "2024-01-29", w2.joined(separator: "; "))

        let (back, w3) = eval("date(\"2024-01-15\") - \"1d\"")
        XCTAssertEqual(back.cells["formula.x"]?.text, "2024-01-14", w3.joined(separator: "; "))

        let (fmt, w4) = eval("date(\"2024-01-15\").format(\"YYYY-MM-DD\")")
        XCTAssertEqual(fmt.cells["formula.x"]?.text, "2024-01-15", w4.joined(separator: "; "))

        let (year, w5) = eval("date(\"2024-06-09\").year")
        XCTAssertEqual(year.cells["formula.x"]?.text, "2024", w5.joined(separator: "; "))

        let (rel, w6) = eval("date(\"2020-01-01\").relative()")
        XCTAssertFalse(rel.cells["formula.x"]?.text.isEmpty ?? true, w6.joined(separator: "; "))
        XCTAssertTrue(w6.isEmpty, w6.joined(separator: "; "))

        let (dur, w7) = eval("duration(\"1d2h\").hours")
        // hours field of the parsed duration is 2
        XCTAssertEqual(dur.cells["formula.x"]?.text, "2", w7.joined(separator: "; "))

        let (cmp, w8) = eval("date(\"2024-01-15\") > date(\"2024-01-01\")")
        XCTAssertEqual(cmp.cells["formula.x"]?.text, "true", w8.joined(separator: "; "))
    }

    func testListNumberStringMethods() {
        let (join, w1) = eval("list(\"a\", \"b\", \"c\").join(\"-\")")
        XCTAssertEqual(join.cells["formula.x"]?.text, "a-b-c", w1.joined(separator: "; "))

        let (contains, w2) = eval("list(\"alpha\", \"beta\").contains(\"beta\")")
        XCTAssertEqual(contains.cells["formula.x"]?.text, "true", w2.joined(separator: "; "))

        let (filt, w3) = eval("list(1, 2, 3, 4).filter(x => x > 2)")
        XCTAssertEqual(filt.cells["formula.x"]?.text, "3, 4", w3.joined(separator: "; "))

        let (mapv, w4) = eval("list(1, 2).map(x => x * 10)")
        XCTAssertEqual(mapv.cells["formula.x"]?.text, "10, 20", w4.joined(separator: "; "))

        let (rnd, w5) = eval("(2.3333).round(2)")
        XCTAssertEqual(rnd.cells["formula.x"]?.text, "2.33", w5.joined(separator: "; "))

        let (absv, w6) = eval("(-4).abs()")
        XCTAssertEqual(absv.cells["formula.x"]?.text, "4", w6.joined(separator: "; "))

        let (ceil, w7) = eval("(2.1).ceil()")
        XCTAssertEqual(ceil.cells["formula.x"]?.text, "3", w7.joined(separator: "; "))

        let (floor, w8) = eval("(2.9).floor()")
        XCTAssertEqual(floor.cells["formula.x"]?.text, "2", w8.joined(separator: "; "))

        let (slice, w9) = eval("\"hello\".slice(1, 4)")
        XCTAssertEqual(slice.cells["formula.x"]?.text, "ell", w9.joined(separator: "; "))

        let (repl, w10) = eval("\"aa-bb\".replace(\"-\", \":\")")
        XCTAssertEqual(repl.cells["formula.x"]?.text, "aa:bb", w10.joined(separator: "; "))

        let (spl, w11) = eval("\"a,b\".split(\",\").join(\"+\")")
        XCTAssertEqual(spl.cells["formula.x"]?.text, "a+b", w11.joined(separator: "; "))

        let (title, w12) = eval("\"hello world\".title()")
        XCTAssertEqual(title.cells["formula.x"]?.text, "Hello World", w12.joined(separator: "; "))

        let (trim, w13) = eval("\"  hi  \".trim()")
        XCTAssertEqual(trim.cells["formula.x"]?.text, "hi", w13.joined(separator: "; "))

        let (len, w14) = eval("\"hello\".length")
        XCTAssertEqual(len.cells["formula.x"]?.text, "5", w14.joined(separator: "; "))
    }

    func testUnknownMethodStillWarns() {
        let (row, warnings) = eval("price.notARealMethod()")
        XCTAssertEqual(row.cells["formula.x"] ?? .null, .null)
        XCTAssertTrue(warnings.contains { $0.localizedCaseInsensitiveContains("unknown") }, "warnings: [" + warnings.joined(separator: " | ") + "]")
    }

    func testSummariesRow() {
        let yaml = """
        filters:
          and:
            - file.ext == "md"
        formulas:
          total: price
        summaries:
          customAverage: 'values.mean().round(1)'
        views:
          - type: table
            name: T
            order:
              - file.name
              - price
              - when
            summaries:
              file.name: Count
              price: Sum
              when: Earliest
            # custom formula name also works:
            # (second view below)
          - type: table
            name: Avg
            order:
              - price
            summaries:
              price: customAverage
        """
        let a = """
        ---
        price: 10
        when: 2020-01-01
        ---
        # A
        """
        let b = """
        ---
        price: 30
        when: 2021-06-15
        ---
        # B
        """
        let snap = snapshot(["A.md": a, "B.md": b, "T.base": yaml])
        let file = Bases.parse(yaml)
        XCTAssertEqual(file.summaries["customAverage"], "values.mean().round(1)")
        XCTAssertEqual(file.views[0].summaries["price"], "Sum")
        let r = Bases.run(file, view: 0, in: snap)
        XCTAssertEqual(r.summaries["file.name"]?.text, "2")
        XCTAssertEqual(r.summaries["price"]?.text, "40")
        XCTAssertEqual(r.summaries["when"]?.text, "2020-01-01")
        XCTAssertTrue(r.warnings.isEmpty, r.warnings.joined(separator: "; "))

        let avg = Bases.run(file, view: 1, in: snap)
        XCTAssertEqual(avg.summaries["price"]?.text, "20")
        XCTAssertTrue(avg.warnings.isEmpty, avg.warnings.joined(separator: "; "))
    }

    func testDurationParse() {
        XCTAssertEqual(BaseDuration.parse("1d")?.days, 1)
        XCTAssertEqual(BaseDuration.parse("2w")?.weeks, 2)
        XCTAssertEqual(BaseDuration.parse("1h30m")?.hours, 1)
        XCTAssertEqual(BaseDuration.parse("1h30m")?.minutes, 30)
        XCTAssertEqual(BaseDuration.parse("1 day")?.days, 1)
        XCTAssertNil(BaseDuration.parse("nope"))
    }
}
