import XCTest
@testable import OnyxCore

final class TagsTests: XCTestCase {

    // MARK: names

    func testNormalize() {
        XCTAssertEqual(TagName.normalize("#a//b/"), "a/b")
        XCTAssertEqual(TagName.normalize("Projects/Onyx"), "Projects/Onyx")
        XCTAssertNil(TagName.normalize("#2024"))
        XCTAssertEqual(TagName.normalize("y2024"), "y2024")
        XCTAssertNil(TagName.normalize("a b"))
        XCTAssertNil(TagName.normalize("#"))
        XCTAssertEqual(TagName.normalize("café/naïve"), "café/naïve")
        XCTAssertEqual(TagName.normalize("📚"), "📚")
        XCTAssertEqual(TagName.key("#Book/Fiction"), "book/fiction")
    }

    func testMatchesAndMoves() {
        XCTAssertTrue(TagName.matches("Book/Fiction", filter: "book"))
        XCTAssertFalse(TagName.matches("Book/Fiction", filter: "book", exact: true))
        XCTAssertFalse(TagName.matches("bookish", filter: "book"))
        XCTAssertEqual(TagName.moved("a/B/c", from: "A/b", to: "x"), "x/c")
        XCTAssertEqual(TagName.moved("a/b", from: "a/B", to: "x/y"), "x/y")
        XCTAssertNil(TagName.moved("a/bc", from: "a/b", to: "x"))
        XCTAssertEqual(TagName.reparented("a/b", onto: "x"), "x/b")
        XCTAssertEqual(TagName.reparented("a/b", onto: nil), "b")
        XCTAssertEqual(TagName.ancestry("a/b/c"), ["a", "a/b", "a/b/c"])
        XCTAssertNotNil(TagName.renameProblem(from: "a", to: "a b"))
        XCTAssertNotNil(TagName.renameProblem(from: "a", to: "#a"))
        XCTAssertNil(TagName.renameProblem(from: "a", to: "A"))   // a case fix is a rename
    }

    // MARK: scanning

    func testInlineSkipsCodeLinksURLsAndHeadings() {
        let text = """
        # Heading
        ## Sub #real
        Some #topic/sub and #Topic/Other, `#notcode` and [[Note#Heading]] [[#Local]]
        [jump](#anchor) https://example.com/page#frag http://x.io/#/route &#123; #2024 c#sharp
        ```
        #fenced
        ```
        end #last/ (#paren)
        """
        let names = TagScanner.inline(text).map(\.name)
        XCTAssertEqual(names, ["real", "topic/sub", "Topic/Other", "last", "paren"])
    }

    func testFrontmatterForms() {
        let a = "---\ntags: [one, \"two/three\", #four]\n---\nbody #five\n"
        XCTAssertEqual(TagScanner.names(a), ["one", "two/three", "four", "five"])
        let b = "---\ntitle: x\ntags:\n  - alpha/beta\n  - '#gamma'\n# comment\n  - delta\naliases:\n  - notatag\n---\n"
        XCTAssertEqual(TagScanner.names(b), ["alpha/beta", "gamma", "delta"])
        let c = "---\ntag: a, b c # trailing comment\n---\n"
        XCTAssertEqual(TagScanner.names(c), ["a", "b", "c"])
        // ranges point at the name itself
        let occ = TagScanner.frontmatter(a)
        XCTAssertEqual((a as NSString).substring(with: occ[1].range), "two/three")
        XCTAssertEqual((a as NSString).substring(with: occ[2].range), "four")
    }

    func testSummaryDedupesCaseInsensitively() {
        let s = NoteParser.summarize("---\ntags: Book\n---\n#book #BOOK/fiction #book/Fiction\n")
        XCTAssertEqual(s.tags, ["BOOK/fiction", "Book"])
    }

    // MARK: tree

    func sampleTree(_ sort: TagTree.Sort = .name) -> TagTree {
        TagTree(tags: [
            "book": ["a.md"],
            "Book/fiction": ["b.md", "c.md"],
            "book/Fiction/scifi": ["c.md", "d.md"],
            "book/nonfiction": ["e.md"],
            "area/health/sleep": ["f.md"],
            "zebra": ["a.md", "b.md", "c.md", "d.md", "e.md", "f.md", "g.md"],
        ], sort: sort)
    }

