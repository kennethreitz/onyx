import XCTest
@testable import OnyxCore

final class AttachmentsTests: XCTestCase {
    func testSettingsFromAppJSON() {
        XCTAssertEqual(Attachments.Settings(appJSON: nil), .init(folder: nil, useMarkdownLinks: false, linkFormat: "shortest"))
        let s = Attachments.Settings(appJSON: ["attachmentFolderPath": "./assets", "useMarkdownLinks": true, "newLinkFormat": "relative"])
        XCTAssertEqual(s, .init(folder: "./assets", useMarkdownLinks: true, linkFormat: "relative"))
        XCTAssertEqual(Attachments.Settings(appJSON: ["newLinkFormat": "bogus"]).linkFormat, "shortest")
    }

    func testPastedImageName() {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 23; c.hour = 7; c.minute = 59; c.second = 3
        let tz = TimeZone(identifier: "America/New_York")!
        c.timeZone = tz
        let d = Calendar(identifier: .gregorian).date(from: c)!
        XCTAssertEqual(Attachments.pastedImageName(date: d, timeZone: tz), "Pasted image 20261123075903.png")
        XCTAssertEqual(Attachments.pastedImageName(date: d, ext: "jpg", timeZone: tz), "Pasted image 20261123075903.jpg")
    }

    func testSanitize() {
        XCTAssertEqual(Attachments.sanitize("a:b|c?.png"), "a b c .png")
        XCTAssertEqual(Attachments.sanitize("[x] #1.pdf"), "x 1.pdf")
        XCTAssertEqual(Attachments.sanitize(".hidden.png"), "hidden.png")
        XCTAssertEqual(Attachments.sanitize("Café photo.HEIC"), "Café photo.HEIC")
    }

    func testDestinationFolderAndUniqueName() {
        let taken: Set = ["Pic.png", "Pic 1.png", "A/assets/x.pdf"]
        let root = Attachments.Settings()
        XCTAssertEqual(Attachments.destination(name: "Pic.png", note: "A/n.md", settings: root) { taken.contains($0) }, "Pic 2.png")
        XCTAssertEqual(Attachments.destination(name: "new.png", note: "A/n.md", settings: root) { taken.contains($0) }, "new.png")
        let same = Attachments.Settings(folder: "./")
        XCTAssertEqual(Attachments.destination(name: "Pic.png", note: "A/n.md", settings: same) { taken.contains($0) }, "A/Pic.png")
        let sub = Attachments.Settings(folder: "./assets")
        XCTAssertEqual(Attachments.destination(name: "x.pdf", note: "A/n.md", settings: sub) { taken.contains($0) }, "A/assets/x 1.pdf")
        let fixed = Attachments.Settings(folder: "Attachments")
        XCTAssertEqual(Attachments.destination(name: "a?b.png", note: "A/n.md", settings: fixed) { taken.contains($0) }, "Attachments/a b.png")
        XCTAssertEqual(Attachments.destination(name: "LICENSE", note: nil, settings: root) { $0 == "LICENSE" }, "LICENSE 1")
    }

    func testWikilinks() {
        let s = Attachments.Settings()
        XCTAssertEqual(Attachments.link(to: "Attachments/Pic 1.png", from: "A/n.md", settings: s) { _ in true }, "![[Pic 1.png]]")
        XCTAssertEqual(Attachments.link(to: "Attachments/Pic.png", from: "A/n.md", settings: s) { _ in false }, "![[Attachments/Pic.png]]")
        XCTAssertEqual(Attachments.link(to: "x/talk.m4a", from: nil, settings: s) { _ in true }, "![[talk.m4a]]")
        XCTAssertEqual(Attachments.link(to: "x/paper.pdf", from: nil, settings: s) { _ in true }, "![[paper.pdf]]")
        XCTAssertEqual(Attachments.link(to: "x/data.zip", from: nil, settings: s) { _ in true }, "[[data.zip]]")
        XCTAssertEqual(Attachments.link(to: "B/Other Note.md", from: "A/n.md", settings: s) { _ in true }, "[[Other Note]]")
        XCTAssertEqual(Attachments.link(to: "B/Other Note.md", from: "A/n.md", settings: s) { _ in false }, "[[B/Other Note]]")
        let rel = Attachments.Settings(linkFormat: "relative")
        XCTAssertEqual(Attachments.link(to: "B/img.png", from: "A/n.md", settings: rel) { _ in true }, "![[../B/img.png]]")
        let abs = Attachments.Settings(linkFormat: "absolute")
        XCTAssertEqual(Attachments.link(to: "B/img.png", from: "A/n.md", settings: abs) { _ in true }, "![[B/img.png]]")
    }

    func testMarkdownLinks() {
        let s = Attachments.Settings(useMarkdownLinks: true)
        XCTAssertEqual(Attachments.link(to: "Attachments/Pasted image 1.png", from: "n.md", settings: s) { _ in true }, "![](Pasted%20image%201.png)")
        XCTAssertEqual(Attachments.link(to: "x/data.zip", from: nil, settings: s) { _ in false }, "[data.zip](x/data.zip)")
        XCTAssertEqual(Attachments.link(to: "B/Other Note.md", from: "A/n.md", settings: s) { _ in true }, "[Other Note](Other%20Note.md)")
        let rel = Attachments.Settings(useMarkdownLinks: true, linkFormat: "relative")
        XCTAssertEqual(Attachments.link(to: "A/img.png", from: "A/n.md", settings: rel) { _ in true }, "![](./img.png)")
        XCTAssertEqual(Attachments.link(to: "img.png", from: "A/B/n.md", settings: rel) { _ in true }, "![](../../img.png)")
    }

    func testInsertion() {
        XCTAssertEqual(Attachments.insertion(["![[a.png]]"]), "![[a.png]]")
        XCTAssertEqual(Attachments.insertion(["![[a.png]]", "[[b.zip]]"]), "![[a.png]]\n[[b.zip]]")
    }

    func testMarkdownImageResolution() {
        let text = "x ![](Pasted%20image%201.png) ![a](<sub/b c.png>) ![](https://e.com/i.png) ![](../top.png)"
        XCTAssertEqual(Attachments.markdownImageTargets(in: text), ["Pasted%20image%201.png", "sub/b c.png", "../top.png"])
        let files: Set = ["Attachments/Pasted image 1.png", "A/sub/b c.png", "top.png"]
        let exists = { (p: String) in files.contains(p) }
        let byName = { (p: String) -> String? in files.first { ($0 as NSString).lastPathComponent == (p as NSString).lastPathComponent } }
        XCTAssertEqual(Attachments.resolveMarkdownTarget("Pasted%20image%201.png", from: "A/n.md", exists: exists, resolve: byName), "Attachments/Pasted image 1.png")
        XCTAssertEqual(Attachments.resolveMarkdownTarget("sub/b c.png", from: "A/n.md", exists: exists, resolve: byName), "A/sub/b c.png")
        XCTAssertEqual(Attachments.resolveMarkdownTarget("../top.png", from: "A/n.md", exists: exists, resolve: byName), "top.png")
        XCTAssertEqual(Attachments.resolveMarkdownTarget("/top.png", from: "A/n.md", exists: exists, resolve: byName), "top.png")
    }
}
