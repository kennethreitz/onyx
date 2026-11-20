import XCTest
@testable import OnyxCore

final class InlineFieldsTests: XCTestCase {
    func testParsesInlineFrontmatterAndListsWithExactRanges() {
        let text = "---\npartOf: \"[[Knowledge]]\"\nrelated:\n  - Alpha\n  - \"[[Beta|B]]\"\nrating: 5\n---\n# Note\n" +
            "partOf:: Knowledge, [[Area/Mythology|Myth]]\n- related:: Gamma, [[Delta]]\nscore:: 3\nText [relatesTo:: Epsilon] and (correspondsTo:: [[Zeta]]).\n`partOf:: Code`\n```\npartOf:: Fenced\n```\n"
        let fs = InlineFields.parse(text)
        XCTAssertEqual(fs.map(\.key), ["partOf", "related", "related", "partOf", "related", "score", "relatesTo", "correspondsTo"])
        let links = fs.flatMap(\.links)
        XCTAssertEqual(links.map(\.target), ["Knowledge", "Alpha", "Beta", "Knowledge", "Area/Mythology", "Gamma", "Delta", "Epsilon", "Zeta"])
        XCTAssertEqual(links.map(\.isBare), [false, true, false, true, false, true, false, true, false])
        let ns = text as NSString
        for l in links where l.isBare { XCTAssertEqual(ns.substring(with: l.range), l.target) }
        XCTAssertEqual(fs.first { $0.key == "score" }?.links.count, 0)   // non-relation prose stays a value
    }

    func testEmojiValuesDoNotCrash() {
        let fs = InlineFields.parse("partOf:: 🜍 Alchemy 🜔, [[Salt 🧂]]\nmood:: 🙂\n")
        XCTAssertEqual(fs.first?.links.map(\.target), ["🜍 Alchemy 🜔", "Salt 🧂"])
    }

    func snapshot() -> VaultSnapshot {
        var snap = VaultSnapshot(root: URL(fileURLWithPath: "/tmp/none"))
        let files = [
            "Knowledge/Knowledge.md": "# Knowledge",
            "Knowledge/Alchemy/Alchemy.md": "[[Knowledge]] [[Psychology]]\npartOf:: Knowledge\nrelated:: [[Psychology]]",
            "Knowledge/Alchemy/Jung.md": "partOf:: [[Knowledge/Alchemy/Alchemy|Alchemy]]",
            "Knowledge/Alchemy/Salt.md": "---\npartOf: \"[[Alchemy]]\"\n---\nbody",
            "Psychology.md": "# Psychology",
            "Loose.md": "partOf:: Missing Parent",
        ]
        for (p, c) in files { snap.notes[p] = VaultSnapshot.makeRecord(rel: p, content: c) }
        snap.rebuildDerived()
        return snap
    }

    func testRelationshipIndexesBacklinksAndGraphKinds() {
        let snap = snapshot()
        XCTAssertEqual(snap.parents(of: "Knowledge/Alchemy/Alchemy.md"), ["Knowledge/Knowledge.md"])
        XCTAssertEqual(snap.parts(of: "Knowledge/Alchemy/Alchemy.md"), ["Knowledge/Alchemy/Jung.md", "Knowledge/Alchemy/Salt.md"])
        XCTAssertEqual(snap.siblings(of: "Knowledge/Alchemy/Jung.md"), ["Knowledge/Alchemy/Salt.md"])
        XCTAssertEqual(snap.related(to: "Psychology.md"), ["Knowledge/Alchemy/Alchemy.md"])   // symmetric display
        XCTAssertEqual(snap.backlinks["Knowledge/Knowledge.md"], ["Knowledge/Alchemy/Alchemy.md"])
        XCTAssertEqual(snap.unresolved["Missing Parent"], ["Loose.md"])
        XCTAssertEqual(snap.backlinks(to: "Knowledge/Knowledge.md").first?.source, "Knowledge/Alchemy/Alchemy.md")
        let g = GraphIndex.build(snap)
        let a = g.index["Knowledge/Alchemy/Alchemy.md"]!, k = g.index["Knowledge/Knowledge.md"]!, p = g.index["Psychology.md"]!
        XCTAssertEqual(g.edgeKind(a, k), .partOf); XCTAssertEqual(g.edgeKind(p, a), .related)
    }

    func testRelationGraphRoles() {
        let snap = snapshot()
        let rg = RelationGraph.build(snap, center: "Knowledge/Alchemy/Alchemy.md")
        XCTAssertEqual(rg.nodes.first?.role, .center)
        XCTAssertEqual(Set(rg.nodes.filter { $0.role == .parent }.map(\.path)), ["Knowledge/Knowledge.md"])
        XCTAssertEqual(Set(rg.nodes.filter { $0.role == .part }.map(\.path)), ["Knowledge/Alchemy/Jung.md", "Knowledge/Alchemy/Salt.md"])
        XCTAssertEqual(rg.nodes.filter { $0.role == .related }.map(\.path), ["Psychology.md"])
        XCTAssertTrue(rg.nodes.filter { $0.role == .parent }.allSatisfy { $0.y < 0 })
        XCTAssertTrue(rg.nodes.filter { $0.role == .part }.allSatisfy { $0.y > 0 })
    }

    func testDataviewReadsInlineFieldsAsLinks() throws {
        let snap = snapshot()
        let r = try Dataview.run("TABLE partOf FROM \"Knowledge/Alchemy\" SORT file.name ASC", in: snap)
        XCTAssertEqual(r.rows.first?.last?.text, "Knowledge")
    }
}

/// Read-only smoke check against a real vault: `ONYX_BENCH_VAULT=~/Notes swift test --filter RealVault`.
final class RealVaultFieldsTests: XCTestCase {
    func testRealVaultFields() throws {
        guard let v = ProcessInfo.processInfo.environment["ONYX_BENCH_VAULT"] else { throw XCTSkip("set ONYX_BENCH_VAULT") }
        let t = Date()
        let snap = VaultSnapshot.scan(root: URL(fileURLWithPath: v))
        let fields = snap.notes.values.flatMap(\.summary.fields)
        var kinds: [String: Int] = [:]
        for f in fields { kinds[f.kind, default: 0] += 1 }
        let partOf = snap.relationsOut.values.reduce(0) { $0 + ($1["partof"]?.count ?? 0) }
        let unresolved = snap.notes.values.flatMap { n in n.summary.links.filter { $0.fieldKey.map(InlineField.kind) == "partof" && snap.resolve($0.target, from: n.path) == nil } }.count
        print("[bench] notes=\(snap.notes.count) scan=\(Int(Date().timeIntervalSince(t) * 1000))ms fields=\(kinds.sorted { $0.value > $1.value }.prefix(8)) resolvedPartOf=\(partOf) unresolvedPartOf=\(unresolved)")
    }
}
