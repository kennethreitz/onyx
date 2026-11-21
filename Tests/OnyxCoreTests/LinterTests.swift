import XCTest
@testable import OnyxCore

final class LinterTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func lint(_ s: String, _ c: LinterConfig = .default, touched: Bool = false) -> String {
        let once = Linter.lint(s, config: c, now: now, touched: touched)
        XCTAssertEqual(Linter.lint(once, config: c, now: now, touched: touched), once, "not idempotent for: \(s.debugDescription)")
        return once
    }

    func testDefaults() {
        XCTAssertEqual(Linter.defaultEnabled, ["trailing-whitespace", "blank-lines", "trailing-newline", "heading-blank-lines",
                                              "heading-space", "list-marker", "code-blank-lines", "checkbox"])
        XCTAssertEqual(Linter.rules.count, 11)
        XCTAssertEqual(Set(Linter.rules.map(\.id)).count, Linter.rules.count)
    }

    func testTrailingWhitespaceKeepsHardBreaks() {
        XCTAssertEqual(lint("a \nb  \nc     \nd\t\n   \n", .only("trailing-whitespace")), "a\nb  \nc  \nd\n\n")
        var c = LinterConfig.only("trailing-whitespace"); c.preserveLineBreaks = false
        XCTAssertEqual(lint("a \nb  \n", c), "a\nb\n")
    }

    func testCollapseBlankLines() {
        XCTAssertEqual(lint("a\n\n\n\nb\n\nc\n", .only("blank-lines")), "a\n\nb\n\nc\n")
    }

    func testTrailingNewline() {
        let c = LinterConfig.only("trailing-newline")
        XCTAssertEqual(lint("a", c), "a\n")
        XCTAssertEqual(lint("a\n\n\n", c), "a\n")
        XCTAssertEqual(lint("", c), "")
        XCTAssertEqual(lint("---\ntitle: x\n---\n\n\n", c), "---\ntitle: x\n---\n")
    }

    func testHeadingBlankLines() {
        let c = LinterConfig.only("heading-blank-lines")
        XCTAssertEqual(lint("# A\ntext\n## B\nmore\n", c), "# A\n\ntext\n\n## B\n\nmore\n")
        XCTAssertEqual(lint("---\nx: 1\n---\n# A\nt\n", c), "---\nx: 1\n---\n# A\n\nt\n")
        XCTAssertEqual(lint("#tag line\ntext\n", c), "#tag line\ntext\n")   // a tag, not a heading
    }

    func testHeadingSpace() {
        let c = LinterConfig.only("heading-space")
        XCTAssertEqual(lint("##Heading\n###### Six\n#tag\n####\n", c), "## Heading\n###### Six\n#tag\n####\n")
    }

    func testListMarker() {
        XCTAssertEqual(lint("* a\n+ b\n  * c\n- d\n**bold**\n* * *\n1. one\n", .only("list-marker")),
                       "- a\n- b\n  - c\n- d\n**bold**\n* * *\n1. one\n")
        var c = LinterConfig.only("list-marker"); c.listMarker = "*"
        XCTAssertEqual(lint("- a\n+ b\n", c), "* a\n* b\n")
    }

    func testCodeBlankLines() {
        let c = LinterConfig.only("code-blank-lines")
        XCTAssertEqual(lint("text\n```swift\nlet x = 1\n```\nafter\n", c), "text\n\n```swift\nlet x = 1\n```\n\nafter\n")
        XCTAssertEqual(lint("- item\n  ```\n  code\n  ```\n- next\n", c), "- item\n  ```\n  code\n  ```\n- next\n")   // nested fences untouched
    }

    func testCheckboxes() {
        XCTAssertEqual(lint("- [] a\n- [X] b\n- [  ] c\n- [/] d\n1. [X] e\n[X] not a task\n", .only("checkbox")),
                       "- [ ] a\n- [x] b\n- [ ] c\n- [/] d\n1. [x] e\n[X] not a task\n")
    }

    func testHeadingIncrement() {
        let c = LinterConfig.only("heading-increment")
        XCTAssertEqual(lint("# A\n### B\n##### C\n## D\n#### E\n", c), "# A\n## B\n### C\n## D\n### E\n")
        XCTAssertEqual(lint("## Start\n#### Skip\n", c), "## Start\n### Skip\n")   // the first heading keeps its level
        XCTAssertFalse(LinterConfig.default.on("heading-increment"))
    }

    func testFrontmatterTidy() {
        let c = LinterConfig.only("frontmatter-tidy")
        XCTAssertEqual(lint("---\ntitle :  Hello: World  \ntags:\n  - a\nurl:   \"https://x.y\"\nempty:   \n---\nbody\n", c),
                       "---\ntitle: Hello: World  \ntags:\n  - a\nurl: \"https://x.y\"\nempty:\n---\nbody\n")
        // Body text that looks like YAML is not frontmatter.
        XCTAssertEqual(lint("key :value\n", c), "key :value\n")
        XCTAssertFalse(LinterConfig.default.on("frontmatter-tidy"))
    }

    func testTimestamp() {
        let c = LinterConfig.only("timestamp", "trailing-whitespace")
        let ts = Linter.timestamp(now)
        // Nothing to fix and not touched: no stamp.
        XCTAssertEqual(lint("---\ntitle: x\n---\nbody\n", c), "---\ntitle: x\n---\nbody\n")
        // A fix stamps; an existing key is replaced in place.
        XCTAssertEqual(lint("---\ntitle: x\nupdated: 2020-01-01\n---\nbody \n", c), "---\ntitle: x\nupdated: \(ts)\n---\nbody\n")
        // Touched (lint on save) stamps even without fixes, and creates frontmatter when missing.
        XCTAssertEqual(lint("body\n", c, touched: true), "---\nupdated: \(ts)\n---\nbody\n")
        var m = c; m.timestampKey = "modified"
        XCTAssertEqual(lint("---\na: 1\n---\nb\n", m, touched: true), "---\na: 1\nmodified: \(ts)\n---\nb\n")
        XCTAssertFalse(LinterConfig.default.on("timestamp"))
    }

    func testProtectedRegions() {
        let all = LinterConfig(enabled: Set(Linter.rules.map(\.id)).subtracting(["timestamp"]))
        let fenced = "```\n* x  \n##Heading\n\n\n\n- [X] y\n```\n"
        XCTAssertEqual(lint(fenced, all), fenced)
        let tilde = "~~~md\n# h\ntext   \n~~~\n"
        XCTAssertEqual(lint(tilde, all), tilde)
        let math = "$$\n* a \\\\  \n##b\n$$\n"
        XCTAssertEqual(lint(math, all), math)
        let comment = "%%\n* hidden  \n##x\n\n\n\n%%\n"
        XCTAssertEqual(lint(comment, all), comment)
        let html = "<!--\n* hidden\n##x\n-->\n"
        XCTAssertEqual(lint(html, all), html)
        let callout = "> [!note] Title\n> * item\n> ##nope\n"
        XCTAssertEqual(lint(callout, all), callout)
        let fields = "* partOf:: [[Parent]]\n+ related:: [[A]], [[B]]\nkey:: value with  spaces\n"
        XCTAssertEqual(lint(fields, all), fields)
        let inline = "Text with `* code  ` and $x^2$ and [[Note#Heading|alias]] and [partOf:: [[X]]].\n"
        XCTAssertEqual(lint(inline, all), inline)
        let fm = "---\ntitle:   spaced value  \nlist: [a,b]\n---\n# Hi\n"
        XCTAssertEqual(lint(fm, all), "---\ntitle: spaced value  \nlist: [a,b]\n---\n# Hi\n")
        XCTAssertEqual(lint(fm), fm)   // defaults leave frontmatter alone
    }

    func testInlineSpansAcrossLines() {
        let all = LinterConfig.default
        let open = "Start `code that  \n* keeps   \ngoing` end\n"
        XCTAssertEqual(lint(open, all), open)
        let math = "Euler $e^{i\\pi}  \n+ 1 = 0$ ok\n"
        XCTAssertEqual(lint(math, all), math)
        // A span closed on its line is fine; the line's prefix is still linted.
        XCTAssertEqual(lint("* see [[Note|n]] and `x` and $y$   \n", all), "- see [[Note|n]] and `x` and $y$  \n")
        // A stray dollar only protects to the end of its paragraph.
        XCTAssertEqual(lint("costs $5 \n\n* a\n", all), "costs $5 \n\n- a\n")
    }

    func testUnclosedAndProtectedTails() {
        for text in ["```\n##not a heading   ", "%%\n# Hidden   ", "$$\nx   ", "partOf:: [[A]]  ", "> [!note] text   ", "Start `code\n##not a heading\n``` still code"] {
            XCTAssertEqual(lint(text), text)
        }
        XCTAssertEqual(Linter.rule("heading-space")!.transform("##Title"), "## Title")
    }

    func testFullNoteIsIdempotent() {
        let messy = "---\ntitle: Messy\n---\n#tag\n##Intro\nSome text   \n\n\n\n* one\n+ [X] two\n- [] three\n```js\nconsole.log(1)  \n```\nafter\n# End\n\n\n"
        let out = lint(messy)
        XCTAssertEqual(out, "---\ntitle: Messy\n---\n#tag\n\n## Intro\n\nSome text  \n\n- one\n- [x] two\n- [ ] three\n\n```js\nconsole.log(1)  \n```\n\nafter\n\n# End\n")
        XCTAssertEqual(lint("a\r\nb  \r\n\r\n\r\n", .default), "a\r\nb  \r\n")
    }

    func testCursorMapping() {
        let old = "a \n##Intro\nhello world\n"
        let new = Linter.lint(old)   // "a\n\n## Intro\n\nhello world\n"
        let caret = (old as NSString).range(of: "world").location
        XCTAssertEqual(Linter.mapCursor(caret, from: old, to: new), (new as NSString).range(of: "world").location)
        XCTAssertEqual(Linter.mapCursor(0, from: old, to: new), 0)
        XCTAssertEqual(Linter.mapCursor(2, from: old, to: new), 1)   // past trimmed trailing space clamps
    }
}
