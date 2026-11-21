import Foundation

/// Source-preserving editor for a `.base` YAML file. With no edits, `text` is
/// returned byte-for-byte. Each edit splices only the affected node, so comments,
/// unknown keys, and the order of untouched keys stay put as much as possible.
public struct BaseDoc: Sendable {
    public private(set) var text: String

    public init(_ text: String) { self.text = text }

    public var file: BaseFile { Bases.parse(text) }

    @discardableResult
    public mutating func setViewName(index: Int, _ name: String) -> Bool {
        setViewScalar(index: index, key: "name", value: YAMLWrite.scalar(name))
    }

    @discardableResult
    public mutating func setViewSort(index: Int, _ sort: [BaseSort]) -> Bool {
        guard viewCount > index, index >= 0 else { return false }
        if sort.isEmpty {
            return setViewKey(index: index, key: "sort", written: "[]")
        }
        let body = sort.map { s -> String in
            let dir = s.ascending ? "ASC" : "DESC"
            return "- property: \(YAMLWrite.ident(s.property))\n  direction: \(dir)"
        }.joined(separator: "\n")
        return setViewKey(index: index, key: "sort", written: nil, block: body)
    }

    /// Official `order:` list of property keys. Also keeps a legacy `columns:` list
    /// in the same order when that key is what the file already uses.
    @discardableResult
    public mutating func setViewOrder(index: Int, _ keys: [String], displayNames: [String: String] = [:]) -> Bool {
        guard viewCount > index, index >= 0 else { return false }
        let keys = BaseDoc.uniq(keys)
        var doc = LineDoc(text)
        guard let view = doc.view(index) else { return false }
        let hasColumns = view.map["columns"] != nil
        let hasOrder = view.map["order"] != nil
        var ok = true
        if hasColumns || (!hasOrder && !displayNames.isEmpty && hasColumns) {
            let chunks = keys.map { k -> String in
                if let n = displayNames[k], !n.isEmpty {
                    return "- property: \(YAMLWrite.ident(k))\n  name: \(YAMLWrite.scalar(n))"
                }
                return "- property: \(YAMLWrite.ident(k))"
            }
            ok = doc.setList(path: viewPath(index) + [.key("columns")], chunks: chunks) || doc.insertViewKey(index, key: "columns", block: chunks.joined(separator: "\n"))
        }
        if hasOrder || !hasColumns {
            let chunks = keys.map { "- \(YAMLWrite.ident($0))" }
            let path = viewPath(index) + [.key("order")]
            ok = doc.setList(path: path, chunks: chunks) || doc.insertViewKey(index, key: "order", block: chunks.joined(separator: "\n")) || ok
        }
        guard ok else { return false }
        text = doc.text
        return true
    }

    @discardableResult
    public mutating func addColumn(view index: Int, key: String, displayName: String? = nil) -> Bool {
        var keys = file.views[safe: index]?.order ?? []
        if keys.contains(key) { return false }
        keys.append(key)
        var names: [String: String] = [:]
        if let n = displayName, !n.isEmpty { names[key] = n }
        // Keep names already in the file for other columns so a columns-style rewrite
        // doesn't drop them. displayName on the file wins.
        let f = file
        for k in keys {
            if names[k] == nil, let n = f.properties[k]?.displayName { names[k] = n }
        }
        return setViewOrder(index: index, keys, displayNames: names)
    }

    @discardableResult
    public mutating func removeColumn(view index: Int, key: String) -> Bool {
        guard var keys = file.views[safe: index]?.order, let i = keys.firstIndex(of: key) else { return false }
        keys.remove(at: i)
        if keys.isEmpty { keys = ["file.name"] }
        var names: [String: String] = [:]
        for k in keys { if let n = file.properties[k]?.displayName { names[k] = n } }
        return setViewOrder(index: index, keys, displayNames: names)
    }

    @discardableResult
    public mutating func moveColumn(view index: Int, from: Int, to: Int) -> Bool {
        guard var keys = file.views[safe: index]?.order, keys.indices.contains(from) else { return false }
        let k = keys.remove(at: from)
        let dest = max(0, min(to, keys.count))
        keys.insert(k, at: dest)
        var names: [String: String] = [:]
        for x in keys { if let n = file.properties[x]?.displayName { names[x] = n } }
        return setViewOrder(index: index, keys, displayNames: names)
    }

