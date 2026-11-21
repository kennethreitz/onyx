import XCTest
@testable import OnyxCore

final class BasesTests: XCTestCase {
    func snapshot(_ files: [String: String], attachments: [String: String] = [:]) -> VaultSnapshot {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("onyx-bases-\(UUID().uuidString)")
        for (p, c) in files.merging(attachments, uniquingKeysWith: { _, n in n }) {
            let url = dir.appendingPathComponent(p)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? c.write(to: url, atomically: true, encoding: .utf8)
        }
        return VaultSnapshot.scan(root: dir)
    }

    func note(_ name: String, folder: String, props: [String: String], body: String = "", tags: String? = nil) -> (String, String) {
        let path = folder.isEmpty ? "\(name).md" : "\(folder)/\(name).md"
        var fm = props.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\n")
        if let tags { fm += "\ntags: [\(tags)]" }
        return (path, "---\n\(fm)\n---\n# \(name)\n\(body)")
    }

    func libs() -> (VaultSnapshot, String) {
        let yaml = """
        name: Python Libraries
        query: {}
        filters:
          and:
            - file.folder == "Library/Python Libraries"
            - '!file.name.endsWith("base")'
            - '!file.name.endsWith(".canvas")'
        views:
          - type: table
            name: All Libraries
            sort: []
            columns:
              - property: note.name
                name: Library
              - property: year
                name: Year
              - property: domain
                name: Domain
              - property: philosophy
                name: Philosophy
              - property: status
                name: Status
              - property: maintainer
                name: Maintained By
            filter:
              property: type
              operator: eq
              value: library
          - type: list
            name: View
            order:
              - file.name
              - downloads
        """
        let files = [
            note("Arbor", folder: "Library/Python Libraries", props: ["type": "library", "year": "2011", "domain": "HTTP", "philosophy": "for humans", "status": "active", "maintainer": "Ada", "downloads": "1000"]),
            note("Quill", folder: "Library/Python Libraries", props: ["type": "library", "year": "2018", "domain": "CLI", "philosophy": "simple", "status": "active", "maintainer": "Bea"]),
            note("Readme", folder: "Library/Python Libraries", props: ["type": "page"]),
            note("Other", folder: "Library/Other", props: ["type": "library", "year": "1999"]),
        ]
        var dict = Dictionary(uniqueKeysWithValues: files)
        dict["Library/Python Libraries/Libraries.base"] = yaml
        dict["Library/Python Libraries/Sketch.canvas"] = "{\"nodes\":[],\"edges\":[]}"
        let snap = snapshot(dict)
        return (snap, yaml)
    }

    func testParsesOfficialExample() {
        let yaml = """
        filters:
          or:
            - file.hasTag("tag")
            - and:
              - file.hasTag("book")
              - file.hasLink("Textbook")
              - not:
                - file.hasTag("book")
                - file.inFolder("Required Reading")
        formulas:
          formatted_price: 'if(price, price.toFixed(2) + " dollars")'
          ppu: "(price / age).toFixed(2)"
        properties:
          status:
            displayName: Status
          formula.formatted_price:
            displayName: "Price"
          file.ext:
            displayName: Extension
        views:
          - type: table
            name: "My table"
            limit: 10
            groupBy:
              property: note.age
              direction: DESC
            filters:
              and:
                - 'status != "done"'
                - or:
                  - "formula.ppu > 5"
                  - "price > 2.1"
            order:
              - file.name
              - file.ext
              - note.age
              - formula.ppu
              - formula.formatted_price
        """
        let f = Bases.parse(yaml)
        XCTAssertEqual(f.formulas["ppu"], "(price / age).toFixed(2)")
        XCTAssertEqual(f.properties["formula.formatted_price"]?.displayName, "Price")
        XCTAssertEqual(f.views.count, 1)
        XCTAssertEqual(f.views[0].name, "My table")
        XCTAssertEqual(f.views[0].limit, 10)
        XCTAssertEqual(f.views[0].groupBy?.property, "note.age")
        XCTAssertEqual(f.views[0].groupBy?.ascending, false)
        XCTAssertEqual(f.views[0].order, ["file.name", "file.ext", "note.age", "formula.ppu", "formula.formatted_price"])
        if case .or(let xs) = f.filters { XCTAssertEqual(xs.count, 2) } else { XCTFail("expected or filter") }
        XCTAssertTrue(f.warnings.isEmpty, f.warnings.joined(separator: "; "))
    }

