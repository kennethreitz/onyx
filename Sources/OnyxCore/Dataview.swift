import Foundation

/// Dataview-lite: the subset of DQL this vault actually uses —
/// TABLE [WITHOUT ID] expr AS "Name", … / LIST, FROM "folder" | #tag (with OR / -),
/// WHERE expressions (= != < > <= >= AND OR, contains(), choice(), default()),
/// SORT a ASC, b DESC, LIMIT n.
public enum DVValue: Equatable, Sendable {
    case null
    case string(String)
    case number(Double)
    case bool(Bool)
    case link(path: String, name: String)
    case list([DVValue])

    public var truthy: Bool {
        switch self {
        case .null: return false
        case .string(let s): return !s.isEmpty
        case .number(let n): return n != 0
        case .bool(let b): return b
        case .link: return true
        case .list(let l): return !l.isEmpty
        }
    }
    public var text: String {
        switch self {
        case .null: return ""
        case .string(let s): return s
        case .number(let n): return n.rounded() == n && abs(n) < 1e15 ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        case .link(_, let name): return name
        case .list(let l): return l.map(\.text).joined(separator: ", ")
        }
    }
    static func from(_ p: PropertyValue) -> DVValue {
        switch p {
        case .string(let s): return s.isEmpty ? .null : .string(s)
        case .number(let n): return .number(n)
        case .bool(let b): return .bool(b)
        case .list(let l): return .list(l.map { .string($0) })
        }
    }
    func compare(_ o: DVValue) -> Int {
        switch (self, o) {
        case (.null, .null): return 0
        case (.null, _): return -1
        case (_, .null): return 1
        case (.number(let a), .number(let b)): return a < b ? -1 : (a > b ? 1 : 0)
        default:
            let a = text, b = o.text
            if let x = Double(a), let y = Double(b) { return x < y ? -1 : (x > y ? 1 : 0) }
            switch a.localizedStandardCompare(b) { case .orderedAscending: return -1; case .orderedDescending: return 1; default: return 0 }
        }
    }
}

public indirect enum DVExpr: Sendable {
    case field(String)
    case literal(DVValue)
    case call(String, [DVExpr])
    case binary(String, DVExpr, DVExpr)
    case not(DVExpr)
}

public struct DVQuery: Sendable {
    public enum Kind: Sendable { case table, list, task }
    public var kind: Kind
    public var withoutID = false
    public var columns: [(DVExpr, String)] = []
    public var listExpr: DVExpr?
    public var from: [(String, Bool)] = []   // (source, negated); source "#tag" or folder path
    public var whereExpr: DVExpr?
    public var sort: [(DVExpr, Bool)] = []   // ascending?
    public var limit: Int?
}

public struct DVResult: Sendable {
    public var headers: [String]
    public var rows: [[DVValue]]
    public var isList: Bool
}

public enum DataviewError: Error, CustomStringConvertible {
    case parse(String)
    public var description: String { switch self { case .parse(let s): return s } }
}

public enum Dataview {
    // MARK: Tokenizer
    enum Tok: Equatable { case ident(String), str(String), num(Double), op(String), lparen, rparen, comma, hash(String) }

    static func tokenize(_ s: String) throws -> [Tok] {
        var out: [Tok] = []
        let c = Array(s)
        var i = 0
        while i < c.count {
            let ch = c[i]
            if ch.isWhitespace { i += 1; continue }
            if ch == "\"" || ch == "'" {
                var j = i + 1; var v = ""
                while j < c.count && c[j] != ch { if c[j] == "\\" && j + 1 < c.count { j += 1 }; v.append(c[j]); j += 1 }
                out.append(.str(v)); i = j + 1; continue
            }
            if ch == "(" { out.append(.lparen); i += 1; continue }
            if ch == ")" { out.append(.rparen); i += 1; continue }
            if ch == "," { out.append(.comma); i += 1; continue }
            if ch == "#" {
                var j = i + 1; var v = ""
                while j < c.count && (c[j].isLetter || c[j].isNumber || "_-/".contains(c[j])) { v.append(c[j]); j += 1 }
                out.append(.hash(v)); i = j; continue
            }
            if "=!<>&|+-*/".contains(ch) {
                if i + 1 < c.count, ["!=", "<=", ">=", "==", "&&", "||"].contains(String([ch, c[i + 1]])) {
                    out.append(.op(String([ch, c[i + 1]]))); i += 2; continue
                }
                if ch == "-" && i + 1 < c.count && c[i + 1].isNumber && (out.last == nil || { if case .op = out.last! { return true }; return out.last == .lparen || out.last == .comma }()) {
                    // negative number
                } else {
                    out.append(.op(String(ch))); i += 1; continue
                }
            }
            if ch.isNumber || ch == "-" {
                var j = i; var v = ""
                if ch == "-" { v = "-"; j += 1 }
                while j < c.count && (c[j].isNumber || c[j] == ".") { v.append(c[j]); j += 1 }
                if let d = Double(v) { out.append(.num(d)) }
                i = j; continue
            }
            if ch.isLetter || ch == "_" {
                var j = i; var v = ""
                while j < c.count && (c[j].isLetter || c[j].isNumber || c[j] == "_" || c[j] == "." ||
                                      (c[j] == "-" && j + 1 < c.count && c[j + 1].isLetter)) { v.append(c[j]); j += 1 }
                out.append(.ident(v)); i = j; continue
            }
            throw DataviewError.parse("Unexpected character '\(ch)'")
        }
        return out
    }