    @discardableResult
    public mutating func addView(type: String, name: String) -> Bool {
        let t = (type == "cards" || type == "list") ? type : "table"
        var body = "type: \(t)\nname: \(YAMLWrite.scalar(name))"
        if t == "table" || t == "list" {
            body += "\norder:\n  - file.name"
        }
        if t == "cards" { body += "\norder:\n  - file.name\ncardSize: 200" }
        var doc = LineDoc(text)
        if !doc.appendListItem(path: [.key("views")], item: body) {
            // No views: key yet — add one at the end of the root map.
            if !doc.insertRootKey("views", block: "- " + body.replacingOccurrences(of: "\n", with: "\n  ")) {
                return false
            }
        }
        text = doc.text
        return true
    }

    /// Writes a legacy `filter: {property, operator, value}` on the view. Complex
    /// `filters:` groups are left alone; the two are ANDed when the file is read.
    @discardableResult
    public mutating func setSimpleFilter(view index: Int, property: String, operator op: String, value: String) -> Bool {
        guard viewCount > index, index >= 0, !property.isEmpty else { return false }
        let block = "property: \(YAMLWrite.ident(property))\noperator: \(YAMLWrite.ident(op))\nvalue: \(YAMLWrite.scalar(value))"
        var doc = LineDoc(text)
        if doc.setViewKey(index, key: "filter", written: nil, block: block) || doc.insertViewKey(index, key: "filter", block: block) {
            text = doc.text
            return true
        }
        return false
    }

    @discardableResult
    public mutating func clearSimpleFilter(view index: Int) -> Bool {
        var doc = LineDoc(text)
        guard doc.removeViewKey(index, key: "filter") else { return false }
        text = doc.text
        return true
    }

    /// The view's simple (legacy) filter, if it has one and it's just property / operator / value.
    public func simpleFilter(view index: Int) -> (property: String, op: String, value: String)? {
        let doc = LineDoc(text)
        guard let view = doc.view(index), let loc = view.map["filter"] else { return nil }
        let raw = doc.rawValue(loc)
        // Re-parse just this node with the existing YAML subset parser.
        var warnings: [String] = []
        let v = YAML.parse(raw, warnings: &warnings)
        let m = v.map ?? [:]
        guard let p = m["property"]?.string, !p.isEmpty else { return nil }
        let op = m["operator"]?.string ?? "eq"
        let val = m["value"]?.string ?? ""
        return (p, op, val)
    }

    var viewCount: Int { file.views.count }

    @discardableResult
    mutating func setViewScalar(index: Int, key: String, value: String) -> Bool {
        setViewKey(index: index, key: key, written: value)
    }

    @discardableResult
    mutating func setViewKey(index: Int, key: String, written: String?, block: String? = nil) -> Bool {
        var doc = LineDoc(text)
        if doc.setViewKey(index, key: key, written: written, block: block) || doc.insertViewKey(index, key: key, written: written, block: block) {
            text = doc.text
            return true
        }
        return false
    }

    func viewPath(_ index: Int) -> [YAMLPath] { [.key("views"), .index(index)] }

    static func uniq(_ xs: [String]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for x in xs where seen.insert(x).inserted { out.append(x) }
        return out
    }
}

public enum BaseColumns {
    /// Built-in `file.*` properties offered in the column picker.
    public static let fileKeys = [
        "file.name", "file.filename", "file.folder", "file.ext", "file.path",
        "file.size", "file.mtime", "file.ctime", "file.tags", "file.link",
        "note.name",
    ]

    public static func pickerKeys(in snap: VaultSnapshot, file: BaseFile) -> [String] {
        var keys: [String] = fileKeys
        var seen = Set(keys)
        for n in snap.notes.values {
            for p in n.summary.frontmatter.properties where seen.insert(p.key).inserted {
                keys.append(p.key)
            }
        }
        for name in file.formulas.keys.sorted() {
            let k = "formula.\(name)"
            if seen.insert(k).inserted { keys.append(k) }
        }
        return keys
    }
}

// MARK: - Line-oriented YAML document

enum YAMLPath: Equatable {
    case key(String)
    case index(Int)
}