    func testParsesLegacyColumnsAndFilter() {
        let (_, yaml) = libs()
        let f = Bases.parse(yaml)
        XCTAssertEqual(f.name, "Python Libraries")
        XCTAssertEqual(f.views[0].type, "table")
        XCTAssertEqual(f.views[0].order.first, "note.name")
        XCTAssertEqual(f.properties["note.name"]?.displayName, "Library")
        XCTAssertEqual(f.properties["maintainer"]?.displayName, "Maintained By")
        XCTAssertTrue(f.warnings.isEmpty, f.warnings.joined(separator: "; "))
    }

    func testLibraryFiltersAndLegacyViewFilter() {
        let (snap, yaml) = libs()
        XCTAssertNotNil(snap.bases["Library/Python Libraries/Libraries.base"])
        XCTAssertTrue(QuickIndex(snap).search("libraries").contains { $0.entry.path.hasSuffix("Libraries.base") })
        let f = Bases.parse(yaml)
        let r = Bases.run(f, view: 0, in: snap)
        XCTAssertEqual(Set(r.rows.map(\.name)), ["Arbor", "Quill"])
        XCTAssertFalse(r.rows.contains { $0.name == "Readme" })          // type != library
        XCTAssertFalse(r.rows.contains { $0.name == "Other" })           // other folder
        XCTAssertFalse(r.rows.contains { $0.path.hasSuffix(".base") })
        XCTAssertFalse(r.rows.contains { $0.path.hasSuffix(".canvas") })
        XCTAssertEqual(r.columns.map(\.displayName), ["Library", "Year", "Domain", "Philosophy", "Status", "Maintained By"])
        XCTAssertEqual(r.rows.first { $0.name == "Arbor" }?.cells["year"]?.text, "2011")
        XCTAssertTrue(r.warnings.isEmpty, r.warnings.joined(separator: "; "))
    }

    func testFolderStartsWithInFolderAndNameCompare() {
        let yaml = """
        filters:
          and:
            - file.folder.startsWith("Docs/History")
        views:
          - type: table
            name: Table
            order:
              - file.name
            sort:
              - property: file.name
                direction: ASC
          - type: list
            name: View
        """
        let files = [
            note("Letter", folder: "Docs/History", props: ["type": "doc"]),
            note("Annex", folder: "Docs/History/Annexes", props: ["type": "doc"]),
            note("History", folder: "Docs", props: [:]),          // folder note, folder is Docs
            note("Elsewhere", folder: "Docs/Other", props: [:]),
        ]
        var dict = Dictionary(uniqueKeysWithValues: files)
        dict["Docs/History/History.base"] = yaml
        let snap = snapshot(dict)
        let f = Bases.parse(yaml)
        let r = Bases.run(f, view: 0, in: snap)
        XCTAssertEqual(r.rows.map(\.name), ["Annex", "History", "Letter"]) // History.base included? name "History", folder Docs/History, startsWith yes — AND the .base file itself
        // The .base is in Docs/History, so it matches startsWith. That's official default (every file).
        XCTAssertTrue(r.rows.contains { $0.path.hasSuffix("History.base") })
        XCTAssertFalse(r.rows.contains { $0.name == "Elsewhere" })
        XCTAssertFalse(r.rows.contains { $0.path == "Docs/History.md" })

        let games = """
        filters:
          and:
            - file.folder == "Library/Games"
            - '!file.name.endsWith("base")'
            - file.name != "Games"
        views:
          - type: table
            name: Table
            filters:
              and:
                - file.folder == "Library/Games"
            order:
              - file.name
            sort:
              - property: file.name
                direction: ASC
        """
        let gfiles = [
            note("Games", folder: "Library/Games", props: [:]),
            note("Lantern", folder: "Library/Games", props: ["platform": "Mac", "genre": "puzzle", "status": "done"]),
            note("Meadow", folder: "Library/Games", props: ["platform": "Mac", "genre": "sim", "status": "playing"]),
        ]
        var gdict = Dictionary(uniqueKeysWithValues: gfiles)
        gdict["Library/Games/Video Games.base"] = games
        let gsnap = snapshot(gdict)
        let gr = Bases.run(Bases.parse(games), view: 0, in: gsnap)
        XCTAssertEqual(gr.rows.map(\.name), ["Lantern", "Meadow"])
        XCTAssertTrue(gr.warnings.isEmpty, gr.warnings.joined(separator: "; "))
    }

