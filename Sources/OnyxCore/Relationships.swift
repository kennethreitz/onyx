import Foundation

/// `partOf::` hierarchy walks, kept pure so cycles and multiple parents are testable.
public enum Ancestry {
    /// The primary ancestry of `start`, root-most first and ending at its direct parent.
    /// Each step follows the first parent `parents` returns; a cycle or `maxDepth` stops the walk
    /// (`cycle` is true when a note repeats). `start` itself is never part of the chain.
    public static func chain(of start: String, parents: (String) -> [String], maxDepth: Int = 12) -> (chain: [String], cycle: Bool) {
        var seen: Set<String> = [start], out: [String] = [], cur = start, cycle = false
        while out.count < maxDepth, let next = parents(cur).first(where: { $0 != cur }) {
            if !seen.insert(next).inserted { cycle = true; break }
            out.append(next); cur = next
        }
        return (out.reversed(), cycle)
    }

    /// One node of a parts tree. `cycle` marks a part that is already an ancestor in this branch.
    public struct Node: Equatable, Sendable {
        public var path: String
        public var children: [Node]
        public var cycle: Bool
        /// Parts cut off by `maxDepth` (only counted at the last level).
        public var hidden: Int
    }

    /// The tree of parts below `root`, cycle-safe: a note that is its own ancestor in a branch
    /// appears once more with `cycle` set and no children. A note with several parents shows
    /// under each of them.
    public static func partsTree(of root: String, parts: (String) -> [String], maxDepth: Int = 6) -> [Node] {
        func walk(_ p: String, _ path: Set<String>, _ depth: Int) -> [Node] {
            parts(p).map { c in
                if path.contains(c) { return Node(path: c, children: [], cycle: true, hidden: 0) }
                if depth >= maxDepth { return Node(path: c, children: [], cycle: false, hidden: parts(c).count) }
                return Node(path: c, children: walk(c, path.union([c]), depth + 1), cycle: false, hidden: 0)
            }
        }
        return walk(root, [root], 1)
    }

    /// Every descendant of `root` (cycle-safe), for counts.
    public static func descendantCount(of root: String, parts: (String) -> [String]) -> Int {
        var seen: Set<String> = [root], stack = [root]
        while let p = stack.popLast() { for c in parts(p) where seen.insert(c).inserted { stack.append(c) } }
        return seen.count - 1
    }
}

/// A link-valued inline field other than the built-in hierarchy keys, e.g. `treats:: [[Anxiety]]`.
public struct FieldRelation: Equatable, Sendable {
    public var kind: String        // InlineField.kind
    public var key: String         // as written (first spelling seen)
    public var outgoing: [String]  // notes this note points to with the key
    public var incoming: [String]  // notes pointing here with the key
}

extension VaultSnapshot {
    /// Kinds shown by the dedicated Part of / Parts / Related rows.
    public static let builtInRelationKinds: Set<String> = ["partof", "related", "relatesto"]

    /// Other link-valued fields of `path`, both directions, grouped by key and sorted by key.
    public func fieldRelations(of path: String) -> [FieldRelation] {
        var spelling: [String: String] = [:]
        func learn(_ p: String) {
            for f in notes[p]?.summary.fields ?? [] where spelling[f.kind] == nil { spelling[f.kind] = f.key }
        }
        learn(path)
        var kinds = Set((relationsOut[path] ?? [:]).keys).union((relationsIn[path] ?? [:]).keys)
        kinds.subtract(Self.builtInRelationKinds)
        var out: [FieldRelation] = []
        for k in kinds {
            let o = (relationsOut[path]?[k] ?? []).subtracting([path]).sorted()
            let i = (relationsIn[path]?[k] ?? []).subtracting([path]).sorted()
            guard !o.isEmpty || !i.isEmpty else { continue }
            if spelling[k] == nil { i.forEach(learn) }
            out.append(FieldRelation(kind: k, key: spelling[k] ?? k, outgoing: o, incoming: i))
        }
        return out.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }

    /// Primary `partOf` ancestry (root-most first) and any other direct parents.
    public func ancestry(of path: String) -> (chain: [String], otherParents: [String], cycle: Bool) {
        let a = Ancestry.chain(of: path, parents: { parents(of: $0) })
        let direct = parents(of: path).filter { $0 != path }
        return (a.chain, Array(direct.dropFirst()), a.cycle)
    }

    /// Field keys used in the vault, most used first (ties by name), for `key::` completion.
    public func fieldKeys() -> [(key: String, count: Int)] {
        var counts: [String: Int] = [:], spelling: [String: [String: Int]] = [:]
        for n in notes.values {
            for f in n.summary.fields {
                counts[f.kind, default: 0] += 1
                spelling[f.kind, default: [:]][f.key, default: 0] += 1
            }
        }
        return counts.compactMap { k, c in
            guard let s = spelling[k]?.max(by: { ($0.value, $1.key) < ($1.value, $0.key) })?.key else { return nil }
            return (s, c)
        }.sorted { ($0.count, $1.key.lowercased()) > ($1.count, $0.key.lowercased()) }
    }

    /// Kinds whose values are notes: the relation keys, plus any key used with a `[[link]]` somewhere.
    public func linkValuedKinds() -> Set<String> {
        var s: Set<String> = ["partof", "related", "relatesto", "correspondsto"]
        for n in notes.values { for f in n.summary.fields where !f.links.isEmpty { s.insert(f.kind) } }
        return s
    }

    /// The note type from frontmatter `class:` (brackets stripped), if any.
    public func noteClass(_ path: String) -> String? {
        guard let v = notes[path]?.summary.frontmatter["class"]?.strings.first else { return nil }
        var s = v.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("[[") && s.hasSuffix("]]") { s = String(s.dropFirst(2).dropLast(2)) }
        if let bar = s.firstIndex(of: "|") { s = String(s[s.index(after: bar)...]) }
        return s.isEmpty ? nil : s
    }
}
