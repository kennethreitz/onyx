import XCTest
@testable import OnyxCore

final class CanvasTests: XCTestCase {
    /// Every JSON Canvas feature, written the way Obsidian writes it (tabs, one item per line,
    /// no trailing newline), plus fields Onyx doesn't know about.
    static let sample = """
    {
    \t"nodes":[
    \t\t{"id":"g1","type":"group","x":-420,"y":-300,"width":900,"height":620,"color":"6","label":"Group “one”","background":"img/bg.png","backgroundStyle":"cover"},
    \t\t{"id":"6f0ad84f44ce95a3","type":"text","text":"# Title\\n\\nA [[Linked Note|alias]] and \\"quotes\\" \\\\ tabs\\tand emoji 🜍 \\u0001","x":-380,"y":-240,"width":250,"height":120.5,"color":"#a4c2f4","customField":{"nested":[1,2.5e3,true,null]}},
    \t\t{"id":"f1","type":"file","file":"Notes/Linked Note.md","subpath":"#Heading","x":0,"y":-240,"width":400,"height":400},
    \t\t{"id":"img","type":"file","file":"img/pic.png","x":0,"y":200,"width":300,"height":200,"color":"3"},
    \t\t{"id":"l1","type":"link","url":"https://jsoncanvas.org","x":-380,"y":0,"width":250,"height":80}
    \t],
    \t"edges":[
    \t\t{"id":"e1","fromNode":"6f0ad84f44ce95a3","fromSide":"right","fromEnd":"none","toNode":"f1","toSide":"left","toEnd":"arrow","color":"1","label":"see"},
    \t\t{"id":"e2","fromNode":"f1","fromSide":"bottom","toNode":"img","toSide":"top","fromEnd":"arrow","toEnd":"none"}
    \t],
    \t"metadata":{"version":"1.0-1.0","frontmatter":{}}
    }
    """

    func testRoundTripIsByteIdentical() throws {
        let v = try CanvasFile.parse(Self.sample)
        XCTAssertEqual(CanvasFile.format(v), Self.sample)
        // unknown fields and key order survive
        let n = v["nodes"]!.array![1]
        if case .object(let kv) = n { XCTAssertEqual(kv.map(\.0), ["id", "type", "text", "x", "y", "width", "height", "color", "customField"]) } else { XCTFail() }
        XCTAssertEqual(n["text"]?.string?.contains("🜍"), true)
        XCTAssertEqual(n["height"]?.double, 120.5)
    }

    func testNormalizesJSONStringifyOutput() throws {
        // what the canvas page posts: JSON.stringify(doc), compact
        let compact = try JSONValue.parse(Self.sample).compact
        XCTAssertFalse(compact.contains("\n\t"))
        XCTAssertEqual(try CanvasFile.normalize(compact), Self.sample)
    }

    func testEmptyFileIsAnEmptyCanvas() throws {
        XCTAssertEqual(CanvasFile.format(try CanvasFile.parse("")), "{\n\t\"nodes\":[],\n\t\"edges\":[]\n}")
        XCTAssertEqual(CanvasFile.format(try CanvasFile.parse("{}")), "{}")
    }

    func testRejectsBrokenJSON() {
        XCTAssertThrowsError(try JSONValue.parse("{\"nodes\":[}"))
        XCTAssertThrowsError(try JSONValue.parse("{} x"))
    }

    func testSummaryCollectsFileCardsAndTextLinks() {
        let s = CanvasFile.summarize(Self.sample)
        XCTAssertEqual(s.files, ["Notes/Linked Note.md", "img/pic.png"])
        XCTAssertEqual(s.links, ["Linked Note"])
        XCTAssertEqual(s.nodeCount, 5); XCTAssertEqual(s.edgeCount, 2)
    }

    func testRewriteFilesTouchesOnlyFileValues() throws {
        let out = CanvasFile.rewriteFiles(Self.sample) { $0 == "Notes/Linked Note.md" ? "Archive/Linked Note.md" : nil }
        XCTAssertEqual(out, Self.sample.replacingOccurrences(of: "\"file\":\"Notes/Linked Note.md\"", with: "\"file\":\"Archive/Linked Note.md\""))
        XCTAssertNil(CanvasFile.rewriteFiles(Self.sample) { _ in nil })
    }

    func testVaultIndexesCanvasLinksAsBacklinks() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("onyx-canvas-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Notes"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "# Linked".write(to: dir.appendingPathComponent("Notes/Linked Note.md"), atomically: true, encoding: .utf8)
        try Self.sample.write(to: dir.appendingPathComponent("Board.canvas"), atomically: true, encoding: .utf8)
        var snap = VaultSnapshot.scan(root: dir)
        XCTAssertNotNil(snap.canvases["Board.canvas"])
        XCTAssertEqual(snap.canvasLinks["Board.canvas"], ["Notes/Linked Note.md"])
        XCTAssertEqual(snap.backlinks["Notes/Linked Note.md"], ["Board.canvas"])
        XCTAssertEqual(snap.backlinks(to: "Notes/Linked Note.md").first?.source, "Board.canvas")
        let g = GraphIndex.build(snap)
        let ci = try XCTUnwrap(g.index["Board.canvas"]), ni = try XCTUnwrap(g.index["Notes/Linked Note.md"])
        XCTAssertEqual(g.out[ci], [ni]); XCTAssertEqual(g.names[ci], "Board")
        XCTAssertTrue(QuickIndex(snap).search("board").contains { $0.entry.path == "Board.canvas" })
        snap.update(path: "Board.canvas", content: "{}")
        XCTAssertNil(snap.backlinks["Notes/Linked Note.md"])
    }

    /// Kenneth's real canvases (copies, never ~/Notes): parse → write is byte-identical.
    /// Point ONYX_CANVAS_FIXTURES at a folder of copies; skipped when it isn't there.
    func testRealCanvasesRoundTrip() throws {
        let root = ProcessInfo.processInfo.environment["ONYX_CANVAS_FIXTURES"] ?? "/tmp/onyx-canvas-vault"
        guard let en = FileManager.default.enumerator(atPath: root) else { throw XCTSkip("no canvas fixtures at \(root)") }
        var n = 0
        for case let rel as String in en where rel.hasSuffix(".canvas") {
            let text = try String(contentsOfFile: root + "/" + rel, encoding: .utf8)
            let v = try CanvasFile.parse(text)
            XCTAssertEqual(CanvasFile.format(v), text, rel)
            XCTAssertEqual(try CanvasFile.normalize(v.compact), text, rel)
            n += 1
        }
        if n == 0 { throw XCTSkip("no .canvas files under \(root)") }
        print("[canvas] \(n) real canvases round-tripped")
    }
}
