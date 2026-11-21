import XCTest
@testable import OnyxCore

final class RelationshipsTests: XCTestCase {
    func snapshot(_ files: [String: String]) -> VaultSnapshot {
        var snap = VaultSnapshot(root: URL(fileURLWithPath: "/tmp/none"))
        for (p, c) in files { snap.notes[p] = VaultSnapshot.makeRecord(rel: p, content: c) }
        snap.rebuildDerived()
        return snap
    }

    func testAncestryChainRootFirst() {
        let s = snapshot([
            "Medication.md": "# Medication",
            "SSRI.md": "partOf:: [[Medication]]",
            "Sertraline.md": "---\nclass: Medication\ndrugClass: SSRI\n---\npartOf:: [[SSRI]]\ntreats:: [[Anxiety]]",
            "Anxiety.md": "# Anxiety",
        ])
        let a = s.ancestry(of: "Sertraline.md")
        XCTAssertEqual(a.chain, ["Medication.md", "SSRI.md"])
        XCTAssertTrue(a.otherParents.isEmpty); XCTAssertFalse(a.cycle)
        XCTAssertEqual(s.ancestry(of: "Medication.md").chain, [])
        XCTAssertEqual(s.noteClass("Sertraline.md"), "Medication")
        XCTAssertNil(s.noteClass("SSRI.md"))
    }

    func testCyclesStopAndAreFlagged() {
        let s = snapshot(["A.md": "partOf:: B", "B.md": "partOf:: C", "C.md": "partOf:: A", "Self.md": "partOf:: Self"])
        let a = s.ancestry(of: "A.md")
        XCTAssertEqual(a.chain, ["C.md", "B.md"]); XCTAssertTrue(a.cycle)
        XCTAssertEqual(s.ancestry(of: "Self.md").chain, [])   // self-links are not indexed
        let tree = Ancestry.partsTree(of: "A.md", parts: { s.parts(of: $0) })
        XCTAssertEqual(tree.map(\.path), ["C.md"])
        XCTAssertEqual(tree[0].children.map(\.path), ["B.md"])
        XCTAssertEqual(tree[0].children[0].children.map(\.path), ["A.md"])
        XCTAssertTrue(tree[0].children[0].children[0].cycle)
        XCTAssertEqual(Ancestry.descendantCount(of: "A.md", parts: { s.parts(of: $0) }), 2)
    }

    func testMultipleParents() {
        let s = snapshot(["Alpha.md": "", "Beta.md": "", "Root.md": "", "Child.md": "partOf:: Beta, [[Alpha]]"])
        var t = s; t.notes["Alpha.md"] = VaultSnapshot.makeRecord(rel: "Alpha.md", content: "partOf:: Root"); t.rebuildDerived()
        let a = t.ancestry(of: "Child.md")
        XCTAssertEqual(a.chain, ["Root.md", "Alpha.md"])   // first parent by path
        XCTAssertEqual(a.otherParents, ["Beta.md"])
        let tree = Ancestry.partsTree(of: "Root.md", parts: { t.parts(of: $0) })
        XCTAssertEqual(tree.map(\.path), ["Alpha.md"]); XCTAssertEqual(tree[0].children.map(\.path), ["Child.md"])
        XCTAssertEqual(t.parts(of: "Beta.md"), ["Child.md"])   // shows under each parent
    }

    func testDepthLimitCountsHidden() {
        let s = snapshot(["R.md": "", "A.md": "partOf:: R", "B.md": "partOf:: A", "C.md": "partOf:: B"])
        let tree = Ancestry.partsTree(of: "R.md", parts: { s.parts(of: $0) }, maxDepth: 2)
        XCTAssertEqual(tree[0].children.map(\.path), ["B.md"])
        XCTAssertEqual(tree[0].children[0].hidden, 1)
    }

