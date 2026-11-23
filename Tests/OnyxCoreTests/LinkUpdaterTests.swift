import XCTest
@testable import OnyxCore

final class LinkUpdaterTests: XCTestCase {
    func vault(_ notes: [String: String], attachments: [String] = [], canvases: [String: String] = [:]) -> VaultSnapshot {
        var snap = VaultSnapshot(root: URL(fileURLWithPath: "/tmp/none"))
        for (p, c) in notes { snap.notes[p] = VaultSnapshot.makeRecord(rel: p, content: c) }
        for a in attachments { snap.attachments[a] = Date() }
        for (p, c) in canvases { snap.attachments[p] = Date(); snap.canvases[p] = CanvasFile.summarize(c) }
        snap.rebuildDerived()
        return snap
    }

    func edits(_ snap: VaultSnapshot, _ from: String, _ to: String, format: String = "shortest",
               canvases: [String: String] = [:]) -> [String: String] {
        let plan = LinkUpdater.plan(snap, from: from, to: to, linkFormat: format) { canvases[$0] }
        return Dictionary(uniqueKeysWithValues: plan.edits.map { ($0.path, $0.text) })
    }

    func testAttachmentRenameKeepsSuffixes() {
        let snap = vault(["A.md": "![[photo.png]] ![[photo.png|300]] [[photo.png|alias]] ![[assets/photo.png|200x100]] ![](assets/photo.png) ![](/assets/photo.png)"],
                         attachments: ["assets/photo.png"])
        let e = edits(snap, "assets/photo.png", "assets/Beach Day.png")
        XCTAssertEqual(e["A.md"], "![[Beach Day.png]] ![[Beach Day.png|300]] [[Beach Day.png|alias]] ![[assets/Beach Day.png|200x100]] ![](assets/Beach%20Day.png) ![](/assets/Beach%20Day.png)")
    }

    func testNoteRenameHeadingsAliasesEmbedsAndCount() {
        let snap = vault(["Old.md": "# Old", "B.md": "[[Old]] [[Old#Part]] [[Old#^blk|see]] ![[Old]] [[old]] [[Old.md]] [x](Old.md#Part)"])
        let plan = LinkUpdater.plan(snap, from: "Old.md", to: "New Name.md") { _ in nil }
        XCTAssertEqual(plan.edits.map(\.path), ["B.md"])
        XCTAssertEqual(plan.edits[0].text, "[[New Name]] [[New Name#Part]] [[New Name#^blk|see]] ![[New Name]] [[New Name]] [[New Name.md]] [x](New%20Name.md#Part)")
        XCTAssertEqual(plan.linkCount, 7)
    }

    func testCodeIsNeverTouched() {
        let t = "[[Old]]\n```\n[[Old]] ![](Old.md)\n```\n`[[Old]]` and `![](Old.md)`"
        let e = edits(vault(["Old.md": "", "B.md": t]), "Old.md", "New.md")
        XCTAssertEqual(e["B.md"], "[[New]]\n```\n[[Old]] ![](Old.md)\n```\n`[[Old]]` and `![](Old.md)`")
    }

    func testFrontmatterAndFieldLinks() {
        let t = "---\npartOf: \"[[Old]]\"\nup:\n  - \"[[Old|O]]\"\n---\nrelated:: [[Old]]"
        let e = edits(vault(["Old.md": "", "B.md": t]), "Old.md", "New.md")
        XCTAssertEqual(e["B.md"], "---\npartOf: \"[[New]]\"\nup:\n  - \"[[New|O]]\"\n---\nrelated:: [[New]]")
    }

    func testShortestBecomesPathWhenNameCollides() {
        // renaming to a name another note already has: the bare link must become a path
        let snap = vault(["Projects/Plan.md": "", "Archive/Idea.md": "", "B.md": "[[Plan]] and [[Plan|p]]"])
        XCTAssertEqual(edits(snap, "Projects/Plan.md", "Projects/Idea.md")["B.md"], "[[Projects/Idea]] and [[Projects/Idea|p]]")
        XCTAssertEqual(edits(snap, "Projects/Plan.md", "Projects/Idea.md", format: "relative")["B.md"], "[[Projects/Idea]] and [[Projects/Idea|p]]")
        let deep = vault(["Projects/Plan.md": "", "Archive/Idea.md": "", "Notes/B.md": "[[Plan]]"])
        XCTAssertEqual(edits(deep, "Projects/Plan.md", "Projects/Idea.md", format: "relative")["Notes/B.md"], "[[../Projects/Idea]]")
        // still unique: stays shortest
        XCTAssertEqual(edits(snap, "Projects/Plan.md", "Projects/Roadmap.md")["B.md"], "[[Roadmap]] and [[Roadmap|p]]")
    }

