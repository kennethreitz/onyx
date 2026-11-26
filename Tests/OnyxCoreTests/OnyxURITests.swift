import XCTest
@testable import OnyxCore

final class OnyxURITests: XCTestCase {

    // MARK: Open

    func testOpenVaultByName() {
        let u = parse("onyx://open?vault=my%20vault")
        guard case .open(let o) = u else { return XCTFail("\(String(describing: u))") }
        XCTAssertEqual(o.vault, "my vault")
        XCTAssertNil(o.file)
        XCTAssertNil(o.path)
    }

    func testOpenVaultByID() {
        guard case .open(let o) = parse("onyx://open?vault=ef6ca3e3b524d22f") else { return XCTFail() }
        XCTAssertEqual(o.vault, "ef6ca3e3b524d22f")
    }

    func testOpenFileOmitsMarkdownExtension() {
        guard case .open(let o) = parse("onyx://open?vault=my%20vault&file=my%20note") else { return XCTFail() }
        XCTAssertEqual(o.vault, "my vault")
        XCTAssertEqual(o.file, "my note")
    }

    func testOpenFilePercentEncodedSlash() {
        guard case .open(let o) = parse("onyx://open?vault=Notes&file=path%2Fto%2Fmy%20note") else { return XCTFail() }
        XCTAssertEqual(o.file, "path/to/my note")
    }

    func testOpenFileAllowsUnencodedSlash() {
        guard case .open(let o) = parse("onyx://open?vault=Notes&file=path/to/my%20note") else { return XCTFail() }
        XCTAssertEqual(o.file, "path/to/my note")
    }

    func testOpenHeadingEncodedInFile() {
        guard case .open(let o) = parse("onyx://open?vault=Notes&file=Note%23Heading") else { return XCTFail() }
        XCTAssertEqual(o.file, "Note")
        XCTAssertEqual(o.heading, "Heading")
        XCTAssertNil(o.block)
    }

    func testOpenHeadingAsFragment() {
        guard case .open(let o) = parse("onyx://open?vault=Notes&file=Note#Heading") else { return XCTFail() }
        XCTAssertEqual(o.file, "Note")
        XCTAssertEqual(o.heading, "Heading")
    }

    func testOpenBlockEncodedInFile() {
        guard case .open(let o) = parse("onyx://open?vault=Notes&file=Note%23%5Eid") else { return XCTFail() }
        XCTAssertEqual(o.file, "Note")
        XCTAssertNil(o.heading)
        XCTAssertEqual(o.block, "id")
    }

    func testOpenBlockAsFragment() {
        guard case .open(let o) = parse("onyx://open?vault=Notes&file=Note#^block-id") else { return XCTFail() }
        XCTAssertEqual(o.file, "Note")
        XCTAssertEqual(o.block, "block-id")
    }

    func testOpenAbsolutePath() {
        guard case .open(let o) = parse("onyx://open?path=%2Fhome%2Fuser%2Fmy%20vault%2Fpath%2Fto%2Fmy%20note") else { return XCTFail() }
        XCTAssertEqual(o.path, "/home/user/my vault/path/to/my note")
        XCTAssertNil(o.vault)
        XCTAssertNil(o.file)
    }

    func testPlusIsNotASpace() {
        guard case .open(let o) = parse("onyx://open?vault=Notes&file=C++") else { return XCTFail() }
        XCTAssertEqual(o.file, "C++")
    }

    func testSpaceIsPercentTwenty() {
        guard case .open(let o) = parse("onyx://open?vault=My%20Vault&file=Hello%20world") else { return XCTFail() }
        XCTAssertEqual(o.vault, "My Vault")
        XCTAssertEqual(o.file, "Hello world")
    }

    // MARK: Forms of the action

    func testTripleSlashAndXCallback() {
        XCTAssertNotNil(parse("onyx:///open?vault=Notes"))
        XCTAssertNotNil(parse("onyx://x-callback-url/open?vault=Notes"))
        guard case .open(let a) = parse("onyx:///open?vault=Notes"),
              case .open(let b) = parse("onyx://x-callback-url/open?vault=Notes") else { return XCTFail() }
        XCTAssertEqual(a.vault, "Notes")
        XCTAssertEqual(b.vault, "Notes")
    }

