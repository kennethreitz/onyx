import XCTest
@testable import OnyxCore

final class OutlineTreeTests: XCTestCase {
    func snapshot(_ files: [String: String]) -> VaultSnapshot {
        var snap = VaultSnapshot(root: URL(fileURLWithPath: "/tmp/outline-tree-test"))
        for (p, c) in files { snap.notes[p] = VaultSnapshot.makeRecord(rel: p, content: c) }
        snap.rebuildDerived()
        return snap
    }

    func headings(_ text: String) -> [Heading] { NoteParser.parseHeadings(text) }

    func testNestHeadingsSkipsLevelsAndAllowsLaterShallowerRoots() {
        let hs = headings("# A\n#### Deep\n## B\n# C\n### D\n")
        let tree = OutlineTree.nestHeadings(hs, path: "X.md")
        XCTAssertEqual(tree.map(\.title), ["A", "C"])
        XCTAssertEqual(tree[0].children.map(\.title), ["Deep", "B"])
        XCTAssertEqual(tree[0].children[0].headingLevel, 4)
        XCTAssertTrue(tree[0].children[0].children.isEmpty)
        XCTAssertTrue(tree[0].children[1].children.isEmpty)
        XCTAssertEqual(tree[1].children.map(\.title), ["D"])
        XCTAssertEqual(tree[0].headingIndex, 0)
        XCTAssertEqual(tree[0].headingLine, 0)
        XCTAssertEqual(tree[1].headingLine, 3)
    }

    func testHeadingAtLineIsTheOpenSection() {
        let hs = headings("# A\npara\n## B\nmore\n# C\n")
        XCTAssertNil(OutlineTree.headingIndex(at: -1, in: hs))
        // before any heading (empty prefix) — first heading is line 0 here
        XCTAssertEqual(OutlineTree.headingIndex(at: 0, in: hs), 0)
        XCTAssertEqual(OutlineTree.headingIndex(at: 1.9, in: hs), 0)
        XCTAssertEqual(OutlineTree.headingIndex(at: 2, in: hs), 1)
        XCTAssertEqual(OutlineTree.headingIndex(at: 4.2, in: hs), 2)
        XCTAssertEqual(OutlineTree.activeId(path: "X.md", line: 0, headings: hs), OutlineTree.noteId("X.md"))
        let id = OutlineTree.activeId(path: "X.md", line: 2, headings: hs)
        XCTAssertEqual(id, OutlineTree.headingId("X.md", index: 1, line: 2))
    }

    func testThisNoteUsesLiveTextNotTheSnapshot() {
        let snap = snapshot(["A.md": "# Old\n## Nested\n"])
        let live = "# New\n## Live\n### Deep\n"
        let roots = OutlineTree.build(scope: .note, currentPath: "A.md", currentText: live, snapshot: snap)
        XCTAssertEqual(roots.map(\.title), ["New"])
        XCTAssertEqual(roots[0].kind, .note)
        XCTAssertEqual(roots[0].children.map(\.title), ["Live"])
        XCTAssertEqual(roots[0].children[0].children.map(\.title), ["Deep"])
        // the leading H1 is the title row, not also a child
        XCTAssertFalse(roots[0].children.contains { $0.title == "New" })
    }

    func testFolderScopeIsTheNotesFolderWithSubfolders() {
        let snap = snapshot([
            "Knowledge/Astrology/Sun.md": "# Sun\n## Rise\n",
            "Knowledge/Astrology/Moon.md": "# Moon\n",
            "Knowledge/Astrology/Charts/Natal.md": "# Natal\n",
            "Projects/Ship.md": "# Ship\n",
            "Root.md": "# Root\n",
        ])
        let roots = OutlineTree.build(scope: .folder, currentPath: "Knowledge/Astrology/Sun.md", snapshot: snap)
        XCTAssertEqual(roots.map(\.title), ["Astrology"])
        XCTAssertEqual(roots[0].kind, .folder)
        let names = roots[0].children.map(\.title)
        XCTAssertEqual(names, ["Charts", "Moon", "Sun"])
        XCTAssertEqual(roots[0].children[0].kind, .folder)
        XCTAssertEqual(roots[0].children[0].children.map(\.title), ["Natal"])
        // sibling folders of Astrology are not included
        XCTAssertFalse(flattenTitles(roots, expandAll: true).contains("Ship"))
        XCTAssertFalse(flattenTitles(roots, expandAll: true).contains("Root"))
    }