    // MARK: Expression parser (precedence climbing)
    final class P {
        var t: [Tok]; var i = 0
        init(_ t: [Tok]) { self.t = t }
        var peek: Tok? { i < t.count ? t[i] : nil }
        func next() -> Tok? { defer { i += 1 }; return peek }
        func isKeyword(_ k: String) -> Bool { if case .ident(let s) = peek, s.uppercased() == k { return true }; return false }

        func expr() throws -> DVExpr { try orE() }
        func orE() throws -> DVExpr {
            var l = try andE()
            while isKeyword("OR") || peek == .op("||") || peek == .op("|") { i += 1; l = .binary("or", l, try andE()) }
            return l
        }
        func andE() throws -> DVExpr {
            var l = try cmp()
            while isKeyword("AND") || peek == .op("&&") || peek == .op("&") { i += 1; l = .binary("and", l, try cmp()) }
            return l
        }
        func cmp() throws -> DVExpr {
            var l = try add()
            while case .op(let o) = peek, ["=", "==", "!=", "<", ">", "<=", ">="].contains(o) { i += 1; l = .binary(o == "==" ? "=" : o, l, try add()) }
            return l
        }
        func add() throws -> DVExpr {
            var l = try unary()
            while case .op(let o) = peek, ["+", "-", "*", "/"].contains(o) { i += 1; l = .binary(o, l, try unary()) }
            return l
        }
        func unary() throws -> DVExpr {
            if peek == .op("!") { i += 1; return .not(try unary()) }
            return try primary()
        }
        func primary() throws -> DVExpr {
            guard let tk = next() else { throw DataviewError.parse("Unexpected end of expression") }
            switch tk {
            case .str(let s): return .literal(.string(s))
            case .num(let n): return .literal(.number(n))
            case .lparen: let e = try expr(); if peek == .rparen { i += 1 }; return e
            case .ident(let name):
                if name.lowercased() == "true" { return .literal(.bool(true)) }
                if name.lowercased() == "false" { return .literal(.bool(false)) }
                if name.lowercased() == "null" { return .literal(.null) }
                if peek == .lparen {
                    i += 1
                    var args: [DVExpr] = []
                    while peek != nil && peek != .rparen { args.append(try expr()); if peek == .comma { i += 1 } }
                    i += 1
                    return .call(name.lowercased(), args)
                }
                return .field(name)
            case .hash(let tag): return .literal(.string("#" + tag))
            default: throw DataviewError.parse("Unexpected token")
            }
        }
    }

    // MARK: Query parser
    static let clauses = ["FROM", "WHERE", "SORT", "LIMIT", "GROUP", "FLATTEN"]