    func testObsidianSchemeParsesTheSame() {
        guard case .open(let o) = parse("obsidian://open?vault=my%20vault&file=my%20note%23H") else { return XCTFail() }
        XCTAssertEqual(o.vault, "my vault")
        XCTAssertEqual(o.file, "my note")
        XCTAssertEqual(o.heading, "H")
    }

    func testClipIsOnyxOnly() {
        XCTAssertEqual(parse("onyx://clip?url=https://ex.com"), .clip)
        XCTAssertEqual(parse("onyx:///clip?url=https://ex.com"), .clip)
        XCTAssertEqual(parse("onyx://x-callback-url/clip?url=https://ex.com"), .clip)
        XCTAssertNil(parse("obsidian://clip?url=https://ex.com"))
        // Empty clip with no query is still the clip action; WebClip.request will reject the payload.
        XCTAssertEqual(parse("onyx://clip"), .clip)
    }

    func testUnknownActionIsNil() {
        XCTAssertNil(parse("onyx://unique?vault=Notes"))
        XCTAssertNil(parse("https://example.com"))
        XCTAssertNil(parse("onyx://choose-vault"))
    }

    // MARK: Shorthand

    func testVaultShorthandOpensFile() {
        guard case .open(let o) = parse("onyx://vault/My%20Vault/folder/Note") else { return XCTFail() }
        XCTAssertEqual(o.vault, "My Vault")
        XCTAssertEqual(o.file, "folder/Note")
    }

    func testVaultShorthandVaultOnly() {
        guard case .open(let o) = parse("onyx://vault/Notes") else { return XCTFail() }
        XCTAssertEqual(o.vault, "Notes")
        XCTAssertNil(o.file)
    }

    func testVaultShorthandHeading() {
        guard case .open(let o) = parse("onyx://vault/Notes/Note%23Heading") else { return XCTFail() }
        XCTAssertEqual(o.vault, "Notes")
        XCTAssertEqual(o.file, "Note")
        XCTAssertEqual(o.heading, "Heading")
    }

    func testVaultShorthandFragment() {
        guard case .open(let o) = parse("onyx://vault/Notes/folder/Note#^bid") else { return XCTFail() }
        XCTAssertEqual(o.file, "folder/Note")
        XCTAssertEqual(o.block, "bid")
    }

    // MARK: Search

    func testSearchWithQuery() {
        guard case .search(let s) = parse("onyx://search?vault=my%20vault&query=Obsidian") else { return XCTFail() }
        XCTAssertEqual(s.vault, "my vault")
        XCTAssertEqual(s.query, "Obsidian")
    }

    func testSearchWithoutQuery() {
        guard case .search(let s) = parse("onyx://search?vault=Notes") else { return XCTFail() }
        XCTAssertEqual(s.vault, "Notes")
        XCTAssertNil(s.query)
    }

    func testSearchQueryKeepsSpecialCharacters() {
        guard case .search(let s) = parse("onyx://search?vault=Notes&query=tag%3Afoo%20%22exact%20phrase%22") else { return XCTFail() }
        XCTAssertEqual(s.query, "tag:foo \"exact phrase\"")
    }

    // MARK: New / daily flags

    func testNewNameAndFile() {
        guard case .new(let n) = parse("onyx://new?vault=my%20vault&name=my%20note") else { return XCTFail() }
        XCTAssertEqual(n.vault, "my vault")
        XCTAssertEqual(n.name, "my note")
        XCTAssertFalse(n.overwrite)
        XCTAssertFalse(n.append)
        XCTAssertFalse(n.silent)
    }

    func testNewFileOverridesNameInTheParserAsSeparateFields() {
        // The app prefers `file` over `name`; the parser keeps both.
        guard case .new(let n) = parse("onyx://new?vault=V&name=A&file=path%2Fto%2Fmy%20note") else { return XCTFail() }
        XCTAssertEqual(n.name, "A")
        XCTAssertEqual(n.file, "path/to/my note")
    }

    func testNewFlags() {
        guard case .new(let n) = parse("onyx://new?vault=V&file=n&content=Hello&append=true&silent=true") else { return XCTFail() }
        XCTAssertEqual(n.content, "Hello")
        XCTAssertTrue(n.append)
        XCTAssertTrue(n.silent)
        XCTAssertFalse(n.shouldOverwrite)
    }