    func testInFolderContainsAnyAndCardsCover() {
        let yaml = """
        filters:
          and:
            - file.inFolder("Knowledge/AI/Entities")
            - '!file.name.containsAny(".base", "Skip")'
        views:
          - type: table
            name: Registry
            sort:
              - property: file.name
                direction: ASC
            columns:
              - property: note.name
                name: Entity
              - property: essence
                name: Essence
            filter:
              property: type
              operator: eq
              value: ai-entity
          - type: cards
            name: View
            cardSize: 230
            cover: image
        """
        let files = [
            note("Nova", folder: "Knowledge/AI/Entities", props: ["type": "ai-entity", "essence": "light", "image": "covers/nova.png"]),
            note("Skip Me", folder: "Knowledge/AI/Entities", props: ["type": "ai-entity", "essence": "void"]),
            note("Nested", folder: "Knowledge/AI/Entities/Sub", props: ["type": "ai-entity", "essence": "deep"]),
            note("Other", folder: "Knowledge/AI", props: ["type": "ai-entity"]),
        ]
        var dict = Dictionary(uniqueKeysWithValues: files)
        dict["Knowledge/AI/Entities/Entities.base"] = yaml
        dict["covers/nova.png"] = "not-a-real-png"
        let snap = snapshot(dict)
        let f = Bases.parse(yaml)
        let table = Bases.run(f, view: 0, in: snap)
        XCTAssertEqual(table.rows.map(\.name), ["Nested", "Nova"])
        XCTAssertFalse(table.rows.contains { $0.name == "Skip Me" })
        XCTAssertFalse(table.rows.contains { $0.name.contains("Entities") && $0.path.hasSuffix(".base") })
        let cards = Bases.run(f, view: 1, in: snap)
        XCTAssertEqual(cards.view.type, "cards")
        XCTAssertEqual(cards.view.cardSize, 230)
        XCTAssertEqual(cards.rows.first { $0.name == "Nova" }?.coverPath, "covers/nova.png")
    }