    func testFolderScopeAtVaultRootUsesTopLevelChildren() {
        let snap = snapshot([
            "Root.md": "# Root\n",
            "Knowledge/Sun.md": "# Sun\n",
        ])
        let roots = OutlineTree.build(scope: .folder, currentPath: "Root.md", snapshot: snap)
        XCTAssertEqual(Set(roots.map(\.title)), ["Knowledge", "Root"])
    }

    func testNeighborsIncludeParentsPartsAndLinksNotTheWholeVault() {
        let snap = snapshot([
            "Parent.md": "# Parent\n## P\n",
            "Current.md": "# Current\n## C\n[[Friend]]\npartOf:: [[Parent]]\n",
            "Child.md": "# Child\npartOf:: [[Current]]\n",
            "Grand.md": "# Grand\npartOf:: [[Child]]\n",
            "Friend.md": "# Friend\n",
            "Back.md": "see [[Current]]\n",
            "Stranger.md": "# Stranger\n",
        ])
        let roots = OutlineTree.build(scope: .neighbors, currentPath: "Current.md", snapshot: snap)
        let titles = flattenTitles(roots, expandAll: true)
        XCTAssertTrue(titles.contains("Parent"))
        XCTAssertTrue(titles.contains("Current"))
        XCTAssertTrue(titles.contains("Child"))
        XCTAssertTrue(titles.contains("Grand"))
        XCTAssertTrue(titles.contains("Friend"))
        XCTAssertTrue(titles.contains("Back"))
        XCTAssertFalse(titles.contains("Stranger"))
        // partOf is structure: Current is nested under Parent, Child under Current
        XCTAssertEqual(roots.map(\.title), ["Parent", "Friend", "Back"])
        let current = roots[0].children.first { $0.title == "Current" }
        XCTAssertNotNil(current)
        XCTAssertEqual(current?.children.map(\.title), ["Child"])
        XCTAssertEqual(current?.children[0].children.map(\.title), ["Grand"])
    }

    func testVaultFollowsTheFolderTreeAndHidesFolderNotesAsTheFolder() {
        let snap = snapshot([
            "Knowledge/Knowledge.md": "# Knowledge index\n## Overview\n",
            "Knowledge/Sun.md": "# Sun\n## Rise\n",
            "Projects/Ship.md": "# Ship\n",
        ])
        let roots = OutlineTree.build(scope: .vault, currentPath: "Knowledge/Sun.md", snapshot: snap)
        XCTAssertEqual(roots.map(\.title), ["Knowledge", "Projects"])
        let knowledge = roots[0]
        XCTAssertEqual(knowledge.kind, .folder)
        XCTAssertEqual(knowledge.path, "Knowledge/Knowledge.md")
        XCTAssertTrue(knowledge.loadsHeadings)
        // the index is not also a child file
        XCTAssertEqual(knowledge.children.map(\.title), ["Sun"])
    }