    public static func parse(_ source: String) throws -> DVQuery {
        // Split into clauses by keyword at line or token boundaries.
        let text = source.replacingOccurrences(of: "\n", with: " ")
        let toks = try tokenize(text)
        guard case .ident(let first)? = toks.first else { throw DataviewError.parse("Empty query") }
        var q: DVQuery
        switch first.uppercased() {
        case "TABLE": q = DVQuery(kind: .table)
        case "LIST": q = DVQuery(kind: .list)
        case "TASK": q = DVQuery(kind: .task)
        default: throw DataviewError.parse("Onyx supports TABLE and LIST queries (got \(first))")
        }
        // group tokens per clause
        var sections: [(String, [Tok])] = [("HEAD", [])]
        for tk in toks.dropFirst() {
            if case .ident(let s) = tk, clauses.contains(s.uppercased()) { sections.append((s.uppercased(), [])) ; continue }
            if case .ident(let s) = tk, s.uppercased() == "BY", sections.last?.0 == "GROUP" { continue }
            sections[sections.count - 1].1.append(tk)
        }
        for (name, ts) in sections {
            switch name {
            case "HEAD":
                var t = ts
                if case .ident(let w)? = t.first, w.uppercased() == "WITHOUT", t.count > 1 { q.withoutID = true; t.removeFirst(2) }
                if t.isEmpty { break }
                let p = P(t)
                if q.kind == .list { q.listExpr = try p.expr(); break }
                while p.peek != nil {
                    let e = try p.expr()
                    var label = exprLabel(e)
                    if p.isKeyword("AS") { p.i += 1; if case .str(let s)? = p.next() { label = s } else if case .ident(let s)? = t[safe: p.i - 1] { label = s } }
                    q.columns.append((e, label))
                    if p.peek == .comma { p.i += 1 }
                }
            case "FROM":
                var neg = false
                for tk in ts {
                    switch tk {
                    case .str(let s): q.from.append((s, neg)); neg = false
                    case .hash(let s): q.from.append(("#" + s, neg)); neg = false
                    case .op("-"), .op("!"): neg = true
                    default: break
                    }
                }
            case "WHERE":
                q.whereExpr = try P(ts).expr()
            case "SORT":
                let p = P(ts)
                while p.peek != nil {
                    let e = try p.expr()
                    var asc = true
                    if p.isKeyword("DESC") || p.isKeyword("DESCENDING") { asc = false; p.i += 1 }
                    else if p.isKeyword("ASC") || p.isKeyword("ASCENDING") { p.i += 1 }
                    q.sort.append((e, asc))
                    if p.peek == .comma { p.i += 1 }
                }
            case "LIMIT":
                if case .num(let n)? = ts.first { q.limit = Int(n) }
            default:
                throw DataviewError.parse("\(name) isn't supported by Onyx's dataview-lite yet")
            }
        }
        return q
    }

    static func exprLabel(_ e: DVExpr) -> String {
        switch e {
        case .field(let f): return f
        case .call(let n, _): return n
        default: return "value"
        }
    }

    // MARK: Evaluation
    public static func run(_ source: String, in snap: VaultSnapshot, from currentPath: String? = nil) throws -> DVResult {
        let q = try parse(source)
        var pages = snap.notes.values.filter { matchesFrom(q.from, $0, snap: snap, current: currentPath) }
        if let w = q.whereExpr { pages = pages.filter { eval(w, $0, snap).truthy } }
        if q.sort.isEmpty {
            pages.sort { $0.path < $1.path }
        } else {
            pages.sort { a, b in
                for (e, asc) in q.sort {
                    let c = eval(e, a, snap).compare(eval(e, b, snap))
                    if c != 0 { return asc ? c < 0 : c > 0 }
                }
                return a.path < b.path
            }
        }
        if let l = q.limit { pages = Array(pages.prefix(l)) }
        let link: (NoteRecord) -> DVValue = { .link(path: $0.path, name: $0.name) }
        switch q.kind {
        case .list, .task:
            let rows = pages.map { p -> [DVValue] in
                if let e = q.listExpr { return [link(p), eval(e, p, snap)] }
                return [link(p)]
            }
            return DVResult(headers: [], rows: rows, isList: true)
        case .table:
            var headers = q.columns.map(\.1)
            if !q.withoutID { headers.insert("File", at: 0) }
            let rows = pages.map { p -> [DVValue] in
                var r = q.columns.map { eval($0.0, p, snap) }
                if !q.withoutID { r.insert(link(p), at: 0) }
                return r
            }
            return DVResult(headers: headers, rows: rows, isList: false)
        }
    }

    static func matchesFrom(_ from: [(String, Bool)], _ n: NoteRecord, snap: VaultSnapshot, current: String?) -> Bool {
        if from.isEmpty { return true }
        var anyPositive = false, matchedPositive = false
        for (src, neg) in from {
            let m: Bool
            if src.hasPrefix("#") {
                let t = String(src.dropFirst()).lowercased()
                m = n.summary.tags.contains { $0.lowercased() == t || $0.lowercased().hasPrefix(t + "/") }
            } else {
                let s = src.hasSuffix("/") ? String(src.dropLast()) : src
                m = n.path == s || n.path == s + ".md" || n.path.hasPrefix(s + "/")
            }
            if neg { if m { return false } } else { anyPositive = true; if m { matchedPositive = true } }
        }
        return !anyPositive || matchedPositive
    }