struct EntryLoc: Equatable {
    var key: String
    var keyLine: Int
    /// Exclusive end line of this entry, including any block value.
    var end: Int
    /// Columns of the on-line value after ": ", or nil when the value is a following block (or empty).
    var sameLine: Range<String.Index>?
    /// Raw text after the colon, trimmed; empty means a block or null.
    var rest: String
    var indent: Int
}

struct ListItemLoc: Equatable {
    var start: Int
    var end: Int
    var indent: Int
}

struct ViewLoc {
    var item: ListItemLoc
    var map: [String: EntryLoc]
    var bodyIndent: Int
}

struct LineDoc {
    var lines: [String]
    var newline: String
    var endedWithNL: Bool

    init(_ text: String) {
        if text.contains("\r\n") {
            newline = "\r\n"
            let parts = text.components(separatedBy: "\r\n")
            if parts.last == "" { endedWithNL = true; lines = Array(parts.dropLast()) }
            else { endedWithNL = false; lines = parts }
        } else {
            newline = "\n"
            let parts = text.components(separatedBy: "\n")
            if parts.last == "" { endedWithNL = true; lines = Array(parts.dropLast()) }
            else { endedWithNL = false; lines = parts }
        }
    }

    var text: String {
        let body = lines.joined(separator: newline)
        return endedWithNL ? body + newline : body
    }

    func view(_ index: Int) -> ViewLoc? {
        guard let views = list(path: [.key("views")]), views.indices.contains(index) else { return nil }
        let item = views[index]
        let bodyIndent = itemBodyIndent(item)
        let entries = mapEntries(from: item.start, end: item.end, indent: bodyIndent, skipDashLine: true)
        var map: [String: EntryLoc] = [:]
        for e in entries { map[e.key] = e }
        return ViewLoc(item: item, map: map, bodyIndent: bodyIndent)
    }