    func testFlattenOnlyWalksExpandedBranchesAndLoadsHeadingsLazily() {
        let snap = snapshot([
            "A/One.md": "# One\n## A\n### Deep\n",
            "A/Two.md": "# Two\n## B\n",
            "B/Three.md": "# Three\n## C\n",
        ])
        let roots = OutlineTree.build(scope: .vault, currentPath: "A/One.md", snapshot: snap)
        let hs: (String) -> [Heading] = { snap.notes[$0]?.summary.headings ?? [] }
        let collapsed = OutlineTree.flatten(roots, expanded: [], headings: hs)
        XCTAssertEqual(collapsed.map(\.title), ["A", "B"])
        XCTAssertTrue(collapsed.allSatisfy(\.expandable))
        XCTAssertFalse(collapsed.contains { $0.kind == .heading })

        let folderA = OutlineTree.folderId("A")
        let mid = OutlineTree.flatten(roots, expanded: [folderA], headings: hs)
        XCTAssertEqual(mid.map(\.title), ["A", "One", "Two", "B"])
        XCTAssertFalse(mid.contains { $0.kind == .heading })

        let one = OutlineTree.noteId("A/One.md")
        let open = OutlineTree.flatten(roots, expanded: [folderA, one], headings: hs)
        XCTAssertEqual(open.map(\.title), ["A", "One", "A", "Deep", "Two", "B"])
        XCTAssertEqual(open.filter { $0.kind == .heading }.map(\.title), ["A", "Deep"])
        XCTAssertEqual(open.first { $0.id == one }?.title, "One")  // leading H1 is the note title
        // Two's headings stay unloaded
        XCTAssertFalse(open.contains { $0.title == "B" && $0.kind == .heading })
        let body = OutlineTree.nestBody(of: hs("A/One.md"), path: "A/One.md")
        let folded = OutlineTree.flatten(roots, expanded: [folderA, one], headings: hs,
                                         collapsedHeadings: [body[0].id])
        XCTAssertEqual(folded.filter { $0.kind == .heading }.map(\.title), ["A"])
    }

    func testRevealOpensThePathAndTheNotesHeadingBranches() {
        let snap = snapshot([
            "A/One.md": "# One\n## A\n### Deep\n",
            "A/Two.md": "# Two\n",
        ])
        let roots = OutlineTree.build(scope: .vault, currentPath: "A/One.md", snapshot: snap)
        let hs: (String) -> [Heading] = { snap.notes[$0]?.summary.headings ?? [] }
        let ids = OutlineTree.reveal("A/One.md", in: roots, headings: hs)
        XCTAssertTrue(ids.contains(OutlineTree.folderId("A")))
        XCTAssertTrue(ids.contains(OutlineTree.noteId("A/One.md")))
        XCTAssertFalse(ids.contains(OutlineTree.noteId("A/Two.md")))
        let rows = OutlineTree.flatten(roots, expanded: ids, headings: hs)
        XCTAssertEqual(rows.filter { $0.kind == .heading }.map(\.title), ["A", "Deep"])
        XCTAssertTrue(rows.contains { $0.title == "One" && $0.kind == .note })
    }

    func testThisNoteRevealExpandsEveryHeadingBranch() {
        let hs = headings("# A\n## B\n### C\n# D\n")
        let roots = OutlineTree.nestHeadings(hs, path: "X.md")
        let ids = OutlineTree.reveal("X.md", in: roots, headings: { _ in hs })
        XCTAssertTrue(ids.isEmpty)
        let rows = OutlineTree.flatten(roots, expanded: ids, headings: { _ in [] })
        XCTAssertEqual(rows.map(\.title), ["A", "B", "C", "D"])
        let collapsed = OutlineTree.flatten(roots, expanded: [], headings: { _ in [] },
                                            collapsedHeadings: [roots[0].id])
        XCTAssertEqual(collapsed.map(\.title), ["A", "D"])
    }