    func testBareFlagIsTrue() {
        guard case .new(let n) = parse("onyx://new?vault=V&name=n&overwrite&clipboard&silent") else { return XCTFail() }
        XCTAssertTrue(n.overwrite)
        XCTAssertTrue(n.clipboard)
        XCTAssertTrue(n.silent)
        XCTAssertTrue(n.shouldOverwrite)
    }

    func testExplicitFalseFlag() {
        guard case .new(let n) = parse("onyx://new?vault=V&name=n&overwrite=false&append=0&prepend=no") else { return XCTFail() }
        XCTAssertFalse(n.overwrite)
        XCTAssertFalse(n.append)
        XCTAssertFalse(n.prepend)
    }

    func testOverwriteIgnoredWhenAppendIsSet() {
        guard case .new(let n) = parse("onyx://new?vault=V&file=n&overwrite=true&append=true") else { return XCTFail() }
        XCTAssertTrue(n.overwrite)
        XCTAssertTrue(n.append)
        XCTAssertFalse(n.shouldOverwrite)
        guard case .new(let p) = parse("onyx://new?vault=V&file=n&overwrite=true&prepend=true") else { return XCTFail() }
        XCTAssertFalse(p.shouldOverwrite)
    }

    func testNewHeadingAndSpacing() {
        guard case .new(let n) = parse("onyx://new?vault=V&file=n&append=true&heading=Tasks&content=Buy%20milk&spacing=newline") else { return XCTFail() }
        XCTAssertEqual(n.heading, "Tasks")
        XCTAssertEqual(n.content, "Buy milk")
        XCTAssertEqual(n.spacing, .newline)
    }

    func testDailyUsesTheSameParameters() {
        guard case .daily(let n) = parse("onyx://daily?vault=my%20vault&append=true&heading=Log&content=Called%20Sam") else { return XCTFail() }
        XCTAssertEqual(n.vault, "my vault")
        XCTAssertTrue(n.append)
        XCTAssertEqual(n.heading, "Log")
        XCTAssertEqual(n.content, "Called Sam")
    }

    // MARK: Path safety

    func testNormalizeRelativeFoldsDotAndDotDot() {
        XCTAssertEqual(OnyxURI.normalizeRelative("foo/../bar"), "bar")
        XCTAssertEqual(OnyxURI.normalizeRelative("/foo/bar"), "foo/bar")
        XCTAssertEqual(OnyxURI.normalizeRelative("foo/./bar"), "foo/bar")
        XCTAssertEqual(OnyxURI.normalizeRelative("foo\\bar"), "foo/bar")
        XCTAssertEqual(OnyxURI.normalizeRelative(""), "")
        XCTAssertEqual(OnyxURI.normalizeRelative("."), "")
    }

    func testNormalizeRelativeRejectsEscape() {
        XCTAssertNil(OnyxURI.normalizeRelative(".."))
        XCTAssertNil(OnyxURI.normalizeRelative("../secret"))
        XCTAssertNil(OnyxURI.normalizeRelative("foo/../../bar"))
        XCTAssertNil(OnyxURI.normalizeRelative("/../etc/passwd"))
    }

    func testMarkdownPath() {
        XCTAssertEqual(OnyxURI.markdownPath(for: "Note"), "Note.md")
        XCTAssertEqual(OnyxURI.markdownPath(for: "folder/Note"), "folder/Note.md")
        XCTAssertEqual(OnyxURI.markdownPath(for: "folder/Note.md"), "folder/Note.md")
        XCTAssertEqual(OnyxURI.markdownPath(for: "board.canvas"), "board.canvas")
        XCTAssertEqual(OnyxURI.markdownPath(for: "pic.png"), "pic.png")
    }

    func testSplitAnchor() {
        let a = OnyxURI.splitAnchor("Note#Heading")
        XCTAssertEqual(a.file, "Note")
        XCTAssertEqual(a.heading, "Heading")
        XCTAssertNil(a.block)
        let b = OnyxURI.splitAnchor("Note#^block-id")
        XCTAssertEqual(b.file, "Note")
        XCTAssertNil(b.heading)
        XCTAssertEqual(b.block, "block-id")
        let c = OnyxURI.splitAnchor("Note")
        XCTAssertEqual(c.file, "Note")
        XCTAssertNil(c.heading)
        XCTAssertNil(c.block)
    }