    func testMoveIntoClashKeepsTargetAndOthersStable() {
        // a second "Moon" moving to the vault root would steal bare [[Moon]] links (root path wins)
        let snap = vault(["Sky/Moon.md": "", "Other/Moon.md": "", "Sky/Sun.md": "[[Moon]]", "Note.md": "[[Other/Moon]]"])
        let e = edits(snap, "Other/Moon.md", "Moon.md")
        XCTAssertEqual(e["Sky/Sun.md"], "[[Sky/Moon]]")
        XCTAssertEqual(e["Note.md"], "[[Moon]]")
    }

    func testPathLinksAndFolderRename() {
        let snap = vault(["Projects/Plan.md": "[[./Sub/Deep]] [img](img/x.png)", "Projects/Sub/Deep.md": "", "B.md": "[[Projects/Plan]] [[/Projects/Sub/Deep|d]] ![[Projects/img/x.png]] [[Plan]] [p](Projects/Plan.md) ![](Projects/img/x.png)"],
                         attachments: ["Projects/img/x.png"])
        let e = edits(snap, "Projects", "Work/2026")
        XCTAssertEqual(e["B.md"], "[[Work/2026/Plan]] [[/Work/2026/Sub/Deep|d]] ![[Work/2026/img/x.png]] [[Plan]] [p](Work/2026/Plan.md) ![](Work/2026/img/x.png)")
        XCTAssertNil(e["Projects/Plan.md"])   // relative links inside the folder still work
    }

    func testMovedNoteRelativeWikilinks() {
        let snap = vault(["Notes/A.md": "[[../Top]] [[./B]]", "Top.md": "", "Notes/B.md": ""])
        XCTAssertEqual(snap.resolve("../Top", from: "Notes/A.md"), "Top.md")
        XCTAssertEqual(edits(snap, "Notes/A.md", "Deep/Er/A.md")["Notes/A.md"], "[[../../Top]] [[../../Notes/B]]")
    }

    func testMovedNoteSameFolderPreference() {
        // [[Moon]] in Sky/Sun.md resolved to its neighbour; once Sun moves away it must say which Moon
        let snap = vault(["Sky/Moon.md": "", "Lab/Moon.md": "", "Sky/Sun.md": "[[Moon]]"])
        XCTAssertEqual(edits(snap, "Sky/Sun.md", "Lab/Sun.md")["Sky/Sun.md"], "[[Sky/Moon]]")
        // unique names don't care where the note goes
        let solo = vault(["Sky/Moon.md": "", "Sky/Sun.md": "[[Moon]]"])
        XCTAssertTrue(edits(solo, "Sky/Sun.md", "Lab/Sun.md").isEmpty)
    }

    func testCanvasFileNodes() {
        let canvas = #"{"nodes":[{"id":"1","type":"file","file":"assets/photo.png","x":0,"y":0,"width":10,"height":10},{"id":"2","type":"file","file":"Old.md","x":0,"y":0,"width":10,"height":10}],"edges":[]}"#
        let snap = vault(["Old.md": ""], attachments: ["assets/photo.png"], canvases: ["Board.canvas": canvas])
        let e = edits(snap, "assets", "media", canvases: ["Board.canvas": canvas])
        XCTAssertTrue(e["Board.canvas"]?.contains("\"media/photo.png\"") == true)
        XCTAssertTrue(e["Board.canvas"]?.contains("\"Old.md\"") == true)
        let plan = LinkUpdater.plan(snap, from: "Old.md", to: "New.md") { $0 == "Board.canvas" ? canvas : nil }
        XCTAssertEqual(plan.edits.first?.links, 1)
        XCTAssertTrue(plan.edits.first?.text.contains("\"New.md\"") == true)
    }

    func testNothingToDo() {
        let snap = vault(["A.md": "[[B]] [[Unrelated]] https://x.y/Old.md", "B.md": "", "Old.md": ""])
        XCTAssertTrue(LinkUpdater.plan(snap, from: "Old.md", to: "New.md") { _ in nil }.isEmpty)
        // a move that keeps the name: bare links are fine
        XCTAssertTrue(edits(vault(["Old.md": "", "A.md": "[[Old]] ![[Old]]"]), "Old.md", "Sub/Old.md").isEmpty)
    }

    func testMovesMap() {
        let snap = vault(["F/a.md": "", "F/G/b.md": "", "Fx/c.md": ""], attachments: ["F/p.png"])
        let m = LinkUpdater.moves(snap, from: "F", to: "H")
        XCTAssertEqual(m.notes, ["F/a.md": "H/a.md", "F/G/b.md": "H/G/b.md"])
        XCTAssertEqual(m.files["F/p.png"], "H/p.png")
        XCTAssertNil(m.files["Fx/c.md"])
    }
}