    func testWholeVaultFlattenStaysCheapOnALargeVault() {
        var files: [String: String] = [:]
        for f in 0..<40 {
            for n in 0..<50 {
                var body = "# Note \(f)-\(n)\n"
                for h in 0..<8 { body += "## Heading \(h)\ntext\n" }
                files[String(format: "F%02d/N%02d.md", f, n)] = body
            }
        }
        files["F00/N00.md"] = "# Focus\n## A\n### Deep\n"
        let snap = snapshot(files)
        XCTAssertEqual(snap.notes.count, 2000)

        let t0 = CFAbsoluteTimeGetCurrent()
        let roots = OutlineTree.build(scope: .vault, currentPath: "F00/N00.md", snapshot: snap)
        let build = CFAbsoluteTimeGetCurrent() - t0
        XCTAssertEqual(roots.count, 40)
        XCTAssertLessThan(build, 0.2, "vault outline build took \(build)s")

        let hs: (String) -> [Heading] = { snap.notes[$0]?.summary.headings ?? [] }
        let t1 = CFAbsoluteTimeGetCurrent()
        let ids = OutlineTree.reveal("F00/N00.md", in: roots, headings: hs)
        let rows = OutlineTree.flatten(roots, expanded: ids, headings: hs)
        let flat = CFAbsoluteTimeGetCurrent() - t1
        // 40 top-level folders + 50 notes in the open folder + the open note's headings
        XCTAssertLessThan(rows.count, 100)
        XCTAssertEqual(rows.filter { $0.kind == .folder }.count, 40)
        XCTAssertTrue(rows.contains { $0.title == "Focus" && $0.kind == .note })
        XCTAssertTrue(rows.contains { $0.title == "A" && $0.kind == .heading })
        XCTAssertFalse(rows.contains { $0.title == "Focus" && $0.kind == .heading })
        XCTAssertFalse(rows.contains { $0.title.hasPrefix("Note 1-") })
        XCTAssertLessThan(flat, 0.05, "lazy flatten took \(flat)s")
    }


    func testLeadingH1IsTheNoteTitleNotAChild() {
        let snap = snapshot([
            "Planet.md": "# The Sun\n## Rise\n### Dawn\n## Set\n",
            "Notes.md": "## Just a section\n### Nested\n",
        ])
        let vault = OutlineTree.build(scope: .vault, currentPath: "Planet.md", snapshot: snap)
        let planet = vault.first { $0.path == "Planet.md" }
        XCTAssertEqual(planet?.kind, .note)
        XCTAssertEqual(planet?.title, "The Sun")
        let hs: (String) -> [Heading] = { snap.notes[$0]?.summary.headings ?? [] }
        let rows = OutlineTree.flatten(vault, expanded: [OutlineTree.noteId("Planet.md")], headings: hs)
        XCTAssertEqual(rows.filter { $0.path == "Planet.md" }.map { ($0.kind, $0.title) }.map { "\($0.0):\($0.1)" },
                       ["note:The Sun", "heading:Rise", "heading:Dawn", "heading:Set"])

        let notes = vault.first { $0.path == "Notes.md" }
        XCTAssertEqual(notes?.title, "Notes")  // no leading H1: file name
        let rows2 = OutlineTree.flatten(vault, expanded: [OutlineTree.noteId("Notes.md")], headings: hs)
        XCTAssertEqual(rows2.filter { $0.path == "Notes.md" }.map(\.title), ["Notes", "Just a section", "Nested"])
    }

    func testThisNoteLeadingH1IsTheRootTitle() {
        let snap = snapshot(["X.md": "# Title\n## A\n# Other\n## B\n"])
        let roots = OutlineTree.build(scope: .note, currentPath: "X.md", snapshot: snap)
        XCTAssertEqual(roots.map(\.title), ["Title"])
        XCTAssertEqual(roots[0].kind, .note)
        XCTAssertEqual(roots[0].children.map(\.title), ["A", "Other"])
        XCTAssertEqual(roots[0].children[1].children.map(\.title), ["B"])
        XCTAssertEqual(OutlineTree.activeId(path: "X.md", line: 0, headings: NoteParser.parseHeadings(snap.notes["X.md"]!.content)),
                       OutlineTree.noteId("X.md"))
        let noH1 = snapshot(["Y.md": "## A\n## B\n"])
        let roots2 = OutlineTree.build(scope: .note, currentPath: "Y.md", snapshot: noH1)
        XCTAssertEqual(roots2[0].title, "Y")
        XCTAssertEqual(roots2[0].children.map(\.title), ["A", "B"])
    }