    static func field(_ name: String, _ n: NoteRecord, _ snap: VaultSnapshot) -> DVValue {
        let lower = name.lowercased()
        switch lower {
        case "file.link": return .link(path: n.path, name: n.name)
        case "file.name": return .string(n.name)
        case "file.path": return .string(n.path)
        case "file.folder": return .string(n.folder)
        case "file.size": return .number(Double(n.size))
        case "file.mtime", "file.mday": return .string(iso(n.mtime))
        case "file.ctime", "file.cday": return .string(iso(n.ctime))
        case "file.tags", "file.etags": return .list(n.summary.tags.map { .string("#" + $0) })
        case "file.outlinks": return .list(n.summary.links.compactMap { l in snap.resolve(l.target, from: n.path).map { DVValue.link(path: $0, name: (($0 as NSString).lastPathComponent as NSString).deletingPathExtension) } })
        case "file.inlinks": return .list((snap.backlinks[n.path] ?? []).sorted().map { .link(path: $0, name: (($0 as NSString).lastPathComponent as NSString).deletingPathExtension) })
        default: break
        }
        // Dataview normalizes keys: case-insensitive, spaces/dashes interchangeable
        let norm = { (s: String) in s.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "_", with: "-") }
        if let p = n.summary.frontmatter.properties.first(where: { norm($0.key) == norm(name) }) {
            let v = DVValue.from(p.value)
            // A property holding "[[Note]]" becomes a link
            if case .string(let s) = v, s.hasPrefix("[["), s.hasSuffix("]]") {
                let l = NoteParser.makeLink(inner: String(s.dropFirst(2).dropLast(2)), embed: false, range: NSRange())
                if let path = snap.resolve(l.target, from: n.path) { return .link(path: path, name: l.alias ?? l.target) }
            }
            return v
        }
        return .null
    }

    static func iso(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }

    static func eval(_ e: DVExpr, _ n: NoteRecord, _ snap: VaultSnapshot) -> DVValue {
        switch e {
        case .literal(let v): return v
        case .field(let f): return field(f, n, snap)
        case .not(let x): return .bool(!eval(x, n, snap).truthy)
        case .binary(let op, let a, let b):
            if op == "and" { return .bool(eval(a, n, snap).truthy && eval(b, n, snap).truthy) }
            if op == "or" { return .bool(eval(a, n, snap).truthy || eval(b, n, snap).truthy) }
            let x = eval(a, n, snap), y = eval(b, n, snap)
            switch op {
            case "=": return .bool(equal(x, y))
            case "!=": return .bool(!equal(x, y))
            case "<": return .bool(x.compare(y) < 0)
            case ">": return .bool(x.compare(y) > 0)
            case "<=": return .bool(x.compare(y) <= 0)
            case ">=": return .bool(x.compare(y) >= 0)
            case "+":
                if case .number(let p) = x, case .number(let q) = y { return .number(p + q) }
                return .string(x.text + y.text)
            case "-": if case .number(let p) = x, case .number(let q) = y { return .number(p - q) }; return .null
            case "*": if case .number(let p) = x, case .number(let q) = y { return .number(p * q) }; return .null
            case "/": if case .number(let p) = x, case .number(let q) = y, q != 0 { return .number(p / q) }; return .null
            default: return .null
            }
        case .call(let name, let args):
            let v = args.map { eval($0, n, snap) }
            switch name {
            case "choice": return v.count == 3 ? (v[0].truthy ? v[1] : v[2]) : .null
            case "default": return v.count == 2 ? (v[0] == .null ? v[1] : v[0]) : .null
            case "contains", "icontains":
                guard v.count == 2 else { return .null }
                let ci = name == "icontains"
                if case .list(let l) = v[0] { return .bool(l.contains { equal($0, v[1]) || (ci && $0.text.lowercased() == v[1].text.lowercased()) }) }
                return .bool(ci ? v[0].text.lowercased().contains(v[1].text.lowercased()) : v[0].text.contains(v[1].text))
            case "length": if case .list(let l) = v.first { return .number(Double(l.count)) }; return .number(Double(v.first?.text.count ?? 0))
            case "lower": return .string(v.first?.text.lowercased() ?? "")
            case "upper": return .string(v.first?.text.uppercased() ?? "")
            case "join": if case .list(let l) = v.first { return .string(l.map(\.text).joined(separator: v.count > 1 ? v[1].text : ", ")) }; return v.first ?? .null
            case "link": if let p = snap.resolve(v.first?.text ?? "", from: n.path) { return .link(path: p, name: v.count > 1 ? v[1].text : (v.first?.text ?? "")) }; return .null
            case "number": return Double(v.first?.text ?? "").map { .number($0) } ?? .null
            case "string": return .string(v.first?.text ?? "")
            default: return .null
            }
        }
    }

    static func equal(_ a: DVValue, _ b: DVValue) -> Bool {
        if case .list(let l) = a, !(b.isList) { return l.contains { equal($0, b) } }
        if case .link(let p, _) = a, case .link(let q, _) = b { return p == q }
        if case .number(let x) = a, case .number(let y) = b { return x == y }
        return a.text == b.text
    }
}

extension DVValue { var isList: Bool { if case .list = self { return true }; return false } }

extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }
