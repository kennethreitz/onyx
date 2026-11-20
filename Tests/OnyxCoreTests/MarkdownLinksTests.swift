import XCTest
@testable import OnyxCore

final class MarkdownLinksTests: XCTestCase {
    let files: Set<String> = ["Notes/A Note.md", "Notes/B.md", "Projects/Plan.md", "assets/pic one.png", "Notes/img/x.png", "Root.md"]
    func run(_ text: String, note: String, to newNote: String? = nil, moves: [String: String]) -> String {
        MarkdownLinks.rewrite(text, oldNote: note, newNote: newNote ?? moves[note] ?? note,
                              exists: { self.files.contains($0) },
                              resolveName: { n in self.files.first { ($0 as NSString).lastPathComponent == n } },
                              moved: { moves[$0] }) ?? text
    }

    func testRelativeEncodedAnchorAndEmbed() {
        let t = "See [plan](../Projects/Plan.md#Goals \"t\") and ![](../assets/pic%20one.png) and [b](B.md) and `[c](../Projects/Plan.md)`"
        let out = run(t, note: "Notes/B2.md", moves: ["Projects/Plan.md": "Archive/2026/Plan v2.md", "assets/pic one.png": "media/pic one.png"])
        XCTAssertEqual(out, "See [plan](../Archive/2026/Plan%20v2.md#Goals \"t\") and ![](../media/pic%20one.png) and [b](B.md) and `[c](../Projects/Plan.md)`")
    }

    func testMovedNoteRewritesItsOwnRelativeLinks() {
        let t = "[a](A%20Note.md) [p](../Projects/Plan.md) [v](/Projects/Plan.md) [img](img/x.png) [web](https://x.y/a.md) [h](#Local)"
        let out = run(t, note: "Notes/B.md", moves: ["Notes/B.md": "Deep/Er/B.md"])
        XCTAssertEqual(out, "[a](../../Notes/A%20Note.md) [p](../../Projects/Plan.md) [v](/Projects/Plan.md) [img](../../Notes/img/x.png) [web](https://x.y/a.md) [h](#Local)")
    }

    func testVaultAbsoluteNameAndAngle() {
        let moves = ["Notes/A Note.md": "Notes/Renamed.md", "Notes/B.md": "Other/B.md"]
        XCTAssertEqual(run("[x](Notes/A%20Note.md)", note: "Projects/Plan.md", moves: moves), "[x](Notes/Renamed.md)")
        XCTAssertEqual(run("[x](<Notes/A Note.md#H>)", note: "Projects/Plan.md", moves: moves), "[x](<Notes/Renamed.md#H>)")
        XCTAssertEqual(run("[x](/Notes/B.md)", note: "Projects/Plan.md", moves: moves), "[x](/Other/B.md)")
        XCTAssertEqual(run("[x](A%20Note.md)", note: "Projects/Plan.md", moves: moves), "[x](Renamed.md)")        // shortest (by name)
        XCTAssertEqual(run("[x](B.md)", note: "Projects/Plan.md", moves: moves), "[x](B.md)")                     // name unchanged: still resolves
        XCTAssertEqual(run("[x](Notes/B)", note: "Root.md", moves: moves), "[x](Other/B)")                        // no extension stays without
        XCTAssertEqual(run("[r](Root.md)", note: "Root.md", to: "Sub/Root.md", moves: [:]), "[r](../Root.md)")    // root note moved down
    }

    func testHelpers() {
        XCTAssertEqual(MarkdownLinks.relative(from: "a/b", to: "a/c/d.md"), "../c/d.md")
        XCTAssertEqual(MarkdownLinks.relative(from: "", to: "a/d.md"), "a/d.md")
        XCTAssertEqual(MarkdownLinks.relative(from: "a", to: "a/d.md"), "d.md")
        XCTAssertNil(MarkdownLinks.normalize("../x"))
        XCTAssertEqual(MarkdownLinks.normalize("a/./b/../c"), "a/c")
        XCTAssertEqual(MarkdownLinks.destinations(in: "```\n[a](b.md)\n```\n%%[c](d.md)%% [e](f.md)").count, 1)
    }
}