    func testFolderNoteLeadingH1IsNotRepeatedUnderTheFolder() {
        let snap = snapshot([
            "Knowledge/Knowledge.md": "# Knowledge index\n## Overview\n",
            "Knowledge/Sun.md": "# Sun\n## Rise\n",
        ])
        let roots = OutlineTree.build(scope: .vault, currentPath: "Knowledge/Sun.md", snapshot: snap)
        let knowledge = roots[0]
        XCTAssertEqual(knowledge.title, "Knowledge")  // folder name stays
        let hs: (String) -> [Heading] = { snap.notes[$0]?.summary.headings ?? [] }
        let rows = OutlineTree.flatten(roots, expanded: [OutlineTree.folderId("Knowledge")], headings: hs)
        XCTAssertFalse(rows.contains { $0.title == "Knowledge index" })
        XCTAssertTrue(rows.contains { $0.title == "Overview" && $0.kind == .heading })
    }

    func testFollowCollapsesOffPathSiblingsAndKeepsTopLevelVisible() {
        let snap = snapshot(["X.md": "# Title\n## A\n### A1\n#### Deep\n## B\n### B1\n"])
        let roots = OutlineTree.build(scope: .note, currentPath: "X.md", snapshot: snap)
        let hs: (String) -> [Heading] = { _ in NoteParser.parseHeadings(snap.notes["X.md"]!.content) }
        let a = roots[0].children.first { $0.title == "A" }!
        let a1 = a.children.first { $0.title == "A1" }!
        let b = roots[0].children.first { $0.title == "B" }!
        let followed = OutlineTree.follow(
            activeId: a1.id, roots: roots, headings: hs,
            expanded: [roots[0].id], heldOpen: [], entered: []
        )
        XCTAssertTrue(followed.expand.contains(roots[0].id))
        XCTAssertFalse(followed.collapse.contains(a.id))
        XCTAssertFalse(followed.collapse.contains(a1.id))
        XCTAssertTrue(followed.collapse.contains(b.id))
        let rows = OutlineTree.flatten(roots, expanded: followed.expand, headings: hs, collapsedHeadings: followed.collapse)
        XCTAssertEqual(rows.map(\.title), ["Title", "A", "A1", "Deep", "B"])
        XCTAssertFalse(rows.contains { $0.title == "B1" })
    }

    func testFollowRespectsHeldOpenUntilPathLeavesTheRoot() {
        let snap = snapshot(["X.md": "# Title\n## A\n### A1\n## B\n### B1\n# Other\n## C\n"])
        let roots = OutlineTree.build(scope: .note, currentPath: "X.md", snapshot: snap)
        let hs: (String) -> [Heading] = { _ in NoteParser.parseHeadings(snap.notes["X.md"]!.content) }
        let a1 = roots[0].children.first { $0.title == "A" }!.children[0]
        let b = roots[0].children.first { $0.title == "B" }!
        let other = roots[0].children.first { $0.title == "Other" }!
        // Manually expand B while reading A1: it stays open
        var followed = OutlineTree.follow(
            activeId: a1.id, roots: roots, headings: hs,
            expanded: [roots[0].id], heldOpen: [b.id], entered: []
        )
        XCTAssertTrue(followed.heldOpen.contains(b.id))
        XCTAssertFalse(followed.collapse.contains(b.id))
        let open = OutlineTree.flatten(roots, expanded: followed.expand, headings: hs, collapsedHeadings: followed.collapse)
        XCTAssertTrue(open.contains { $0.title == "B1" })
        // Moving to a different top-level heading (Other) releases the hold on B
        let c = other.children[0]
        followed = OutlineTree.follow(
            activeId: c.id, roots: roots, headings: hs,
            expanded: followed.expand, heldOpen: followed.heldOpen, entered: followed.entered
        )
        XCTAssertFalse(followed.heldOpen.contains(b.id))
        XCTAssertTrue(followed.collapse.contains(b.id))
    }

