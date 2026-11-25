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
        let id = OutlineTree.activeId(path: "X.md", line: 2, headings: hs)
        XCTAssertEqual(id, OutlineTree.headingId("X.md", index: 1, line: 2))
    }

    func testThisNoteUsesLiveTextNotTheSnapshot() {
        let snap = snapshot(["A.md": "# Old\n## Nested\n"])
        let live = "# New\n## Live\n### Deep\n"
        let roots = OutlineTree.build(scope: .note, currentPath: "A.md", currentText: live, snapshot: snap)
        XCTAssertEqual(roots.map(\.title), ["New"])
        XCTAssertEqual(roots[0].children.map(\.title), ["Live"])
        XCTAssertEqual(roots[0].children[0].children.map(\.title), ["Deep"])
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
        XCTAssertEqual(open.map(\.title), ["A", "One", "One", "A", "Deep", "Two", "B"])
        XCTAssertEqual(open.filter { $0.kind == .heading }.map(\.title), ["One", "A", "Deep"])
        // Two's headings stay unloaded
        XCTAssertFalse(open.contains { $0.title == "B" && $0.kind == .heading })
        let oneH = OutlineTree.nestHeadings(hs("A/One.md"), path: "A/One.md")
        let folded = OutlineTree.flatten(roots, expanded: [folderA, one], headings: hs,
                                         collapsedHeadings: [oneH[0].id])
        XCTAssertEqual(folded.filter { $0.kind == .heading }.map(\.title), ["One"])
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
        XCTAssertEqual(rows.filter { $0.kind == .heading }.map(\.title), ["One", "A", "Deep"])
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
        XCTAssertTrue(rows.contains { $0.title == "Focus" && $0.kind == .heading })
        XCTAssertFalse(rows.contains { $0.title.hasPrefix("Note 1-") })
        XCTAssertLessThan(flat, 0.05, "lazy flatten took \(flat)s")
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
}