    func testTreeCountsAndCaseMerge() {
        let t = sampleTree()
        XCTAssertEqual(t.roots.map(\.name), ["area", "book", "zebra"])
        let book = t.node("BOOK")!
        XCTAssertEqual(book.ownCount, 1)
        XCTAssertEqual(book.totalCount, 5)   // a b c d e, each once
        XCTAssertEqual(book.children.map(\.name), ["fiction", "nonfiction"])
        let fiction = t.node("book/fiction")!
        XCTAssertEqual(fiction.ownCount, 2)
        XCTAssertEqual(fiction.totalCount, 3)
        XCTAssertEqual(fiction.children.first?.path, "book/Fiction/scifi")
        // implicit parents exist with no notes of their own
        XCTAssertEqual(t.node("area/health")?.ownCount, 0)
        XCTAssertEqual(t.node("area/health")?.totalCount, 1)
        XCTAssertEqual(t.notes(for: "#book"), ["a.md", "b.md", "c.md", "d.md", "e.md"])
        XCTAssertEqual(t.notes(for: "book", exact: true), ["a.md"])
        XCTAssertNil(t.node("book/missing"))
    }

    func testSortByCountAndRows() {
        let t = sampleTree(.count)
        XCTAssertEqual(t.roots.map(\.name), ["zebra", "book", "area"])
        XCTAssertEqual(t.rows(expanded: []).map(\.node.key), ["zebra", "book", "area"])
        let rows = t.rows(expanded: ["book", "book/fiction"])
        XCTAssertEqual(rows.map(\.node.key), ["zebra", "book", "book/fiction", "book/fiction/scifi", "book/nonfiction", "area"])
        XCTAssertEqual(rows.map(\.depth), [0, 0, 1, 2, 1, 0])
        XCTAssertEqual(t.subtreeKeys("book"), ["book", "book/fiction"])
    }

    func testFilter() {
        let (f, expand) = sampleTree().filtered("sci")
        XCTAssertEqual(f.roots.map(\.key), ["book"])
        XCTAssertEqual(f.rows(expanded: expand).map(\.node.key), ["book", "book/fiction", "book/fiction/scifi"])
        XCTAssertEqual(sampleTree().filtered("#book fic").tree.roots.first?.children.map(\.key), ["book/fiction", "book/nonfiction"])
        XCTAssertEqual(sampleTree().filtered("").tree.roots.count, 3)
    }

    func testLargeVaultIsFast() {
        var tags: [String: Set<String>] = [:]
        for i in 0..<5000 { tags["t\(i % 50)/s\(i % 400)/leaf\(i)"] = Set((0..<20).map { "n\(($0 * 7 + i) % 20000).md" }) }
        measure { _ = TagTree(tags: tags, sort: .count).rows(expanded: Set((0..<50).map { "t\($0)" })) }
    }

    // MARK: rename

    func testRewriteInlineAndFrontmatter() {
        let text = """
        ---
        tags: [project/onyx, other]
        aliases: [project/onyx]
        ---
        #Project/Onyx/ios work and #project/onyxish stays, `#project/onyx` stays
        - list #project/onyx
        """
        let r = TagRename.rewrite(text, from: "project/onyx", to: "apps/onyx")
        XCTAssertEqual(r.count, 3)
        XCTAssertTrue(r.text.contains("tags: [apps/onyx, other]"))
        XCTAssertTrue(r.text.contains("aliases: [project/onyx]"))
        XCTAssertTrue(r.text.contains("#apps/onyx/ios work"))
        XCTAssertTrue(r.text.contains("#project/onyxish"))
        XCTAssertTrue(r.text.contains("`#project/onyx`"))
        XCTAssertTrue(r.text.contains("- list #apps/onyx"))
        XCTAssertEqual(r.lines.map(\.line), [1, 4, 5])
        XCTAssertEqual(r.renames.map(\.1), ["apps/onyx", "apps/onyx/ios"])
    }