    func testFollowKeepsFilterMatchesOpen() {
        let snap = snapshot(["X.md": "# Title\n## A\n### A1\n## B\n### B1\n"])
        let roots = OutlineTree.build(scope: .note, currentPath: "X.md", snapshot: snap)
        let hs: (String) -> [Heading] = { _ in NoteParser.parseHeadings(snap.notes["X.md"]!.content) }
        let a1 = roots[0].children.first { $0.title == "A" }!.children[0]
        let b = roots[0].children.first { $0.title == "B" }!
        let followed = OutlineTree.follow(
            activeId: a1.id, roots: roots, headings: hs,
            expanded: [roots[0].id], heldOpen: [], entered: [], keepOpen: [b.id]
        )
        XCTAssertFalse(followed.collapse.contains(b.id))
        let rows = OutlineTree.flatten(roots, expanded: followed.expand, headings: hs, collapsedHeadings: followed.collapse)
        XCTAssertTrue(rows.contains { $0.title == "B1" })
    }

    func testFollowDoesNotLoadOffPathVaultHeadings() {
        var files: [String: String] = ["F00/N00.md": "# Focus\n## A\n### Deep\n"]
        for i in 1..<20 { files[String(format: "F00/N%02d.md", i)] = "# Note \(i)\n## Hidden\n" }
        let snap = snapshot(files)
        let roots = OutlineTree.build(scope: .vault, currentPath: "F00/N00.md", snapshot: snap)
        let hs: (String) -> [Heading] = { snap.notes[$0]?.summary.headings ?? [] }
        let ids = OutlineTree.reveal("F00/N00.md", in: roots, headings: hs)
        let a = OutlineTree.nestBody(of: hs("F00/N00.md"), path: "F00/N00.md")[0]
        let followed = OutlineTree.follow(
            activeId: a.id, roots: roots, headings: hs,
            expanded: ids, heldOpen: [], entered: []
        )
        let rows = OutlineTree.flatten(roots, expanded: followed.expand, headings: hs, collapsedHeadings: followed.collapse)
        XCTAssertTrue(rows.contains { $0.title == "A" })
        XCTAssertFalse(rows.contains { $0.title == "Hidden" })
    }

    private func flattenTitles(_ roots: [OutlineNode], expandAll: Bool) -> [String] {
        func allIds(_ nodes: [OutlineNode]) -> Set<String> {
            var s: Set<String> = []
            func walk(_ n: OutlineNode) {
                s.insert(n.id)
                for c in n.children { walk(c) }
            }
            nodes.forEach(walk)
            return s
        }
        let hs: (String) -> [Heading] = { _ in [] }
        // when expandAll, also load deferred headings from the node path via empty default —
        // callers that need headings should pass a snapshot-backed tree already expanded with flatten.
        let expanded = allIds(roots)
        // include every node we visit by iterating until stable, loading structural children only
        let rows = OutlineTree.flatten(roots, expanded: expandAll ? expanded : [], headings: hs)
        if expandAll {
            // include children present on the built tree (neighbors / folder structure)
            return Self.titlesDeep(roots)
        }
        return rows.map(\.title)
    }

    private static func titlesDeep(_ nodes: [OutlineNode]) -> [String] {
        var out: [String] = []
        func walk(_ n: OutlineNode) {
            out.append(n.title)
            for c in n.children { walk(c) }
        }
        nodes.forEach(walk)
        return out
    }