    func itemBodyIndent(_ item: ListItemLoc) -> Int {
        let line = lines[item.start]
        let ind = lineIndent( line)
        let content = ltrim(line)
        if content.hasPrefix("- ") {
            let rest = String(content.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if firstColon(rest) != nil { return ind + 2 }
        }
        // Bare `-` with a following block, or `- value`.
        if item.start + 1 < item.end {
            for j in (item.start + 1)..<item.end where !isTrivia(lines[j]) {
                return lineIndent( lines[j])
            }
        }
        return ind + 2
    }

    @discardableResult
    mutating func setViewKey(_ index: Int, key: String, written: String?, block: String?) -> Bool {
        guard let view = view(index), let loc = view.map[key] else { return false }
        apply(entry: loc, written: written, block: block, indent: view.bodyIndent)
        return true
    }

    @discardableResult
    mutating func insertViewKey(_ index: Int, key: String, written: String? = nil, block: String? = nil) -> Bool {
        guard let view = view(index) else { return false }
        if view.map[key] != nil { return setViewKey(index, key: key, written: written, block: block) }
        let pad = String(repeating: " ", count: view.bodyIndent)
        var chunk = pad + key + ":"
        if let written { chunk += " " + written }
        else if let block {
            let inner = indentBlock(block, by: view.bodyIndent + 2)
            chunk += "\n" + inner
        } else {
            chunk += " null"
        }
        let insertAt = view.item.end
        let newLines = chunk.components(separatedBy: "\n")
        lines.insert(contentsOf: newLines, at: insertAt)
        return true
    }

    @discardableResult
    mutating func removeViewKey(_ index: Int, key: String) -> Bool {
        guard let view = view(index), let loc = view.map[key] else { return false }
        lines.removeSubrange(loc.keyLine..<loc.end)
        return true
    }

    mutating func apply(entry loc: EntryLoc, written: String?, block: String?, indent: Int) {
        if let written {
            // Put the value on the key line; drop any previous block body.
            var line = lines[loc.keyLine]
            if let hash = trailingComment(line) {
                let prefix = String(line[..<colonIndex(line)!])
                line = prefix + ": " + written + " " + hash
            } else if let c = colonIndex(line) {
                line = String(line[..<c]) + ": " + written
            }
            lines[loc.keyLine] = line
            if loc.end > loc.keyLine + 1 {
                lines.removeSubrange((loc.keyLine + 1)..<loc.end)
            }
            return
        }
        if let block {
            // Key line with no same-line value, then an indented block.
            if let c = colonIndex(lines[loc.keyLine]) {
                var line = String(lines[loc.keyLine][..<c]) + ":"
                if let hash = trailingComment(lines[loc.keyLine]) { line += " " + hash }
                lines[loc.keyLine] = line
            }
            let inner = indentBlock(block, by: indent + 2).components(separatedBy: "\n")
            if loc.end > loc.keyLine + 1 {
                lines.removeSubrange((loc.keyLine + 1)..<loc.end)
            }
            lines.insert(contentsOf: inner, at: loc.keyLine + 1)
        }
    }

    @discardableResult
    mutating func setList(path: [YAMLPath], chunks: [String]) -> Bool {
        guard let items = list(path: path) else { return false }
        // Locate the list as a whole: from the first item to the last, or the `key: []` line.
        guard let parent = parentEntry(path: path) else {
            // List is a view / root value we already have as items.
            guard let first = items.first, let last = items.last else { return false }
            let indent = first.indent
            let rendered = chunks.map { indentBlock($0, by: indent) }.joined(separator: "\n")
            let newLines = rendered.isEmpty ? [String(repeating: " ", count: indent) + "# empty"] : rendered.components(separatedBy: "\n")
            lines.removeSubrange(first.start..<last.end)
            lines.insert(contentsOf: newLines, at: first.start)
            return true
        }
        if chunks.isEmpty {
            apply(entry: parent, written: "[]", block: nil, indent: parent.indent)
            return true
        }
        apply(entry: parent, written: nil, block: chunks.joined(separator: "\n"), indent: parent.indent)
        return true
    }

    @discardableResult
    mutating func appendListItem(path: [YAMLPath], item: String) -> Bool {
        if let items = list(path: path), let last = items.last {
            let chunk = indentBlock("- " + item.replacingOccurrences(of: "\n", with: "\n  "), by: last.indent)
            lines.insert(contentsOf: chunk.components(separatedBy: "\n"), at: last.end)
            return true
        }
        // Empty flow list `views: []` or a key with no items.
        guard let parent = parentEntry(path: path) else { return false }
        let block = "- " + item.replacingOccurrences(of: "\n", with: "\n  ")
        apply(entry: parent, written: nil, block: block, indent: parent.indent)
        return true
    }

    @discardableResult
    mutating func insertRootKey(_ key: String, block: String) -> Bool {
        let indent = firstContentIndent()
        let pad = String(repeating: " ", count: indent)
        let chunk = pad + key + ":\n" + indentBlock(block, by: indent + 2)
        lines.append(contentsOf: chunk.components(separatedBy: "\n"))
        endedWithNL = true
        return true
    }

    func rawValue(_ loc: EntryLoc) -> String {
        if !loc.rest.isEmpty { return loc.rest }
        if loc.end > loc.keyLine + 1 {
            return lines[(loc.keyLine + 1)..<loc.end].joined(separator: "\n")
        }
        return ""
    }

    func parentEntry(path: [YAMLPath]) -> EntryLoc? {
        guard let last = path.last, case .key(let k) = last else { return nil }
        if path.count == 1 {
            let indent = firstContentIndent()
            let entries = mapEntries(from: 0, end: lines.count, indent: indent, skipDashLine: false)
            return entries.first { $0.key == k }
        }
        // views[i].key
        if path.count == 3, case .key("views") = path[0], case .index(let i) = path[1], case .key(let k) = last {
            return view(i)?.map[k]
        }
        return nil
    }

    func list(path: [YAMLPath]) -> [ListItemLoc]? {
        if path == [.key("views")] {
            let indent = firstContentIndent()
            let entries = mapEntries(from: 0, end: lines.count, indent: indent, skipDashLine: false)
            guard let e = entries.first(where: { $0.key == "views" }) else { return nil }
            return listItems(in: e)
        }
        if path.count == 3, case .key("views") = path[0], case .index(let i) = path[1], case .key(let k) = path[2] {
            guard let v = view(i), let e = v.map[k] else { return nil }
            return listItems(in: e)
        }
        return nil
    }

    func listItems(in e: EntryLoc) -> [ListItemLoc] {
        if e.rest == "[]" || e.rest.hasPrefix("[") { return [] }
        let start: Int
        let indent: Int
        if e.rest.hasPrefix("- ") || e.rest == "-" {
            // Unusual: list starts on the key line. Treat as no block items plus that one — skip.
            start = e.keyLine + 1
            indent = e.indent + 2
        } else {
            start = e.keyLine + 1
            // Find the indent of the first list item.
            var found: Int?
            for j in start..<e.end where !isTrivia(lines[j]) {
                let t = ltrim(lines[j])
                if t.hasPrefix("- ") || t == "-" { found = lineIndent( lines[j]); break }
            }
            indent = found ?? (e.indent + 2)
        }
        return listItems(from: start, end: e.end, indent: indent)
    }

    func listItems(from start: Int, end: Int, indent: Int) -> [ListItemLoc] {
        var out: [ListItemLoc] = []
        var i = start
        while i < end {
            if isTrivia(lines[i]) { i += 1; continue }
            let ind = lineIndent( lines[i])
            if ind < indent { break }
            let t = ltrim(lines[i])
            if ind == indent, t.hasPrefix("- ") || t == "-" {
                var j = i + 1
                while j < end {
                    if isTrivia(lines[j]) {
                        // Peek: if the next non-trivia is a sibling item or outdent, stop before this trivia? Keep trailing trivia with the item only if more-indented content follows. Otherwise leave it for the next item / parent.
                        var k = j + 1
                        while k < end, isTrivia(lines[k]) { k += 1 }
                        if k < end, lineIndent( lines[k]) > indent { j = k; continue }
                        break
                    }
                    if lineIndent( lines[j]) > indent { j += 1; continue }
                    break
                }
                out.append(ListItemLoc(start: i, end: j, indent: indent))
                i = j
                continue
            }
            if ind > indent { i += 1; continue }
            break
        }
        return out
    }

    func mapEntries(from start: Int, end: Int, indent: Int, skipDashLine: Bool) -> [EntryLoc] {
        var out: [EntryLoc] = []
        var i = start
        if skipDashLine, i < end {
            // The `- type: table` line itself may also be the first map key.
            let t = ltrim(lines[i])
            if t.hasPrefix("- ") {
                let rest = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if firstColon(rest) != nil {
                    if let e = entry(at: i, indent: indent, end: end, dashPrefix: true) {
                        out.append(e)
                        i = e.end
                    } else {
                        i += 1
                    }
                } else {
                    i += 1
                }
            }
        }
        while i < end {
            if isTrivia(lines[i]) { i += 1; continue }
            let ind = lineIndent( lines[i])
            if ind < indent { break }
            let t = ltrim(lines[i])
            if ind == indent, t.hasPrefix("- ") || t == "-" { break }
            if ind > indent { i += 1; continue }
            if firstColon(t) == nil { i += 1; continue }
            if let e = entry(at: i, indent: indent, end: end, dashPrefix: false) {
                out.append(e)
                i = e.end
            } else {
                i += 1
            }
        }
        return out
    }

    func entry(at i: Int, indent: Int, end: Int, dashPrefix: Bool) -> EntryLoc? {
        var content = ltrim(lines[i])
        if dashPrefix, content.hasPrefix("- ") { content = String(content.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        guard let colon = firstColon(content) else { return nil }
        let key = YAML.unquote(String(content[..<colon]).trimmingCharacters(in: .whitespaces))
        let rest = String(content[content.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        var j = i + 1
        if rest.isEmpty {
            while j < end {
                if isTrivia(lines[j]) {
                    var k = j + 1
                    while k < end, isTrivia(lines[k]) { k += 1 }
                    if k < end, lineIndent( lines[k]) > indent { j = k; continue }
                    break
                }
                let ind = lineIndent( lines[j])
                let t = ltrim(lines[j])
                if ind > indent { j += 1; continue }
                // Compact list whose dashes line up with the key (`or:` then `- item` at the same indent).
                if ind == indent, (t.hasPrefix("- ") || t == "-"), isCompactListKey(key) {
                    j += 1
                    while j < end {
                        if isTrivia(lines[j]) { break }
                        if lineIndent( lines[j]) > indent { j += 1; continue }
                        if lineIndent( lines[j]) == indent, ltrim(lines[j]).hasPrefix("- ") { j += 1; continue }
                        break
                    }
                    continue
                }
                break
            }
        }
        // same-line value range on the original line (for comment-preserving scalar edits)
        var same: Range<String.Index>? = nil
        if !rest.isEmpty, let c = colonIndex(lines[i]) {
            var s = lines[i].index(after: c)
            while s < lines[i].endIndex, lines[i][s] == " " { s = lines[i].index(after: s) }
            var e = lines[i].endIndex
            if let hash = YAML.unquotedHash(lines[i]) {
                e = hash
                while e > s, lines[i][lines[i].index(before: e)] == " " { e = lines[i].index(before: e) }
            }
            if s < e { same = s..<e }
        }
        return EntryLoc(key: key, keyLine: i, end: j, sameLine: same, rest: rest, indent: indent)
    }

    func isCompactListKey(_ k: String) -> Bool {
        let x = k.lowercased()
        return x == "and" || x == "or" || x == "not" || x == "filters"
    }

    func firstContentIndent() -> Int {
        for l in lines where !isTrivia(l) { return lineIndent( l) }
        return 0
    }

    func lineIndent(_ line: String) -> Int { line.prefix { $0 == " " || $0 == "\t" }.count }

    func ltrim(_ line: String) -> String { String(line.drop(while: { $0 == " " || $0 == "\t" })) }

    func isTrivia(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.isEmpty || t.hasPrefix("#")
    }

    func firstColon(_ s: String) -> String.Index? { YAMLFirstColon(s) }

    func colonIndex(_ line: String) -> String.Index? {
        var i = line.startIndex
        while i < line.endIndex, line[i] == " " || line[i] == "\t" { i = line.index(after: i) }
        if i < line.endIndex, line[i] == "-" {
            let n = line.index(after: i)
            if n < line.endIndex, line[n] == " " {
                i = line.index(after: n)
                while i < line.endIndex, line[i] == " " { i = line.index(after: i) }
            }
        }
        var quote: Character? = nil
        var j = i
        while j < line.endIndex {
            let ch = line[j]
            if let q = quote {
                if ch == q { quote = nil }
            } else if ch == "\"" || ch == "'" { quote = ch }
            else if ch == ":" { return j }
            j = line.index(after: j)
        }
        return nil
    }

    func trailingComment(_ line: String) -> String? {
        guard let hash = YAML.unquotedHash(line) else { return nil }
        return String(line[hash...]).trimmingCharacters(in: .whitespaces)
    }

    func indentBlock(_ block: String, by n: Int) -> String {
        let pad = String(repeating: " ", count: n)
        return block.split(separator: "\n", omittingEmptySubsequences: false).map { row in
            if row.isEmpty { return "" }
            return pad + row
        }.joined(separator: "\n")
    }
}

enum YAMLWrite {
    static func ident(_ s: String) -> String {
        if s.isEmpty { return "\"\"" }
        // Unquoted if it looks like a safe YAML ident / dotted path / number.
        let ok = s.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "_" || $0 == "-" }
        if ok, s.first?.isNumber == false || Double(s) != nil { return s }
        return scalar(s)
    }

    static func scalar(_ s: String) -> String {
        if s.isEmpty { return "\"\"" }
        if Double(s) != nil, s.first?.isNumber == true || s.hasPrefix("-") { return s }
        if s == "true" || s == "false" || s == "null" || s == "yes" || s == "no" { return "\"" + s + "\"" }
        let needs = s.contains(where: { $0 == ":" || $0 == "#" || $0 == "'" || $0 == "\"" || $0 == "\n" || $0 == "&" || $0 == "*" || $0 == "!" || $0 == "{" || $0 == "}" || $0 == "[" || $0 == "]" || $0 == "," || $0 == " " })
        if !needs, s.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "_" || $0 == "-" || $0 == "/" }) {
            return s
        }
        return "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

func YAMLFirstColon(_ s: String) -> String.Index? {
    var quote: Character? = nil
    var i = s.startIndex
    while i < s.endIndex {
        let c = s[i]
        if let q = quote {
            if c == q { quote = nil }
        } else if c == "\"" || c == "'" { quote = c }
        else if c == ":" { return i }
        i = s.index(after: i)
    }
    return nil
}