    func testPlanAcrossVaultAndMerge() {
        let texts = ["a.md": "#book/fiction", "b.md": "---\ntags:\n  - book\n---\n", "c.md": "no tags", "d.md": "#bookish"]
        let tree = TagTree(tags: ["book": ["b.md"], "book/fiction": ["a.md"], "reading": ["x.md"]])
        let p = TagRename.plan(texts: texts, from: "book", to: "reading", existing: tree)
        XCTAssertEqual(p.changes.map(\.path), ["a.md", "b.md"])
        XCTAssertEqual(p.changes[0].after, "#reading/fiction")
        XCTAssertEqual(p.changes[1].after, "---\ntags:\n  - reading\n---\n")
        XCTAssertTrue(p.merges)
        XCTAssertEqual(p.occurrences, 2)
        // re-parent: drag book/fiction onto reading
        let q = TagRename.plan(texts: texts, from: "book/fiction", to: TagName.reparented("book/fiction", onto: "reading"))
        XCTAssertEqual(q.changes.map(\.after), ["#reading/fiction"])
        XCTAssertFalse(q.merges)
        // case-only rename
        XCTAssertEqual(TagRename.rewrite("#book", from: "book", to: "Book").text, "#Book")
    }

    // MARK: completion

    func testCompletionContext() {
        XCTAssertEqual(TagCompletion.context(line: "see #pro", caret: 8)?.query, "pro")
        XCTAssertEqual(TagCompletion.context(line: "see #projects/ac", caret: 16)?.query, "projects/ac")
        XCTAssertEqual(TagCompletion.context(line: "see #", caret: 5)?.query, "")
        XCTAssertNil(TagCompletion.context(line: "#", caret: 1))           // a heading in the making
        XCTAssertNotNil(TagCompletion.context(line: "#to", caret: 3))
        XCTAssertNil(TagCompletion.context(line: "# Head", caret: 6))
        XCTAssertNil(TagCompletion.context(line: "c#sharp", caret: 7))
        XCTAssertNil(TagCompletion.context(line: "[[Note#He", caret: 9))
        XCTAssertNil(TagCompletion.context(line: "`code #x", caret: 8))
        XCTAssertNil(TagCompletion.context(line: "https://a.com/#x", caret: 16))
        let c = TagCompletion.context(line: "a #pro/x b", caret: 5)!
        XCTAssertEqual(c.queryStart, 3); XCTAssertEqual(c.replaceEnd, 8)
    }

    func testFrontmatterCompletionContext() {
        let t = "---\ntags:\n  - pro\nother: x\n---\nbody"
        let caret = (t as NSString).range(of: "pro").location + 3
        let fc = TagCompletion.frontmatterContext(text: t, caret: caret)
        XCTAssertEqual(fc?.context.query, "pro")
        XCTAssertNil(TagCompletion.frontmatterContext(text: t, caret: (t as NSString).range(of: "x\n").location + 1))
        let inline = "---\ntags: [a, bo]\n---\n"
        XCTAssertEqual(TagCompletion.frontmatterContext(text: inline, caret: (inline as NSString).range(of: "bo").location + 2)?.context.query, "bo")
    }

    func testSegmentSuggestions() {
        let paths = sampleTree().allPaths
        XCTAssertEqual(TagCompletion.suggestions("bo", paths: paths).map(\.path), ["book"])
        XCTAssertEqual(TagCompletion.suggestions("book/", paths: paths).map(\.path), ["Book/fiction", "book/nonfiction"])
        XCTAssertEqual(TagCompletion.suggestions("book/fiction/", paths: paths).map(\.path), ["book/Fiction/scifi"])
        // a deeper segment matches too, after the top-level ones
        XCTAssertEqual(TagCompletion.suggestions("sle", paths: paths).map(\.path), ["area/health/sleep"])
        let health = TagCompletion.suggestions("area/he", paths: paths)[0]
        XCTAssertEqual(TagCompletion.insertText(health), "area/health/")   // only a parent: keep going
        XCTAssertEqual(TagCompletion.insertText(TagCompletion.suggestions("zeb", paths: paths)[0]), "zebra")
        XCTAssertEqual(TagCompletion.suggestions("book", paths: paths).first?.exact, true)
        XCTAssertEqual(TagCompletion.suggestions("zebra", paths: paths), [])   // nothing to complete
    }
}