    /// Scroll-spy reports a source line; the highlighted row must be the last heading
    /// whose line is at or above that position, using the same ids as the tree (so a
    /// leading H1 used as the title does not shift body heading indices). Selecting a
    /// row is a pure lookup — it does not scroll the document.
    func testScrollSpyHighlightsTheHeadingAtTheLandingLineAcrossALongNote() {
        var parts: [String] = ["# Home", "", "Intro under the title.", ""]
        let names = ["The Proprietor", "Morning", "Afternoon", "Evening",
                     "The Garden", "The Library", "Guests", "Coda"]
        for (i, name) in names.enumerated() {
            parts.append(i == 5 ? "# \(name)" : "## \(name)")
            parts.append("")
            for p in 1...8 { parts.append("Paragraph \(p) under \(name).") }
            parts.append("")
        }
        parts.append("Closing lines after the last heading.")
        let text = parts.joined(separator: "\n")
        let hs = NoteParser.parseHeadings(text)
        XCTAssertEqual(hs.first?.text, "Home")
        XCTAssertEqual(hs.first?.level, 1)
        XCTAssertEqual(hs.count, 1 + names.count)

        let snap = snapshot(["Home.md": text])
        let roots = OutlineTree.build(scope: .note, currentPath: "Home.md", currentText: text, snapshot: snap)
        let rows = OutlineTree.flatten(roots, expanded: [roots[0].id], headings: { _ in hs })
        let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })

        // Body rows are numbered in the full heading list, not from zero after dropping the H1.
        XCTAssertEqual(rows[0].id, OutlineTree.noteId("Home.md"))
        XCTAssertEqual(rows[0].headingIndex, 0)
        let proprietor = rows.first { $0.title == "The Proprietor" }!
        XCTAssertEqual(proprietor.headingIndex, 1)
        XCTAssertEqual(proprietor.id, OutlineTree.headingId("Home.md", index: 1, line: proprietor.headingLine!))
        let library = rows.first { $0.title == "The Library" }!  // later H1, still a child of the title
        XCTAssertEqual(library.headingIndex, 6)
        for row in rows where row.kind == .heading {
            let i = hs.firstIndex { $0.line == row.headingLine }
            XCTAssertEqual(row.headingIndex, i)
            XCTAssertEqual(row.id, OutlineTree.headingId("Home.md", index: i!, line: row.headingLine!))
        }

        let lastLine = (hs.last?.line ?? 0) + 4
        var seen: [String] = []
        for line in 0...lastLine {
            let id = OutlineTree.activeId(path: "Home.md", line: Double(line), headings: hs)
            XCTAssertNotNil(id, "line \(line)")
            XCTAssertNotNil(byId[id!], "line \(line) highlighted \(id!) which is not a visible outline row")
            if let i = OutlineTree.headingIndex(at: Double(line), in: hs) {
                let expected = (i == 0 && hs[0].level == 1)
                    ? OutlineTree.noteId("Home.md")
                    : OutlineTree.headingId("Home.md", index: i, line: hs[i].line)
                XCTAssertEqual(id, expected, "line \(line)")
            } else {
                XCTAssertEqual(id, OutlineTree.noteId("Home.md"))
            }
            if seen.last != id { seen.append(id!) }
        }
        // Walking the file should light up the title, then each heading in order, never a neighbour by mistake.
        XCTAssertEqual(seen.first, OutlineTree.noteId("Home.md"))
        XCTAssertEqual(seen.dropFirst().map { byId[$0]!.title }, names)

        // Same mapping in a wider scope (the other outline tab shares this model).
        let vault = OutlineTree.build(scope: .vault, currentPath: "Home.md", currentText: text, snapshot: snap)
        let noteId = OutlineTree.noteId("Home.md")
        let vaultRows = OutlineTree.flatten(vault, expanded: [noteId], headings: { _ in hs })
        let atGarden = Double(rows.first { $0.title == "The Garden" }!.headingLine!)
        let active = OutlineTree.activeId(path: "Home.md", line: atGarden + 1, headings: hs)
        XCTAssertEqual(active, vaultRows.first { $0.title == "The Garden" }?.id)
        XCTAssertEqual(active, rows.first { $0.title == "The Garden" }?.id)

        // No leading H1: the first heading keeps index 0 and is a child of the file-name row.
        let noH1 = "## Alpha\ntext\n## Beta\nmore\n"
        let hs2 = NoteParser.parseHeadings(noH1)
        let snap2 = snapshot(["Y.md": noH1])
        let roots2 = OutlineTree.build(scope: .note, currentPath: "Y.md", currentText: noH1, snapshot: snap2)
        XCTAssertEqual(roots2[0].children[0].headingIndex, 0)
        XCTAssertEqual(OutlineTree.activeId(path: "Y.md", line: 0, headings: hs2),
                       OutlineTree.headingId("Y.md", index: 0, line: 0))
        XCTAssertEqual(OutlineTree.activeId(path: "Y.md", line: 2, headings: hs2),
                       roots2[0].children[1].id)
    }
}