    func testFieldRelationsBothDirections() {
        let s = snapshot([
            "Sertraline.md": "partOf:: SSRI\ntreats:: [[Anxiety]], [[Depression]]\ndose:: 50mg",
            "Anxiety.md": "seeAlso:: [[Sertraline]]",
            "Depression.md": "", "SSRI.md": "",
        ])
        let r = s.fieldRelations(of: "Sertraline.md")
        XCTAssertEqual(r.map(\.key), ["seeAlso", "treats"])
        XCTAssertEqual(r[1].outgoing, ["Anxiety.md", "Depression.md"])
        XCTAssertEqual(r[0].incoming, ["Anxiety.md"])
        let back = s.fieldRelations(of: "Anxiety.md")
        XCTAssertEqual(back.first(where: { $0.kind == "treats" })?.incoming, ["Sertraline.md"])
        XCTAssertTrue(s.linkValuedKinds().contains("treats"))
        XCTAssertFalse(s.linkValuedKinds().contains("dose"))
        XCTAssertEqual(Set(s.fieldKeys().map(\.key)), ["partOf", "treats", "dose", "seeAlso"])
    }

    func testFieldCompletionContexts() {
        XCTAssertEqual(FieldCompletion.context(line: "part:", caret: 5), .init(queryStart: 0, replaceEnd: 5, query: "part", part: .key))
        XCTAssertEqual(FieldCompletion.context(line: "- part:", caret: 7)?.queryStart, 2)
        XCTAssertNil(FieldCompletion.context(line: "some prose part:", caret: 16))
        XCTAssertNil(FieldCompletion.context(line: "part: x", caret: 5))           // text after the caret
        XCTAssertNil(FieldCompletion.context(line: "partOf::", caret: 8))          // no space yet
        XCTAssertEqual(FieldCompletion.context(line: "partOf:: ", caret: 9), .init(queryStart: 9, replaceEnd: 9, query: "", part: .value(key: "partOf")))
        XCTAssertEqual(FieldCompletion.context(line: "partOf:: [[A]], Me", caret: 18)?.query, "Me")
        XCTAssertEqual(FieldCompletion.context(line: "partOf:: [[A]], Me", caret: 18)?.queryStart, 16)
        XCTAssertNil(FieldCompletion.context(line: "partOf:: [[Me", caret: 13))      // the [[ popup owns this
        let keys = [(key: "partOf", count: 9), (key: "part", count: 1), (key: "related", count: 4)]
        let k = FieldCompletion.keySuggestions("part", keys: keys)
        XCTAssertEqual(k.map(\.key), ["part", "partOf"]); XCTAssertTrue(k[0].exact)
        XCTAssertEqual(FieldCompletion.keySuggestions("pa", keys: keys).map(\.key), ["partOf", "part"])
        XCTAssertTrue(FieldCompletion.keySuggestions("x", keys: keys).isEmpty)
    }

    func testHierarchyFocusLayout() {
        let s = snapshot(["R.md": "", "A.md": "partOf:: R\n[[X]]", "B.md": "partOf:: A", "X.md": "[[A]]", "C.md": "partOf:: R"])
        let g = GraphIndex.build(s)
        let a = g.index["A.md"]!
        XCTAssertEqual(Set(g.parts[g.index["R.md"]!]), [a, g.index["C.md"]!])
        let all = Set(FocusLayout.layout(g, center: a).map(\.node))
        XCTAssertTrue(all.contains(g.index["X.md"]!))
        let h = FocusLayout.layout(g, center: a, hierarchy: true)
        XCTAssertEqual(Set(h.filter { $0.ring == 1 }.map(\.node)), [g.index["R.md"]!, g.index["B.md"]!])
        XCTAssertEqual(Set(h.filter { $0.ring == 2 }.map(\.node)), [g.index["C.md"]!])   // sibling via the parent
        XCTAssertTrue(h.first { $0.node == g.index["R.md"]! }!.outgoing)
    }
}
