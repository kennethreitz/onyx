import Foundation

/// Completion for Dataview-style `key:: value` lines, free of AppKit.
///
/// - Typing the first `:` after a word at the start of a line (`part:`) offers existing field
///   keys that start with that word; accepting writes `partOf:: `.
/// - After `key:: ` on a key whose values are notes (`partOf`, `related`, or any key used with a
///   `[[link]]` in the vault), it offers notes; accepting writes `[[Note]]`. Comma lists work.
/// Nothing is ever inserted without an explicit accept, like the `[[` popup.
public enum FieldCompletion {
    public enum Part: Equatable, Sendable {
        case key                 // query is the word before `:`
        case value(key: String)  // query is the current comma segment after `key:: `
    }
    public struct Context: Equatable, Sendable {
        /// UTF-16 offsets within the line: `queryStart..<replaceEnd` is what an accept replaces.
        public var queryStart: Int
        public var replaceEnd: Int
        public var query: String
        public var part: Part
    }

    static let keyRe = try! NSRegularExpression(pattern: #"^(\s*(?:[-*+]\s+)?)([\p{L}][\p{L}\p{N}_-]*):$"#)
    static let valueRe = try! NSRegularExpression(pattern: #"^\s*(?:[-*+]\s+)?([\p{L}][\p{L}\p{N}_ -]*?)::[ \t]+((?:[^,\n]*,)*)[ \t]*([^,\[\]\n]*)$"#)

    /// `line` is the caret's line (no newline needed), `caret` a UTF-16 offset in it.
    /// Text after the caret must be blank, so editing the middle of a line never pops a list.
    public static func context(line: String, caret: Int) -> Context? {
        let ns = line as NSString
        guard caret > 0, caret <= ns.length else { return nil }
        let rest = ns.substring(from: caret).trimmingCharacters(in: .whitespacesAndNewlines)
        guard rest.isEmpty else { return nil }
        let head = ns.substring(to: caret)
        let hr = NSRange(location: 0, length: (head as NSString).length)
        if let m = keyRe.firstMatch(in: head, range: hr) {
            let w = m.range(at: 2)
            return Context(queryStart: w.location, replaceEnd: caret, query: (head as NSString).substring(with: w), part: .key)
        }
        if let m = valueRe.firstMatch(in: head, range: hr) {
            let key = (head as NSString).substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let q = m.range(at: 3)
            let query = (head as NSString).substring(with: q)
            if query.hasPrefix("\"") || query.hasPrefix("'") { return nil }
            return Context(queryStart: q.location, replaceEnd: caret, query: query, part: .value(key: key))
        }
        return nil
    }

    /// Known keys starting with `query` (case-insensitive), most used first. `keys` comes from
    /// `VaultSnapshot.fieldKeys()`. An exact match goes first and is marked so ↩ takes it.
    public static func keySuggestions(_ query: String, keys: [(key: String, count: Int)], limit: Int = 8) -> [(key: String, exact: Bool)] {
        let q = InlineField.kind(query)
        guard !q.isEmpty else { return [] }
        var hits = keys.filter { InlineField.kind($0.key).hasPrefix(q) }.map { ($0.key, InlineField.kind($0.key) == q) }
        if let i = hits.firstIndex(where: { $0.1 }), i > 0 { hits.insert(hits.remove(at: i), at: 0) }
        return Array(hits.prefix(limit))
    }

    /// The text a key accept writes.
    public static func keyInsert(_ key: String) -> String { key + ":: " }
}