    func testHasTagHasLinkFormulasSortLimitGroup() throws {
        let yaml = """
        filters:
          and:
            - file.hasTag("book")
        formulas:
          formatted_price: 'if(price, price.toFixed(2) + " dollars")'
          ppu: "(price / age).toFixed(2)"
        views:
          - type: table
            name: My table
            limit: 2
            groupBy:
              property: age
              direction: DESC
            filters:
              and:
                - 'status != "done"'
                - or:
                  - "formula.ppu > 5"
                  - "price > 2.1"
            order:
              - file.name
              - formula.ppu
              - formula.formatted_price
            sort:
              - property: formula.ppu
                direction: DESC
        """
        let files = [
            note("Alpha", folder: "Shelf", props: ["price": "12", "age": "2", "status": "open"], tags: "book"),
            note("Beta", folder: "Shelf", props: ["price": "3", "age": "1", "status": "open"], body: "See [[Textbook]]", tags: "book"),
            note("Done", folder: "Shelf", props: ["price": "99", "age": "1", "status": "done"], tags: "book"),
            note("Cheap", folder: "Shelf", props: ["price": "1", "age": "10", "status": "open"], tags: "book"),
            note("Untagged", folder: "Shelf", props: ["price": "50", "age": "1", "status": "open"]),
        ]
        let snap = snapshot(Dictionary(uniqueKeysWithValues: files))
        let r = Bases.run(Bases.parse(yaml), view: 0, in: snap)
        // Alpha ppu = 6, Beta ppu = 3 but price 3 > 2.1, Cheap ppu = 0.1 and price 1 — excluded, Done status done — excluded, Untagged no tag.
        XCTAssertEqual(Set(r.rows.map(\.name)), ["Alpha", "Beta"]) // limit 2, sorted by ppu desc: Alpha then Beta
        XCTAssertEqual(r.rows.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(r.total, 2)
        XCTAssertEqual(r.rows[0].cells["formula.formatted_price"]?.text, "12.00 dollars")
        XCTAssertEqual(r.rows[0].cells["formula.ppu"]?.text, "6.00")
        XCTAssertNotNil(r.groups)
        XCTAssertTrue(r.warnings.isEmpty, r.warnings.joined(separator: "; "))

        // hasLink
        let linkYaml = """
        filters: file.hasLink("Textbook")
        views:
          - type: table
            name: T
            order: [file.name]
        """
        let hit = Bases.run(Bases.parse(linkYaml), view: 0, in: snap)
        XCTAssertEqual(hit.rows.map(\.name), ["Beta"])
    }

    func testUnknownExpressionWarnsAndDoesNotCrash() {
        let yaml = """
        filters:
          and:
            - file.folder == "Lab"
            - thisFunctionDoesNotExist(foo.bar)
        views:
          - type: table
            name: Table
            order:
              - file.name
              - formula.missing
        formulas:
          missing: 'mysteryMagic(1)'
        """
        let snap = snapshot(Dictionary(uniqueKeysWithValues: [note("A", folder: "Lab", props: [:])]))
        let f = Bases.parse(yaml)
        let r = Bases.run(f, view: 0, in: snap)
        // The unknown filter is skipped (treated as true), so the Lab note still appears.
        XCTAssertEqual(r.rows.map(\.name), ["A"])
        XCTAssertFalse(r.warnings.isEmpty)
        XCTAssertTrue(r.warnings.contains { $0.lowercased().contains("mystery") || $0.lowercased().contains("unknown") || $0.lowercased().contains("function") })
        XCTAssertEqual(r.rows[0].cells["formula.missing"], .null)
    }

    func testComparisonsBooleansAndDates() {
        let yaml = """
        filters:
          and:
            - file.ext == "md"
            - year >= 2020
            - published == true
        views:
          - type: table
            name: T
            order:
              - file.name
              - file.ext
              - year
            sort:
              - property: year
                direction: ASC
        """
        let files = [
            note("New", folder: "Y", props: ["year": "2024", "published": "true"]),
            note("Old", folder: "Y", props: ["year": "1999", "published": "true"]),
            note("Draft", folder: "Y", props: ["year": "2024", "published": "false"]),
        ]
        let r = Bases.run(Bases.parse(yaml), view: 0, in: snapshot(Dictionary(uniqueKeysWithValues: files)))
        XCTAssertEqual(r.rows.map(\.name), ["New"])
        XCTAssertEqual(r.rows[0].cells["file.ext"]?.text, "md")
    }

    func testEmptyAndMalformedYAML() {
        let empty = Bases.parse("")
        XCTAssertEqual(empty.views.count, 0)
        XCTAssertFalse(empty.warnings.isEmpty)
        let junk = Bases.parse("::::\n- \nfoo")
        XCTAssertNotNil(junk) // parse never throws
        let single = Bases.parse("filters: file.hasTag(\"x\")\nviews:\n  - type: table\n    name: T\n    order: [file.name]\n")
        if case .expression(let s) = single.filters { XCTAssertTrue(s.contains("hasTag")) } else { XCTFail("\(single.filters)") }
    }

    /// Read-only smoke check against a real vault: `ONYX_BASES_VAULT=~/Notes swift test --filter testRealBasesReadOnly`.
    /// Prints view names, row counts, columns and warnings — never writes, and never asserts on note titles.
    func testRealBasesReadOnly() throws {
        guard let root = ProcessInfo.processInfo.environment["ONYX_BASES_VAULT"], !root.isEmpty else {
            throw XCTSkip("set ONYX_BASES_VAULT to a vault to check real .base files (read-only)")
        }
        let snap = VaultSnapshot.scan(root: URL(fileURLWithPath: (root as NSString).expandingTildeInPath))
        let paths = snap.bases.keys.sorted()
        XCTAssertFalse(paths.isEmpty, "no .base files under \(root)")
        for p in paths {
            let file = Bases.parse(snap.bases[p] ?? "")
            print("BASE \(p)")
            print("  name=\(file.name ?? "—") views=\(file.views.count) parseWarnings=\(file.warnings)")
            for (i, v) in file.views.enumerated() {
                let r = Bases.run(file, view: i, in: snap)
                print("  view[\(i)] \(v.type) \"\(v.name)\" rows=\(r.rows.count) total=\(r.total) columns=\(r.columns.map(\.displayName)) cover=\(r.rows.filter { $0.coverPath != nil }.count) warnings=\(r.warnings)")
            }
        }
    }
}