    // MARK: Vault resolution

    func testResolveVaultByNameOrIDOrCurrent() {
        let notes = KnownVault(name: "Notes", url: URL(fileURLWithPath: "/Users/me/Notes"), id: "abc123")
        let work = KnownVault(name: "Work", url: URL(fileURLWithPath: "/Users/me/Work"), id: "def456")
        let all = [notes, work]
        XCTAssertEqual(OnyxURIVaults.resolve(nil, among: all, current: notes), notes)
        XCTAssertEqual(OnyxURIVaults.resolve("", among: all, current: work), work)
        XCTAssertEqual(OnyxURIVaults.resolve("Work", among: all, current: notes), work)
        XCTAssertEqual(OnyxURIVaults.resolve("work", among: all, current: notes), work)
        XCTAssertEqual(OnyxURIVaults.resolve("abc123", among: all, current: work), notes)
        XCTAssertEqual(OnyxURIVaults.resolve("/Users/me/Work", among: all, current: notes), work)
        XCTAssertNil(OnyxURIVaults.resolve("Missing", among: all, current: notes))
    }

    func testResolvePrefersCurrentWhenNamesCollide() {
        let a = KnownVault(name: "Notes", url: URL(fileURLWithPath: "/tmp/a/Notes"))
        let b = KnownVault(name: "Notes", url: URL(fileURLWithPath: "/tmp/b/Notes"))
        XCTAssertEqual(OnyxURIVaults.resolve("Notes", among: [a, b], current: b), b)
        XCTAssertEqual(OnyxURIVaults.resolve("Notes", among: [a, b], current: nil), a)
    }

    func testContainingPicksTheMostSpecificVault() {
        let parent = KnownVault(name: "Notes", url: URL(fileURLWithPath: "/Users/me/Notes"))
        let child = KnownVault(name: "Sub", url: URL(fileURLWithPath: "/Users/me/Notes/Sub"))
        let hit = OnyxURIVaults.containing("/Users/me/Notes/Sub/a.md", among: [parent, child])
        XCTAssertEqual(hit?.0, child)
        XCTAssertEqual(hit?.1, "a.md")
        let top = OnyxURIVaults.containing("/Users/me/Notes/inbox/a.md", among: [parent, child])
        XCTAssertEqual(top?.0, parent)
        XCTAssertEqual(top?.1, "inbox/a.md")
        let root = OnyxURIVaults.containing("/Users/me/Notes", among: [parent])
        XCTAssertEqual(root?.1, "")
        XCTAssertNil(OnyxURIVaults.containing("/tmp/other/a.md", among: [parent]))
    }

    func testParseObsidianAppJSON() {
        let json = """
        {"vaults":{"ef6ca3e3b524d22f":{"path":"/Users/me/Notes","ts":200},"zzzz":{"path":"/Users/me/Work","ts":100}}}
        """.data(using: .utf8)!
        let vaults = OnyxURIVaults.parseObsidianAppJSON(json)
        XCTAssertEqual(vaults.count, 2)
        XCTAssertEqual(vaults[0].name, "Notes")
        XCTAssertEqual(vaults[0].id, "ef6ca3e3b524d22f")
        XCTAssertEqual(vaults[1].name, "Work")
    }

    // MARK: Content apply

    func testApplyCreatesOrOverwrites() {
        let fresh = OnyxURI.New(content: "Hi")
        XCTAssertEqual(OnyxURIContent.apply(existing: nil, incoming: "Hi", flags: fresh), "Hi")
        var over = OnyxURI.New(overwrite: true)
        XCTAssertEqual(OnyxURIContent.apply(existing: "Old", incoming: "New", flags: over), "New")
        over.append = true
        XCTAssertEqual(OnyxURIContent.apply(existing: "Old", incoming: "New", flags: over), "Old\n\nNew")
    }

    func testApplyWithoutFlagsLeavesExistingAlone() {
        let flags = OnyxURI.New(content: "ignored")
        XCTAssertEqual(OnyxURIContent.apply(existing: "Stay", incoming: "ignored", flags: flags), "Stay")
    }

    func testApplyAppendAndPrependSpacing() {
        var flags = OnyxURI.New(append: true, spacing: .auto)
        XCTAssertEqual(OnyxURIContent.apply(existing: "A", incoming: "B", flags: flags), "A\n\nB")
        flags.spacing = .newline
        XCTAssertEqual(OnyxURIContent.apply(existing: "A", incoming: "B", flags: flags), "A\nB")
        flags.spacing = .inline
        XCTAssertEqual(OnyxURIContent.apply(existing: "A", incoming: "B", flags: flags), "AB")
        flags = OnyxURI.New(prepend: true, spacing: .auto)
        XCTAssertEqual(OnyxURIContent.apply(existing: "A", incoming: "B", flags: flags), "B\n\nA")
    }

    func testApplyAppendUnderHeading() {
        let existing = "# Intro\n\nHello\n\n# Tasks\n\n- [ ] one\n\n# Done\n\n- x\n"
        var flags = OnyxURI.New(append: true, heading: "Tasks", spacing: .newline)
        let out = OnyxURIContent.apply(existing: existing, incoming: "- [ ] two", flags: flags)
        XCTAssertEqual(out, "# Intro\n\nHello\n\n# Tasks\n\n- [ ] one\n- [ ] two\n# Done\n\n- x\n")
        flags.prepend = true
        flags.append = false
        let pre = OnyxURIContent.apply(existing: existing, incoming: "- [ ] zero", flags: flags)
        XCTAssertTrue(pre.contains("# Tasks\n- [ ] zero\n\n- [ ] one"), pre)
    }

    func testApplyMissingHeadingFallsBackToWholeFile() {
        let flags = OnyxURI.New(append: true, heading: "Missing", spacing: .auto)
        XCTAssertEqual(OnyxURIContent.apply(existing: "# Intro\n\nHi\n", incoming: "X", flags: flags),
                       "# Intro\n\nHi\n\n\nX")
    }

    // MARK: Build / round-trip

    func testMakeOpenEncodesReservedCharacters() {
        let u = OnyxURI.makeOpen(vault: "My Vault", file: "folder/Note.md", heading: "A heading")
        XCTAssertEqual(u?.absoluteString, "onyx://open?vault=My%20Vault&file=folder%2FNote.md%23A%20heading")
        guard case .open(let o) = OnyxURI.parse(u!) else { return XCTFail() }
        XCTAssertEqual(o.vault, "My Vault")
        XCTAssertEqual(o.file, "folder/Note.md")
        XCTAssertEqual(o.heading, "A heading")
    }

    func testMakeOpenBlockRoundTrip() {
        let u = OnyxURI.makeOpen(vault: "Notes", file: "A.md", block: "bid")
        guard case .open(let o) = OnyxURI.parse(u!) else { return XCTFail() }
        XCTAssertEqual(o.file, "A.md")
        XCTAssertEqual(o.block, "bid")
        XCTAssertNil(o.heading)
    }

    // MARK: Click extraction

    func testURLInMarkdownLink() {
        let s = "See [this](onyx://open?vault=Notes&file=Hello%20world) please"
        let start = s.distance(from: s.startIndex, to: s.firstIndex(of: "[")!)
        let u = OnyxURI.url(in: s, at: start)
        XCTAssertEqual(OnyxURI.parse(u!), parse("onyx://open?vault=Notes&file=Hello%20world"))
        XCTAssertNil(OnyxURI.url(in: "See [this](https://example.com)", at: 4))
    }

    func testURLRawInText() {
        let s = "open onyx://open?vault=Notes&file=A then go"
        let at = s.distance(from: s.startIndex, to: s.range(of: "onyx:")!.lowerBound)
        let u = OnyxURI.url(in: s, at: at + 2)
        guard case .open(let o) = OnyxURI.parse(u!) else { return XCTFail() }
        XCTAssertEqual(o.file, "A")
        XCTAssertNotNil(OnyxURI.url(in: "obsidian://search?vault=Notes&query=x", at: 0))
    }

    // MARK: Helpers

    private func parse(_ s: String) -> OnyxURI? {
        guard let url = URL(string: s) else { XCTFail("bad URL \(s)"); return nil }
        return OnyxURI.parse(url)
    }
}
