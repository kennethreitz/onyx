import XCTest
@testable import OnyxCore

final class HTMLToMarkdownTests: XCTestCase {
    let base = URL(string: "https://example.com/blog/post")!
    func md(_ html: String) -> String { HTMLToMarkdown(baseURL: base).convert(html) }

    func testParagraphsHeadingsAndEmphasis() {
        let html = #"<div xmlns="http://www.w3.org/1999/xhtml"><h2>Intro  text</h2><p>Hello <strong>bold</strong> and <em>italic</em>, <del>gone</del> <mark>lit</mark>.</p><p>Second</p></div>"#
        XCTAssertEqual(md(html), "## Intro text\n\nHello **bold** and *italic*, ~~gone~~ ==lit==.\n\nSecond")
    }

    func testWhitespaceInsideMarksStaysOutside() {
        XCTAssertEqual(md("<p>a<b> b </b>c</p>"), "a **b** c")
    }

    func testLinksAreAbsoluteAndAnchorsDropped() {
        XCTAssertEqual(md(##"<p>See <a href="/about me">the page</a> and <a href="#fn1">1</a>.</p>"##),
                       "See [the page](https://example.com/about%20me) and 1.")
    }

    func testImagesAreHotlinkedFromTheLargestSrcset() {
        let out = md(#"<p><img src="data:image/gif;base64,AAAA" srcset="small.jpg 320w, big.jpg 1200w, mid.jpg 800w" alt="A [cat]"/><img src="/x.png" alt="x"/><img src="data:image/png;base64,AA"/></p>"#)
        XCTAssertEqual(out, "![A cat](https://example.com/blog/big.jpg)![x](https://example.com/x.png)")
        // srcset wins over a smaller src; density descriptors too.
        XCTAssertEqual(md(#"<img src="https://cdn.e.com/a-400.jpg" srcset="https://cdn.e.com/a-400.jpg 1x, //cdn.e.com/a-800.jpg 2x"/>"#),
                       "![](https://cdn.e.com/a-800.jpg)")
    }

    func testLazyImagesResolveToAbsoluteURLs() {
        XCTAssertEqual(md(#"<img src="data:image/svg+xml,%3Csvg/%3E" data-src="../img/lazy one.jpg" alt="Lazy"/>"#),
                       "![Lazy](https://example.com/img/lazy%20one.jpg)")
        XCTAssertEqual(md(#"<img data-srcset="/s.webp 300w, /l.webp 1600w"/>"#), "![](https://example.com/l.webp)")
        XCTAssertEqual(md(#"<img data-original="//images.e.com/o.png"/>"#), "![](https://images.e.com/o.png)")
    }

    func testPictureSourcesCompete() {
        let html = #"<picture><source type="image/avif" srcset="/p-2000.avif 2000w, /p-800.avif 800w"/><img src="/p-640.jpg" alt="P"/></picture>"#
        XCTAssertEqual(md(html), "![P](https://example.com/p-2000.avif)")
    }

    func testDataURIsAndTrackingPixelsAreDropped() {
        XCTAssertEqual(md(#"<p>a<img src="data:image/png;base64,AA"/>b</p>"#), "ab")
        XCTAssertEqual(md(#"<p>a<img src="https://e.com/beacon.gif?id=1" width="1" height="1"/>b</p>"#), "ab")
        XCTAssertEqual(md(#"<p>a<img src="https://www.facebook.com/tr?id=1&amp;ev=PageView"/>b</p>"#), "ab")
        XCTAssertEqual(md(#"<p>a<img src="https://pixel.wp.com/g.gif?v=1"/>b</p>"#), "ab")
        XCTAssertEqual(md(#"<p>a<img src="blob:https://e.com/1234"/>b</p>"#), "ab")
        // A small but real image stays.
        XCTAssertEqual(md(#"<img src="https://e.com/icon.png" width="16" height="16" alt="i"/>"#), "![i](https://e.com/icon.png)")
    }

    func testLinkedImageKeepsImage() {
        XCTAssertEqual(md(#"<a href="https://x.com/full.png"><img src="https://x.com/t.png" alt=""/></a>"#), "![](https://x.com/t.png)")
    }

    func testNestedListsAndTasks() {
        let html = "<ul><li>One<ul><li>Sub <b>a</b></li><li>Sub b</li></ul></li><li><input type=\"checkbox\" checked=\"checked\"/> Done</li></ul><ol start=\"3\"><li>Three</li><li>Four</li></ol>"
        XCTAssertEqual(md(html), "- One\n  - Sub **a**\n  - Sub b\n- [x] Done\n\n3. Three\n4. Four")
    }

    func testCodeBlocksKeepWhitespaceAndLanguage() {
        let html = "<p>Use <code>a_b</code>:</p><pre><code class=\"language-python\">def f():\n    return  1\n</code></pre>"
        XCTAssertEqual(md(html), "Use `a_b`:\n\n```python\ndef f():\n    return  1\n```")
        XCTAssertEqual(md("<pre data-onyx-lang=\"swift\">let x = 1</pre>"), "```swift\nlet x = 1\n```")
        XCTAssertEqual(md("<p><code>a`b</code></p>"), "``a`b``")
    }

    func testCodeInsideListIsIndented() {
        XCTAssertEqual(md("<ul><li><p>Run:</p><pre>make\nmake test</pre></li></ul>"), "- Run:\n\n  ```\n  make\n  make test\n  ```")
    }

    func testBlockquote() {
        XCTAssertEqual(md("<blockquote><p>One</p><p>Two</p></blockquote>"), "> One\n>\n> Two")
    }

    func testTable() {
        let html = "<table><thead><tr><th>Name</th><th>Value</th></tr></thead><tbody><tr><td>a|b</td><td><b>1</b></td></tr><tr><td>c</td></tr></tbody></table>"
        XCTAssertEqual(md(html), "| Name | Value |\n| --- | --- |\n| a\\|b | **1** |\n| c | |")
    }

    func testLayoutTableBecomesBlocks() {
        XCTAssertEqual(md("<table><tr><td><p>Just text</p></td></tr></table>"), "Just text")
    }

    func testEscapesMarkdownAndMath() {
        XCTAssertEqual(md("<p>Costs $5 *now* [[x]] snake_case</p>"), "Costs \\$5 \\*now\\* \\[\\[x\\]\\] snake\\_case")
        XCTAssertEqual(md("<p># not a heading</p><p>1. not a list</p><p>- nor this</p>"), "\\# not a heading\n\n1\\. not a list\n\n\\- nor this")
    }

    func testListMarkersOnlyEscapedAtLineStart() {
        XCTAssertEqual(md("<p><a href=\"https://e.com\">Book</a>. p. 24. Scribner.</p>"), "[Book](https://e.com). p. 24. Scribner.")
    }

    func testNestedEmphasisIsFlattened() {
        XCTAssertEqual(md("<p><cite>Fiske, <i>Dictionary</i> (2011)</cite></p>"), "*Fiske, Dictionary (2011)*")
        XCTAssertEqual(md("<p><b>a <strong>b</strong></b></p>"), "**a b**")
    }

    func testDropsScriptsAndChrome() {
        XCTAssertEqual(md("<div><script>alert(1)</script><style>p{}</style><nav>menu</nav><p>Body</p><form><button>Go</button></form></div>"), "Body")
    }

    func testYouTubeEmbed() {
        XCTAssertEqual(md(#"<iframe src="https://www.youtube.com/embed/dQw4w9WgXcQ?si=x"></iframe>"#), "![](https://www.youtube.com/watch?v=dQw4w9WgXcQ)")
        XCTAssertEqual(HTMLToMarkdown.youTubeID("https://youtu.be/abc"), "abc")
    }

    func testHighlightedCodeKeepsLineBreaksBetweenSpans() {
        let html = "<pre><code><span>a</span>\n<span>  b</span></code></pre>"
        XCTAssertEqual(md(html), "```\na\n  b\n```")
    }

    func testTagSoupFallsBackToTidy() {
        let out = md("<p>Caf&eacute; &amp; bar<br>next line<p>Para two")
        XCTAssertTrue(out.contains("Café & bar\nnext line"), out)
        XCTAssertTrue(out.contains("Para two"), out)
    }

    func testFigureCaption() {
        XCTAssertEqual(md(#"<figure><img src="https://e.com/a.png" alt="A"/><figcaption>The caption</figcaption></figure>"#),
                       "![A](https://e.com/a.png)\n\n*The caption*")
    }
}

final class WebClipTests: XCTestCase {
    func testRequestParsing() {
        let u = URL(string: "onyx://clip?url=https%3A%2F%2Fex.com%2Fa&title=Hi%20there&selection=%3Cp%3Ex%3C%2Fp%3E&folder=Inbox")!
        let r = WebClip.request(from: u)
        XCTAssertEqual(r?.url, "https://ex.com/a")
        XCTAssertEqual(r?.title, "Hi there")
        XCTAssertEqual(r?.selection, "<p>x</p>")
        XCTAssertEqual(r?.folder, "Inbox")
        XCTAssertEqual(r?.needsFetch, false)
        XCTAssertEqual(WebClip.request(from: URL(string: "onyx://clip?url=https://ex.com")!)?.needsFetch, true)
        XCTAssertNotNil(WebClip.request(from: URL(string: "onyx:///clip?text=hello")!))
        XCTAssertNil(WebClip.request(from: URL(string: "onyx://vault/Notes.md")!))
        XCTAssertNil(WebClip.request(from: URL(string: "onyx://clip")!))
        XCTAssertNil(WebClip.Request(url: "file:///etc/passwd").webURL)
    }

    func testAuthors() {
        XCTAssertEqual(WebClip.authors("By Jane Doe and John Roe"), ["Jane Doe", "John Roe"])
        XCTAssertEqual(WebClip.authors("Jane Doe, John Roe | March 3, 2024"), ["Jane Doe", "John Roe"])
        XCTAssertEqual(WebClip.authors(nil), [])
    }

    func testDates() {
        XCTAssertEqual(WebClip.normalizedDate("2026-05-17T10:00:00Z"), "2026-05-17")
        XCTAssertEqual(WebClip.normalizedDate("March 3, 2024"), "2024-03-03")
        XCTAssertNil(WebClip.normalizedDate("last week"))
    }

    func testFileNames() {
        let d = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(WebClip.fileName(title: "Chesed | Thelemapedia", url: nil, date: d), "Chesed Thelemapedia.md")
        XCTAssertEqual(WebClip.fileName(title: "Swift: a tour?", url: nil, date: d), "Swift - a tour.md")
        XCTAssertEqual(WebClip.fileName(title: "", url: "https://www.ex.com/x", date: d, timeZone: TimeZone(identifier: "UTC")!), "ex.com 1970-01-01 0000.md")
        XCTAssertLessThanOrEqual(WebClip.fileName(title: String(repeating: "word ", count: 60), url: nil, date: d).count, 124)
    }

    func testConventions() {
        let fms = ["---\nclass: Index\ntags: [clippings]\n---", "---\nclass: Source\ntags: [library/article]\n---",
                   "---\nclass: Source\ntags: [library/article]\n---", "---\nclass: Concept\n---"].map(Frontmatter.parse)
        let c = WebClip.conventions(frontmatters: fms)
        XCTAssertEqual(c.noteClass, "Source")
        XCTAssertEqual(c.tags, ["library/article"])
        XCTAssertEqual(WebClip.tagList("#a, b c"), ["a", "b", "c"])
    }

    func testDefaultNote() {
        let page = WebClip.Page(url: "https://ex.com/a", title: "A \"quoted\" title", authors: ["Jane"], published: "2026-05-17T00:00:00Z",
                                description: "Desc", site: "Ex", html: "")
        let utc = TimeZone(identifier: "UTC")!
        let note = WebClip.note(page: page, markdown: "# A quoted title\n\nBody", noteClass: "Source", tags: ["library/article"],
                                clipped: Date(timeIntervalSince1970: 86400 * 365), timeZone: utc)
        XCTAssertEqual(note, """
        ---
        title: "A \\"quoted\\" title"
        source: "https://ex.com/a"
        author: ["Jane"]
        published: 2026-05-17
        created: 1971-01-01
        description: "Desc"
        site: "Ex"
        tags: [library/article]
        class: Source
        ---

        # A "quoted" title

        Body

        """)
        let fm = Frontmatter.parse(note)
        XCTAssertEqual(fm["class"]?.display, "Source")
        XCTAssertEqual(fm["source"]?.display, "https://ex.com/a")
    }

    func testTemplateNote() {
        let page = WebClip.Page(url: "https://ex.com", title: "T", html: "")
        let out = WebClip.note(page: page, markdown: "Body", noteClass: "Source", tags: ["x"],
                               template: "---\nsource: {{url}}\ntags: [{{tags}}]\n---\n> clipped {{date}}\n",
                               clipped: Date(timeIntervalSince1970: 0), timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(out, "---\nsource: https://ex.com\ntags: [x]\n---\n> clipped 1970-01-01\n\nBody\n")
        let withContent = WebClip.note(page: page, markdown: "Body", noteClass: "", tags: [], template: "# {{title}}\n{{content}}\nend",
                                       clipped: Date(), timeZone: .current)
        XCTAssertEqual(withContent, "# T\nBody\nend\n")
    }

    func testBookmarklet() {
        XCTAssertTrue(WebClip.bookmarklet.hasPrefix("javascript:"))
        XCTAssertFalse(WebClip.bookmarklet.contains(" "))
        XCTAssertFalse(WebClip.bookmarklet.contains("%20'") && !WebClip.bookmarklet.contains("%2520"))
        let src = WebClip.bookmarkletSource
        XCTAssertTrue(src.contains("onyx://clip?"))
        XCTAssertTrue(src.contains("XMLSerializer"))
        XCTAssertTrue(src.contains("'%20'"))
    }

    /// docs/web-clipper.md carries the bookmarklet for copy-and-paste; keep it current.
    func testDocsCarryCurrentBookmarklet() throws {
        let docs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/web-clipper.md")
        let text = try String(contentsOf: docs, encoding: .utf8)
        XCTAssertTrue(text.contains(WebClip.bookmarklet), "update the bookmarklet in docs/web-clipper.md")
    }
}

final class ClipURLTests: XCTestCase {
    func testRoundTripsThroughRequestParsing() {
        let fields: [String: Any] = ["url": "https://ex.com/a?b=1&c=2#x", "title": "A + B & C = D", "selection": "<p>x &amp; y</p>",
                                     "author": "", "site": "  Ex  ", "ignored": "z", "published": 3]
        let url = ClipURL.make(fields)!
        XCTAssertFalse(url.absoluteString.contains("ignored"))
        XCTAssertFalse(url.absoluteString.contains("author="))
        let r = WebClip.request(from: url)
        XCTAssertEqual(r?.url, "https://ex.com/a?b=1&c=2#x")
        XCTAssertEqual(r?.title, "A + B & C = D")
        XCTAssertEqual(r?.selection, "<p>x &amp; y</p>")
        XCTAssertEqual(r?.site, "Ex")
        XCTAssertNil(r?.published)
    }

    func testNothingToClip() {
        XCTAssertNil(ClipURL.make(["title": "Only a title"]))
        XCTAssertNotNil(ClipURL.make(["text": "Some text"]))
    }
}
