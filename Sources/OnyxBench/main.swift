import Foundation
import OnyxCore

// onyx-bench: times the vault work Onyx does on launch, while typing, and when switching notes.
// Usage: swift run -c release onyx-bench /path/to/COPY/of/vault [iterations]
// It only reads files, but point it at a copy of your vault anyway (see docs/performance.md).
// ONYX_BENCH_JSON=/path.json also writes the timings as JSON.

let args = CommandLine.arguments
guard args.count > 1 else { print("usage: onyx-bench <vault-copy> [iterations]"); exit(2) }
let root = URL(fileURLWithPath: args[1]).standardizedFileURL
let iters = args.count > 2 ? Int(args[2]) ?? 5 : 5

var results: [(String, Double)] = []
@discardableResult
func bench<T>(_ name: String, _ n: Int = iters, _ body: () -> T) -> T {
    var best = Double.infinity
    var out: T! = nil
    for _ in 0..<max(1, n) {
        let t0 = DispatchTime.now().uptimeNanoseconds
        out = body()
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
        best = min(best, ms)
    }
    results.append((name, best))
    print(name.padding(toLength: 48, withPad: " ", startingAt: 0) + String(format: "%10.2f ms", best))
    return out
}

let snap = bench("cold open: VaultSnapshot.scan", 3) { VaultSnapshot.scan(root: root) }
print("  notes=\(snap.notes.count) attachments=\(snap.attachments.count) folders=\(snap.folders.count)")

// The biggest note and the most linked-to note.
let big = snap.notes.values.max { $0.content.utf16.count < $1.content.utf16.count }!
let hub = snap.backlinks.max { $0.value.count < $1.value.count }!.key
print("  biggest=\(big.path) (\(big.content.utf16.count) chars)  hub=\(hub) (\(snap.backlinks[hub]!.count) backlinks)")
let edited = snap.notes.keys.sorted()[snap.notes.count / 2]

bench("save one note: snapshot.update (rebuild)") { var s = snap; s.update(path: edited, content: snap.notes[edited]!.content + "\nx"); return s.notes.count }
bench("watcher: refresh(paths: 1 file)") { var s = snap; s.refresh(paths: [edited]); return s.notes.count }
let churn = Array(snap.notes.keys.sorted().prefix(50))
bench("watcher churn: 50 files, one batch") { var s = snap; s.refresh(paths: churn); return s.notes.count }
bench("watcher churn: 50 files, 50 batches", 1) { var s = snap; for p in churn { s.refresh(paths: [p]) }; return s.notes.count }
bench("full rebuildDerived") { var s = snap; s.rebuildDerived(); return s.notes.count }
bench("sidebar: buildTree") { snap.buildTree() }
bench("sidebar: TreeDates") { TreeDates(snap) }
bench("quick switcher: QuickIndex build") { QuickIndex(snap) }
let qi = QuickIndex(snap)
bench("quick switcher: search \"con\"") { qi.search("con") }

// Typing in the biggest note: what runs per keystroke.
let text = big.content
bench("keystroke: summarize(biggest)") { NoteParser.summarize(text) }
bench("keystroke: countWords(biggest)") { NoteParser.countWords(text) }
bench("keystroke: parseHeadings(biggest)") { NoteParser.parseHeadings(text) }
bench("keystroke: codeRanges(biggest)") { NoteParser.codeRanges(text) }
bench("keystroke: InlineFields.parse(biggest)") { InlineFields.parse(text) }
bench("keystroke: Frontmatter.parse(biggest)") { Frontmatter.parse(text) }
let listRe = #"^\s*([-*+]|\d+[.)])\s"#
bench("keystroke: per-line list regex(biggest)") { () -> Int in
    var n = 0
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) where String(line).range(of: listRe, options: .regularExpression) != nil { n += 1 }
    return n
}
let open = snap.notes.values.filter { $0.content.utf16.count > 2000 }.sorted { $0.path < $1.path }.first!
bench("open note: summarize(typical)") { NoteParser.summarize(open.content) }

bench("search: \"consciousness\"") { snap.search("consciousness") }
bench("search: \"the\"") { snap.search("the") }
bench("search: two terms \"system memory\"") { snap.search("system memory") }
bench("inspector: backlinks(to: hub)") { snap.backlinks(to: hub) }
bench("reader: linkedMentions(to: hub)") { snap.linkedMentions(to: hub) }
bench("inspector: unlinkedMentions(of: hub)") { snap.unlinkedMentions(of: hub) }
bench("inspector: RelationGraph(hub)") { RelationGraph.build(snap, center: hub) }
let g = bench("graph: GraphIndex.build") { GraphIndex.build(snap) }
bench("graph: Atlas.build (folders)", 2) { Atlas.build(g, grouping: .folders, include: { _ in true }, includeOrphans: false) }
bench("graph: GraphData.build") { GraphData.build(snap) }

let dvQueries = [
    "LIST FROM \"System 777\" WHERE type = \"alter\"",
    "TABLE file.mtime, length(file.inlinks) AS links SORT file.mtime DESC LIMIT 50",
    "TABLE WITHOUT ID file.link AS \"Article\", author, date FROM \"Clippings\" SORT date DESC",
    "TASK WHERE !completed",
    "LIST FROM \"System 777\"",
    "LIST WHERE type = \"alter\"",
]
for q in dvQueries {
    let rows = bench("dataview: \(q.prefix(34))…") { (try? Dataview.run(q, in: snap, from: hub))?.rows.count ?? -1 }
    if rows < 0 { print("  (query failed to parse)") }
}
let bases = snap.bases.sorted { $0.key < $1.key }
for (p, y) in bases.prefix(3) {
    let f = Bases.parse(y)
    bench("bases: \((p as NSString).lastPathComponent)") { Bases.run(f, view: 0, in: snap, from: p).rows.count }
}

if let out = ProcessInfo.processInfo.environment["ONYX_BENCH_JSON"] {
    let d = Dictionary(results.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
    try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys, .prettyPrinted]).write(to: URL(fileURLWithPath: out))
}
// ONYX_BENCH_SCAN=1: where cold-open parsing time goes, one parser at a time (serial).
if ProcessInfo.processInfo.environment["ONYX_BENCH_SCAN"] != nil {
    let notes = Array(snap.notes.values)
    bench("scan part: summarize all (serial)", 1) { notes.reduce(0) { $0 + NoteParser.summarize($1.content).links.count } }
    bench("scan part: lowercased all (serial)", 1) { notes.reduce(0) { $0 + $1.content.lowercased().utf8.count } }
    bench("scan part: InlineFields all (serial)", 1) { notes.reduce(0) { $0 + InlineFields.parse($1.content).count } }
    bench("scan part: codeRanges all (serial)", 1) { notes.reduce(0) { $0 + NoteParser.codeRanges($1.content).count } }
    bench("scan part: headings all (serial)", 1) { notes.reduce(0) { $0 + NoteParser.parseHeadings($1.content).count } }
    bench("scan part: words all (serial)", 1) { notes.reduce(0) { $0 + NoteParser.countWords($1.content) } }
    bench("scan part: frontmatter all (serial)", 1) { notes.reduce(0) { $0 + Frontmatter.parse($1.content).properties.count } }
    bench("scan part: read files (serial)", 1) { notes.reduce(0) { $0 + ((try? Data(contentsOf: root.appendingPathComponent($1.path)))?.count ?? 0) } }
}
