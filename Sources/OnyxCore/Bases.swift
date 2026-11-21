import Foundation

/// Obsidian Bases (`.base` YAML, or a ` ```base ` block in a note). Read-only in Onyx:
/// we parse the file, filter and sort the vault, and draw the views. Unknown
/// expressions are skipped with a warning rather than crashing the view.

public extension String {
    var isBasePath: Bool { lowercased().hasSuffix(".base") }
}

public struct BasePropertyConfig: Sendable, Equatable {
    public var displayName: String?
    public init(displayName: String? = nil) { self.displayName = displayName }
}

public struct BaseColumn: Sendable, Equatable, Identifiable {
    public var id: String { key }
    public var key: String
    public var displayName: String
    public init(key: String, displayName: String) { self.key = key; self.displayName = displayName }
}

public struct BaseSort: Sendable, Equatable {
    public var property: String
    public var ascending: Bool
    public init(property: String, ascending: Bool) { self.property = property; self.ascending = ascending }
}

public indirect enum BaseFilter: Sendable, Equatable {
    case always
    case expression(String)
    case and([BaseFilter])
    case or([BaseFilter])
    case not([BaseFilter])
}

public struct BaseView: Sendable, Equatable, Identifiable {
    public var id: String { name + ":" + type }
    public var type: String          // table, cards, list
    public var name: String
    public var filters: BaseFilter
    public var order: [String]
    public var sort: [BaseSort]
    public var limit: Int?
    public var groupBy: BaseSort?
    public var cardSize: Double?
    public var coverProperty: String?
    public var indentProperties: Bool
    public init(type: String, name: String, filters: BaseFilter, order: [String], sort: [BaseSort], limit: Int?, groupBy: BaseSort?, cardSize: Double?, coverProperty: String?, indentProperties: Bool) {
        self.type = type; self.name = name; self.filters = filters; self.order = order; self.sort = sort
        self.limit = limit; self.groupBy = groupBy; self.cardSize = cardSize; self.coverProperty = coverProperty
        self.indentProperties = indentProperties
    }
}

public struct BaseFile: Sendable, Equatable {
    public var name: String?
    public var formulas: [String: String]
    public var properties: [String: BasePropertyConfig]
    public var filters: BaseFilter
    public var views: [BaseView]
    public var warnings: [String]
    public init(name: String?, formulas: [String: String], properties: [String: BasePropertyConfig], filters: BaseFilter, views: [BaseView], warnings: [String]) {
        self.name = name; self.formulas = formulas; self.properties = properties
        self.filters = filters; self.views = views; self.warnings = warnings
    }
}

public enum BaseValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case list([BaseValue])
    case date(Date)
    case link(path: String, name: String)

    public var isTruthy: Bool {
        switch self {
        case .null: return false
        case .bool(let b): return b
        case .number(let n): return n != 0 && !n.isNaN
        case .string(let s): return !s.isEmpty
        case .list(let l): return !l.isEmpty
        case .date: return true
        case .link(let p, let n): return !p.isEmpty || !n.isEmpty
        }
    }

    public var text: String {
        switch self {
        case .null: return ""
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n.rounded() == n && n.isFinite ? String(Int(n)) : String(n)
        case .string(let s): return s
        case .list(let l): return l.map(\.text).filter { !$0.isEmpty }.joined(separator: ", ")
        case .date(let d): return BaseValue.day.string(from: d)
        case .link(_, let n): return n
        }
    }

    public var sortKey: String {
        switch self {
        case .date(let d): return BaseValue.iso.string(from: d)
        case .number(let n): return String(format: "%020.6f", n)
        case .bool(let b): return b ? "1" : "0"
        default: return text.lowercased()
        }
    }

    public func compare(_ o: BaseValue) -> Int {
        if self == .null && o == .null { return 0 }
        if self == .null { return -1 }
        if o == .null { return 1 }
        switch (self, o) {
        case (.number(let a), .number(let b)): return a == b ? 0 : (a < b ? -1 : 1)
        case (.date(let a), .date(let b)): return a == b ? 0 : (a < b ? -1 : 1)
        case (.bool(let a), .bool(let b)): return a == b ? 0 : (!a ? -1 : 1)
        case (.link(let p1, let n1), .link(let p2, let n2)):
            if !p1.isEmpty && p1 == p2 { return 0 }
            return n1.localizedStandardCompare(n2).rawValue
        default:
            return text.localizedStandardCompare(o.text).rawValue
        }
    }

    static let day: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    static let iso: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; return f
    }()
}

public struct BaseRowView: Sendable, Equatable, Identifiable {
    public var id: String { path }
    public var path: String
    public var name: String
    public var isNote: Bool
    public var cells: [String: BaseValue]
    public var coverPath: String?
    public init(path: String, name: String, isNote: Bool, cells: [String: BaseValue], coverPath: String?) {
        self.path = path; self.name = name; self.isNote = isNote; self.cells = cells; self.coverPath = coverPath
    }
}

public struct BaseGroup: Sendable, Equatable, Identifiable {
    public var id: String { title }
    public var title: String
    public var rows: [BaseRowView]
    public init(title: String, rows: [BaseRowView]) { self.title = title; self.rows = rows }
}

public struct BaseResult: Sendable {
    public var view: BaseView
    public var columns: [BaseColumn]
    public var rows: [BaseRowView]
    public var groups: [BaseGroup]?
    public var warnings: [String]
    public var total: Int
    public init(view: BaseView, columns: [BaseColumn], rows: [BaseRowView], groups: [BaseGroup]?, warnings: [String], total: Int) {
        self.view = view; self.columns = columns; self.rows = rows; self.groups = groups
        self.warnings = warnings; self.total = total
    }
}

/// A file in the vault as seen by a base: a note, or any other attachment.
public struct BaseItem: Sendable {
    public var path: String
    public var name: String
    public var filename: String
    public var folder: String
    public var ext: String
    public var mtime: Date
    public var ctime: Date
    public var size: Int
    public var tags: [String]
    public var links: [String]
    public var properties: Frontmatter
    public var isNote: Bool
    public init(path: String, name: String, filename: String, folder: String, ext: String, mtime: Date, ctime: Date, size: Int, tags: [String], links: [String], properties: Frontmatter, isNote: Bool) {
        self.path = path; self.name = name; self.filename = filename; self.folder = folder; self.ext = ext
        self.mtime = mtime; self.ctime = ctime; self.size = size; self.tags = tags; self.links = links
        self.properties = properties; self.isNote = isNote
    }
}

public enum Bases {
    public static func parse(_ text: String) -> BaseFile {
        var warnings: [String] = []
        let root = YAML.parse(text, warnings: &warnings)
        let map = root.map ?? [:]
        let formulas = (map["formulas"]?.map ?? [:]).compactMapValues { $0.string }
        var props: [String: BasePropertyConfig] = [:]
        for (k, v) in map["properties"]?.map ?? [:] {
            props[k] = BasePropertyConfig(displayName: v.map?["displayName"]?.string ?? v.string)
        }
        var file = BaseFile(
            name: map["name"]?.string,
            formulas: formulas,
            properties: props,
            filters: filter(map["filters"], warnings: &warnings),
            views: [],
            warnings: warnings
        )
        let rawViews = map["views"]?.list ?? []
        if rawViews.isEmpty { warnings.append("This base has no views.") }
        file.views = rawViews.enumerated().map { i, v in view(v, index: i, properties: &file.properties, warnings: &warnings) }
        file.warnings = warnings
        return file
    }

    public static func items(in snap: VaultSnapshot) -> [BaseItem] {
        var out: [BaseItem] = []
        out.reserveCapacity(snap.notes.count + snap.attachments.count)
        for n in snap.notes.values {
            let filename = (n.path as NSString).lastPathComponent
            let ext = (filename as NSString).pathExtension
            out.append(BaseItem(
                path: n.path, name: n.name, filename: filename, folder: n.folder, ext: ext,
                mtime: n.mtime, ctime: n.ctime, size: n.size, tags: n.summary.tags,
                links: n.summary.links.map(\.target) + n.summary.markdownLinks,
                properties: n.summary.frontmatter, isNote: true
            ))
        }
        for (p, mtime) in snap.attachments {
            if snap.notes[p] != nil { continue }
            let filename = (p as NSString).lastPathComponent
            let name = (filename as NSString).deletingPathExtension
            let ext = (filename as NSString).pathExtension
            let folder = (p as NSString).deletingLastPathComponent
            out.append(BaseItem(
                path: p, name: name, filename: filename, folder: folder, ext: ext,
                mtime: mtime, ctime: mtime, size: 0, tags: [], links: [],
                properties: .empty, isNote: false
            ))
        }
        return out
    }

    public static func run(_ file: BaseFile, view index: Int, in snap: VaultSnapshot, from current: String? = nil) -> BaseResult {
        let views = file.views
        let view = views.indices.contains(index) ? views[index] : (views.first ?? BaseView(type: "table", name: "Table", filters: .always, order: ["file.name"], sort: [], limit: nil, groupBy: nil, cardSize: nil, coverProperty: nil, indentProperties: false))
        var warnings = file.warnings
        let combined: BaseFilter = {
            switch (file.filters, view.filters) {
            case (.always, let v): return v
            case (let g, .always): return g
            default: return .and([file.filters, view.filters])
            }
        }()
        let ctxBase = EvalCtx(snap: snap, formulas: file.formulas, current: current, item: nil, memo: [:], warnings: [])
        var rows: [BaseRowView] = []
        for item in items(in: snap) {
            var ctx = ctxBase
            ctx.item = item
            let ok = evalFilter(combined, ctx: &ctx)
            warnings.append(contentsOf: ctx.warnings)
            if ok { rows.append(rowView(item, view: view, file: file, ctx: &ctx, snap: snap)) }
        }
        warnings = uniq(warnings)

        if !view.sort.isEmpty {
            rows.sort { a, b in
                for s in view.sort {
                    let c = (a.cells[s.property] ?? .null).compare(b.cells[s.property] ?? .null)
                    if c != 0 { return s.ascending ? c < 0 : c > 0 }
                }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        } else {
            rows.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        let total = rows.count
        if let limit = view.limit, limit >= 0, rows.count > limit { rows = Array(rows.prefix(limit)) }

        let columns = columns(for: view, file: file)
        var groups: [BaseGroup]? = nil
        if let g = view.groupBy {
            var buckets: [(String, [BaseRowView])] = []
            var index: [String: Int] = [:]
            for r in rows {
                let title = (r.cells[g.property] ?? .null).text
                let key = title.isEmpty ? "—" : title
                if let i = index[key] { buckets[i].1.append(r) }
                else { index[key] = buckets.count; buckets.append((key, [r])) }
            }
            buckets.sort { a, b in
                let c = a.0.localizedStandardCompare(b.0).rawValue
                return g.ascending ? c < 0 : c > 0
            }
            groups = buckets.map { BaseGroup(title: $0.0, rows: $0.1) }
        }
        return BaseResult(view: view, columns: columns, rows: rows, groups: groups, warnings: warnings, total: total)
    }

    public static func sort(_ rows: [BaseRowView], by key: String, ascending: Bool) -> [BaseRowView] {
        rows.sorted { a, b in
            let c = (a.cells[key] ?? .null).compare(b.cells[key] ?? .null)
            if c != 0 { return ascending ? c < 0 : c > 0 }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    public static func displayName(_ key: String, in file: BaseFile) -> String {
        if let n = file.properties[key]?.displayName, !n.isEmpty { return n }
        if key.hasPrefix("formula.") { return String(key.dropFirst(8)) }
        if key.hasPrefix("file.") || key.hasPrefix("note.") { return String(key.split(separator: ".").last ?? Substring(key)) }
        return key
    }

    // MARK: - View / filter YAML

    static func view(_ v: YAML.Value, index: Int, properties: inout [String: BasePropertyConfig], warnings: inout [String]) -> BaseView {
        let m = v.map ?? [:]
        let type = m["type"]?.string ?? "table"
        let name = m["name"]?.string ?? "View \(index + 1)"
        var filters = filter(m["filters"], warnings: &warnings)
        if let legacy = m["filter"] { filters = and(filters, legacyFilter(legacy, warnings: &warnings)) }
        var order: [String] = (m["order"]?.list ?? []).compactMap { $0.string }
        if let cols = m["columns"]?.list {
            var keys: [String] = []
            for c in cols {
                guard let cm = c.map else { if let s = c.string { keys.append(s) }; continue }
                let key = cm["property"]?.string ?? cm["key"]?.string ?? ""
                guard !key.isEmpty else { continue }
                keys.append(key)
                if let n = cm["name"]?.string, !n.isEmpty {
                    var cfg = properties[key] ?? BasePropertyConfig()
                    if cfg.displayName == nil { cfg.displayName = n; properties[key] = cfg }
                }
            }
            if order.isEmpty { order = keys }
        }
        if order.isEmpty { order = ["file.name"] }
        let sort = sorts(m["sort"])
        let group = m["groupBy"].flatMap(groupBy)
        let cover = m["cover"]?.string ?? m["image"]?.string ?? m["coverProperty"]?.string
        return BaseView(
            type: type, name: name, filters: filters, order: order, sort: sort,
            limit: m["limit"]?.int, groupBy: group, cardSize: m["cardSize"]?.number,
            coverProperty: cover, indentProperties: m["indentProperties"]?.bool ?? false
        )
    }

    static func sorts(_ v: YAML.Value?) -> [BaseSort] {
        guard let v, v != .null else { return [] }
        if let s = v.string { return [BaseSort(property: s, ascending: true)] }
        if let m = v.map { return groupBy(v).map { [$0] } ?? (m["property"]?.string).map { [BaseSort(property: $0, ascending: dir(m["direction"]?.string))] } ?? [] }
        return (v.list ?? []).compactMap { item in
            if let s = item.string { return BaseSort(property: s, ascending: true) }
            let m = item.map ?? [:]
            guard let p = m["property"]?.string ?? m["by"]?.string else { return nil }
            return BaseSort(property: p, ascending: dir(m["direction"]?.string ?? m["dir"]?.string))
        }
    }

    static func groupBy(_ v: YAML.Value) -> BaseSort? {
        if let s = v.string { return BaseSort(property: s, ascending: true) }
        let m = v.map ?? [:]
        guard let p = m["property"]?.string else { return nil }
        return BaseSort(property: p, ascending: dir(m["direction"]?.string))
    }

    static func dir(_ s: String?) -> Bool {
        guard let s else { return true }
        return s.lowercased() != "desc" && s.lowercased() != "descending" && s != "1"
    }

    static func filter(_ v: YAML.Value?, warnings: inout [String]) -> BaseFilter {
        guard let v, v != .null else { return .always }
        if let s = v.string { return s.trimmingCharacters(in: .whitespaces).isEmpty ? .always : .expression(s) }
        if let m = v.map {
            if let a = m["and"] { return .and(listFilters(a, warnings: &warnings)) }
            if let o = m["or"] { return .or(listFilters(o, warnings: &warnings)) }
            if let n = m["not"] { return .not(listFilters(n, warnings: &warnings)) }
            if m["property"] != nil { return legacyFilter(v, warnings: &warnings) }
        }
        if let l = v.list { return .and(listFilters(.list(l), warnings: &warnings)) }
        return .always
    }

    static func listFilters(_ v: YAML.Value, warnings: inout [String]) -> [BaseFilter] {
        (v.list ?? [v]).map { filter($0, warnings: &warnings) }
    }

    static func and(_ a: BaseFilter, _ b: BaseFilter) -> BaseFilter {
        switch (a, b) {
        case (.always, let x), (let x, .always): return x
        case (.and(let xs), .and(let ys)): return .and(xs + ys)
        case (.and(let xs), let y): return .and(xs + [y])
        case (let x, .and(let ys)): return .and([x] + ys)
        default: return .and([a, b])
        }
    }

    static func legacyFilter(_ v: YAML.Value, warnings: inout [String]) -> BaseFilter {
        let m = v.map ?? [:]
        guard let prop = m["property"]?.string, !prop.isEmpty else { return .always }
        let op = (m["operator"]?.string ?? "eq").lowercased()
        let val = m["value"]?.string ?? ""
        let rhs = quoteIfNeeded(val)
        let lhs = prop
        let expr: String
        switch op {
        case "eq", "is", "=", "==": expr = "\(lhs) == \(rhs)"
        case "neq", "ne", "isnot", "is_not", "!=", "<>": expr = "\(lhs) != \(rhs)"
        case "gt", ">": expr = "\(lhs) > \(rhs)"
        case "gte", "ge", ">=": expr = "\(lhs) >= \(rhs)"
        case "lt", "<": expr = "\(lhs) < \(rhs)"
        case "lte", "le", "<=": expr = "\(lhs) <= \(rhs)"
        case "contains": expr = "list(\(lhs)).contains(\(rhs))"
        case "startswith", "starts_with", "starts-with": expr = "\(lhs).toString().startsWith(\(rhs))"
        case "endswith", "ends_with", "ends-with": expr = "\(lhs).toString().endsWith(\(rhs))"
        case "isempty", "is_empty", "empty": expr = "!\(lhs)"
        case "isnotempty", "is_not_empty", "notempty": expr = "!!\(lhs)"
        default:
            warnings.append("Unknown filter operator “\(op)” on \(prop).")
            return .always
        }
        return .expression(expr)
    }

    static func quoteIfNeeded(_ s: String) -> String {
        if s.isEmpty { return "\"\"" }
        if Double(s) != nil || s == "true" || s == "false" { return s }
        return "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func columns(for view: BaseView, file: BaseFile) -> [BaseColumn] {
        view.order.map { BaseColumn(key: $0, displayName: displayName($0, in: file)) }
    }

    static func rowView(_ item: BaseItem, view: BaseView, file: BaseFile, ctx: inout EvalCtx, snap: VaultSnapshot) -> BaseRowView {
        var cells: [String: BaseValue] = [:]
        var keys = view.order
        if let g = view.groupBy?.property, !keys.contains(g) { keys.append(g) }
        for k in keys { cells[k] = resolve(k, ctx: &ctx) }
        var cover: String? = nil
        let coverKeys = [view.coverProperty, "cover", "image", "coverImage", "poster", "photo"].compactMap { $0 }
        for k in coverKeys {
            if let p = coverPath(resolve(k, ctx: &ctx), item: item, snap: snap) { cover = p; break }
        }
        return BaseRowView(path: item.path, name: item.name, isNote: item.isNote, cells: cells, coverPath: cover)
    }

    static func coverPath(_ v: BaseValue, item: BaseItem, snap: VaultSnapshot) -> String? {
        func resolveOne(_ raw: String) -> String? {
            var t = raw.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("![[") { t = String(t.dropFirst(3)) }
            if t.hasPrefix("[[") { t = String(t.dropFirst(2)) }
            if t.hasSuffix("]]") { t = String(t.dropLast(2)) }
            if let bar = t.firstIndex(of: "|") { t = String(t[..<bar]) }
            if t.isEmpty { return nil }
            let ext = (t as NSString).pathExtension.lowercased()
            let ok = ["png", "jpg", "jpeg", "gif", "webp", "svg", "avif", "heic", "bmp"].contains(ext) || ext.isEmpty
            guard ok else { return nil }
            if let r = snap.resolve(t, from: item.path), snap.attachments[r] != nil || ext.isEmpty == false { return r }
            if snap.attachments[t] != nil { return t }
            return nil
        }
        switch v {
        case .string(let s): return resolveOne(s)
        case .link(let p, _): return resolveOne(p)
        case .list(let l):
            for x in l { if let p = coverPath(x, item: item, snap: snap) { return p } }
            return nil
        default: return nil
        }
    }

    static func uniq(_ xs: [String]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for x in xs where seen.insert(x).inserted { out.append(x) }
        return out
    }
}

// MARK: - Filter / formula evaluation

extension Bases {
    struct EvalCtx {
        var snap: VaultSnapshot
        var formulas: [String: String]
        var current: String?
        var item: BaseItem?
        var memo: [String: BaseValue]
        var warnings: [String]
        var stack: Set<String> = []
    }

    static func evalFilter(_ f: BaseFilter, ctx: inout EvalCtx) -> Bool {
        switch f {
        case .always: return true
        case .expression(let s):
            let before = ctx.warnings.count
            let v = eval(s, ctx: &ctx)
            if ctx.warnings.count > before { return true } // unknown: don't exclude
            return v.isTruthy
        case .and(let xs): return xs.allSatisfy { evalFilter($0, ctx: &ctx) }
        case .or(let xs): return xs.contains { evalFilter($0, ctx: &ctx) }
        case .not(let xs): return !xs.contains { evalFilter($0, ctx: &ctx) }
        }
    }

    static func resolve(_ key: String, ctx: inout EvalCtx) -> BaseValue {
        eval(key, ctx: &ctx)
    }

    static func eval(_ source: String, ctx: inout EvalCtx) -> BaseValue {
        do {
            let tokens = try tokenize(source)
            var p = Parser(tokens: tokens, src: source)
            let e = try p.expression()
            if !p.atEnd { throw EvalError("Unexpected trailing input in “\(source)”.") }
            return evalExpr(e, ctx: &ctx)
        } catch {
            let msg = (error as? EvalError)?.message ?? "Couldn’t evaluate “\(source)”."
            if !ctx.warnings.contains(msg) { ctx.warnings.append(msg) }
            return .null
        }
    }

    struct EvalError: Error { var message: String; init(_ message: String) { self.message = message } }

    enum Tok: Equatable {
        case ident(String)
        case number(Double)
        case string(String)
        case op(String)
        case lparen, rparen, lbrack, rbrack, comma, dot
    }

    static func tokenize(_ s: String) throws -> [Tok] {
        var i = s.startIndex, out: [Tok] = []
        func peek() -> Character? { i < s.endIndex ? s[i] : nil }
        func adv() { if i < s.endIndex { i = s.index(after: i) } }
        while let c = peek() {
            if c.isWhitespace { adv(); continue }
            if c.isLetter || c == "_" || c == "$" {
                var t = ""
                while let d = peek(), d.isLetter || d.isNumber || d == "_" || d == "-" || d == "$" { t.append(d); adv() }
                out.append(.ident(t)); continue
            }
            if c.isNumber || (c == "." && (s.index(after: i) < s.endIndex && s[s.index(after: i)].isNumber)) {
                var t = ""
                while let d = peek(), d.isNumber || d == "." { t.append(d); adv() }
                guard let n = Double(t) else { throw EvalError("Bad number “\(t)” in “\(s)”.") }
                out.append(.number(n)); continue
            }
            if c == "\"" || c == "'" {
                let q = c; adv()
                var t = ""
                while let d = peek(), d != q {
                    if d == "\\" { adv(); if let e = peek() { t.append(e); adv() }; continue }
                    t.append(d); adv()
                }
                if peek() == q { adv() } else { throw EvalError("Unclosed string in “\(s)”.") }
                out.append(.string(t)); continue
            }
            if c == "(" { out.append(.lparen); adv(); continue }
            if c == ")" { out.append(.rparen); adv(); continue }
            if c == "[" { out.append(.lbrack); adv(); continue }
            if c == "]" { out.append(.rbrack); adv(); continue }
            if c == "," { out.append(.comma); adv(); continue }
            if c == "." { out.append(.dot); adv(); continue }
            let two: String
            if let n = s.index(i, offsetBy: 2, limitedBy: s.endIndex) { two = String(s[i..<n]) } else { two = String(c) }
            if ["==", "!=", ">=", "<=", "&&", "||"].contains(two) { out.append(.op(two)); i = s.index(i, offsetBy: 2); continue }
            if ["+", "-", "*", "/", ">", "<", "!", "=", "&", "|"].contains(String(c)) { out.append(.op(String(c))); adv(); continue }
            throw EvalError("Unexpected “\(c)” in “\(s)”.")
        }
        return out
    }

    indirect enum Expr {
        case lit(BaseValue)
        case ident(String)
        case unary(String, Expr)
        case binary(String, Expr, Expr)
        case member(Expr, String)
        case call(Expr, [Expr])
        case index(Expr, Expr)
    }

    struct Parser {
        let tokens: [Tok]
        let src: String
        var i = 0
        var atEnd: Bool { i >= tokens.count }
        func peek() -> Tok? { i < tokens.count ? tokens[i] : nil }
        mutating func take() -> Tok? { guard i < tokens.count else { return nil }; defer { i += 1 }; return tokens[i] }
        mutating func eat(_ t: Tok) throws {
            guard peek() == t else { throw EvalError("Unexpected token in “\(src)”.") }
            _ = take()
        }
        mutating func expression(_ min: Int = 0) throws -> Expr {
            var left = try prefix()
            while let t = peek() {
                let (prec, rightAssoc, op) = infix(t)
                if prec < min { break }
                _ = take()
                let next = prec + (rightAssoc ? 0 : 1)
                let right = try expression(next)
                left = .binary(op, left, right)
            }
            return left
        }
        func infix(_ t: Tok) -> (Int, Bool, String) {
            switch t {
            case .op("||"): return (1, false, "||")
            case .op("&&"): return (2, false, "&&")
            case .op("=="): return (3, false, "==")
            case .op("!="): return (3, false, "!=")
            case .op("<"): return (4, false, "<")
            case .op(">"): return (4, false, ">")
            case .op("<="): return (4, false, "<=")
            case .op(">="): return (4, false, ">=")
            case .op("+"): return (5, false, "+")
            case .op("-"): return (5, false, "-")
            case .op("*"): return (6, false, "*")
            case .op("/"): return (6, false, "/")
            default: return (-1, false, "")
            }
        }
        mutating func prefix() throws -> Expr {
            if case .op(let o) = peek(), o == "!" || o == "-" {
                _ = take()
                return .unary(o, try prefix())
            }
            return try postfix(try atom())
        }
        mutating func postfix(_ base: Expr) throws -> Expr {
            var e = base
            while true {
                if peek() == .dot {
                    _ = take()
                    guard case .ident(let n) = take() else { throw EvalError("Expected a name after “.” in “\(src)”.") }
                    e = .member(e, n); continue
                }
                if peek() == .lparen {
                    _ = take()
                    var args: [Expr] = []
                    if peek() != .rparen {
                        while true {
                            args.append(try expression())
                            if peek() == .comma { _ = take(); continue }
                            break
                        }
                    }
                    try eat(.rparen)
                    e = .call(e, args); continue
                }
                if peek() == .lbrack {
                    _ = take()
                    let ix = try expression()
                    try eat(.rbrack)
                    e = .index(e, ix); continue
                }
                break
            }
            return e
        }
        mutating func atom() throws -> Expr {
            switch take() {
            case .number(let n): return .lit(.number(n))
            case .string(let s): return .lit(.string(s))
            case .ident(let n):
                switch n {
                case "true": return .lit(.bool(true))
                case "false": return .lit(.bool(false))
                case "null", "nil", "none": return .lit(.null)
                default: return .ident(n)
                }
            case .lparen:
                let e = try expression()
                try eat(.rparen)
                return e
            default: throw EvalError("Expected an expression in “\(src)”.")
            }
        }
    }

    static func evalExpr(_ e: Expr, ctx: inout EvalCtx) -> BaseValue {
        switch e {
        case .lit(let v): return v
        case .ident(let n): return lookup(n, ctx: &ctx)
        case .unary(let o, let x):
            let v = evalExpr(x, ctx: &ctx)
            if o == "!" { return .bool(!v.isTruthy) }
            if o == "-" {
                if case .number(let n) = v { return .number(-n) }
                return .null
            }
            return v
        case .binary(let o, let a, let b):
            if o == "&&" { let l = evalExpr(a, ctx: &ctx); return l.isTruthy ? evalExpr(b, ctx: &ctx) : l }
            if o == "||" { let l = evalExpr(a, ctx: &ctx); return l.isTruthy ? l : evalExpr(b, ctx: &ctx) }
            let l = evalExpr(a, ctx: &ctx), r = evalExpr(b, ctx: &ctx)
            switch o {
            case "==": return .bool(equal(l, r))
            case "!=": return .bool(!equal(l, r))
            case "<": return .bool(l.compare(r) < 0)
            case ">": return .bool(l.compare(r) > 0)
            case "<=": return .bool(l.compare(r) <= 0)
            case ">=": return .bool(l.compare(r) >= 0)
            case "+":
                if case .number(let x) = l, case .number(let y) = r { return .number(x + y) }
                return .string(l.text + r.text)
            case "-":
                if case .number(let x) = l, case .number(let y) = r { return .number(x - y) }
                return .null
            case "*":
                if case .number(let x) = l, case .number(let y) = r { return .number(x * y) }
                return .null
            case "/":
                if case .number(let x) = l, case .number(let y) = r, y != 0 { return .number(x / y) }
                return .null
            default: return .null
            }
        case .member(let base, let name):
            return member(evalExpr(base, ctx: &ctx), name, ctx: &ctx)
        case .call(let cal, let args):
            let argv = args.map { evalExpr($0, ctx: &ctx) }
            if case .ident(let n) = cal { return call(n, argv, recv: nil, ctx: &ctx) }
            if case .member(let base, let name) = cal {
                let recv = evalExpr(base, ctx: &ctx)
                return call(name, argv, recv: recv, ctx: &ctx)
            }
            ctx.warnings.append("Unknown function call.")
            return .null
        case .index(let base, let ix):
            let b = evalExpr(base, ctx: &ctx)
            let i = evalExpr(ix, ctx: &ctx)
            switch (b, i) {
            case (.list(let l), .number(let n)):
                let k = Int(n)
                return l.indices.contains(k) ? l[k] : .null
            case (_, .string(let s)):
                return member(b, s, ctx: &ctx)
            default:
                return .null
            }
        }
    }

    static func equal(_ a: BaseValue, _ b: BaseValue) -> Bool {
        if case .link(let p, let n) = a {
            if case .link(let p2, let n2) = b { return (!p.isEmpty && p == p2) || n == n2 }
            return n == b.text || p == b.text || ((p as NSString).deletingPathExtension as NSString).lastPathComponent == b.text
        }
        if case .link = b { return equal(b, a) }
        if case .list(let l) = a, case .list(let r) = b { return l == r }
        if a.compare(b) == 0 { return true }
        return a.text.lowercased() == b.text.lowercased() && !a.text.isEmpty
    }

    static func lookup(_ name: String, ctx: inout EvalCtx) -> BaseValue {
        switch name {
        case "true": return .bool(true)
        case "false": return .bool(false)
        case "file": return .string("$file") // member() special-cases this sentinel
        case "note": return .string("$note")
        case "formula": return .string("$formula")
        case "this":
            if let p = ctx.current { return .link(path: p, name: ((p as NSString).lastPathComponent as NSString).deletingPathExtension) }
            return .null
        default:
            return member(.string("$note"), name, ctx: &ctx)
        }
    }

    static func member(_ base: BaseValue, _ name: String, ctx: inout EvalCtx) -> BaseValue {
        if case .string("$file") = base { return fileProp(name, ctx: &ctx) }
        if case .string("$note") = base { return noteProp(name, ctx: &ctx) }
        if case .string("$formula") = base { return formula(name, ctx: &ctx) }
        if case .list(let l) = base {
            if name == "length" || name == "count" { return .number(Double(l.count)) }
            return .null
        }
        if case .string(let s) = base, (name == "length" || name == "count") { return .number(Double(s.count)) }
        if case .date(let d) = base {
            if name == "year" { return .number(Double(Calendar.current.component(.year, from: d))) }
            if name == "month" { return .number(Double(Calendar.current.component(.month, from: d))) }
            if name == "day" { return .number(Double(Calendar.current.component(.day, from: d))) }
        }
        return .null
    }

    static func fileProp(_ name: String, ctx: inout EvalCtx) -> BaseValue {
        guard let it = ctx.item else { return .null }
        switch name {
        case "name": return .string(it.name)
        case "filename", "basename": return .string(it.filename)
        case "folder": return .string(it.folder)
        case "ext": return .string(it.ext)
        case "path": return .string(it.path)
        case "size": return .number(Double(it.size))
        case "mtime", "mtimeTs": return .date(it.mtime)
        case "ctime", "ctimeTs": return .date(it.ctime)
        case "tags": return .list(it.tags.map { .string($0) })
        case "link": return .link(path: it.path, name: it.name)
        default: return .null
        }
    }

    static func noteProp(_ name: String, ctx: inout EvalCtx) -> BaseValue {
        if name == "name" { return fileProp("name", ctx: &ctx) }
        if name == "path" { return fileProp("path", ctx: &ctx) }
        guard let it = ctx.item else { return .null }
        if let p = it.properties[name] { return fromProp(p, path: it.path, name: it.name) }
        // common aliases
        if name == "file" { return .string("$file") }
        return .null
    }

    static func fromProp(_ p: PropertyValue, path: String, name: String) -> BaseValue {
        switch p {
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("[["), t.hasSuffix("]]") {
                var inner = String(t.dropFirst(2).dropLast(2))
                var alias: String? = nil
                if let bar = inner.firstIndex(of: "|") { alias = String(inner[inner.index(after: bar)...]); inner = String(inner[..<bar]) }
                let n = alias ?? ((inner as NSString).lastPathComponent as NSString).deletingPathExtension
                return .link(path: inner, name: n)
            }
            if let d = BaseValue.day.date(from: t) ?? BaseValue.iso.date(from: t) { return .date(d) }
            return .string(s)
        case .number(let n): return .number(n)
        case .bool(let b): return .bool(b)
        case .list(let l): return .list(l.map { fromProp(.string($0), path: path, name: name) })
        }
    }

    static func formula(_ name: String, ctx: inout EvalCtx) -> BaseValue {
        if let v = ctx.memo[name] { return v }
        guard let src = ctx.formulas[name] else {
            ctx.warnings.append("Unknown formula “\(name)”.")
            return .null
        }
        if ctx.stack.contains(name) {
            ctx.warnings.append("Circular formula “\(name)”.")
            return .null
        }
        ctx.stack.insert(name)
        let v = eval(src, ctx: &ctx)
        ctx.stack.remove(name)
        ctx.memo[name] = v
        return v
    }

    static func call(_ name: String, _ args: [BaseValue], recv: BaseValue?, ctx: inout EvalCtx) -> BaseValue {
        // Global functions (no receiver, or called as if()).
        if recv == nil {
            switch name {
            case "if":
                let cond = args.first?.isTruthy ?? false
                if cond { return args.count > 1 ? args[1] : .null }
                return args.count > 2 ? args[2] : .null
            case "list":
                if args.count == 1, case .list(let l) = args[0] { return .list(l) }
                return .list(args)
            case "link":
                let t = args.first?.text ?? ""
                let n = args.count > 1 ? args[1].text : ((t as NSString).lastPathComponent as NSString).deletingPathExtension
                let p = ctx.snap.resolve(t, from: ctx.item?.path ?? ctx.current) ?? t
                return .link(path: p, name: n.isEmpty ? t : n)
            case "now": return .date(Date())
            case "today":
                let d = Calendar.current.startOfDay(for: Date())
                return .date(d)
            case "date":
                if case .date(let d) = args.first { return .date(d) }
                if let s = args.first?.text, let d = BaseValue.day.date(from: s) ?? BaseValue.iso.date(from: s) { return .date(d) }
                return .null
            case "number", "num":
                if case .number(let n) = args.first { return .number(n) }
                if let s = args.first?.text, let n = Double(s) { return .number(n) }
                return .null
            case "string", "str":
                return .string(args.first?.text ?? "")
            default:
                break
            }
            // file.hasTag(...) etc. when written as a member call we handle below; if someone
            // writes hasTag() at the top level, treat it as file.hasTag.
            if let it = ctx.item, fileMethod(name, args, item: it, ctx: &ctx) != nil {
                return fileMethod(name, args, item: it, ctx: &ctx)!
            }
        }

        if let recv {
            if case .string("$file") = recv, let it = ctx.item, let v = fileMethod(name, args, item: it, ctx: &ctx) { return v }
            if case .string("$note") = recv {
                // note.foo is a property; note.foo() isn't used. Fall through to string methods on the property.
            }
            if let v = valueMethod(name, args, recv: recv, ctx: &ctx) { return v }
            ctx.warnings.append("Unknown method “\(name)”.")
            return .null
        }
        ctx.warnings.append("Unknown function “\(name)”.")
        return .null
    }

    static func fileMethod(_ name: String, _ args: [BaseValue], item: BaseItem, ctx: inout EvalCtx) -> BaseValue? {
        switch name {
        case "hasTag":
            let want = (args.first?.text ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "#")).lowercased()
            let ok = item.tags.contains { t in
                let x = t.lowercased()
                return x == want || x.hasPrefix(want + "/")
            }
            return .bool(ok)
        case "hasLink":
            let want = args.first?.text ?? ""
            let resolved = ctx.snap.resolve(want, from: item.path)
            let ok = item.links.contains { l in
                if l == want { return true }
                if let r = ctx.snap.resolve(l, from: item.path), r == resolved { return true }
                let last = (l as NSString).lastPathComponent
                return last == want || (last as NSString).deletingPathExtension == want
            }
            return .bool(ok)
        case "inFolder":
            let folder = (args.first?.text ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if folder.isEmpty { return .bool(item.folder.isEmpty) }
            return .bool(item.folder == folder || item.folder.hasPrefix(folder + "/"))
        case "asLink":
            let n = args.first?.text ?? item.name
            return .link(path: item.path, name: n)
        default:
            return nil
        }
    }

    static func valueMethod(_ name: String, _ args: [BaseValue], recv: BaseValue, ctx: inout EvalCtx) -> BaseValue? {
        // String methods. For file.name we also test the filename-with-extension, so
        // filters like file.name.endsWith("base") and file.name.endsWith(".canvas")
        // (as written in real vaults) still exclude those files.
        func haystacks(_ s: String) -> [String] {
            var hs = [s]
            if let it = ctx.item, s == it.name, it.filename != it.name { hs.append(it.filename) }
            if let it = ctx.item, s == it.folder { hs.append(it.folder) }
            return hs
        }
        let text = recv.text
        switch name {
        case "startsWith", "startswith":
            let n = args.first?.text ?? ""
            return .bool(haystacks(text).contains { $0.hasPrefix(n) || $0.lowercased().hasPrefix(n.lowercased()) })
        case "endsWith", "endswith":
            let n = args.first?.text ?? ""
            return .bool(haystacks(text).contains { $0.hasSuffix(n) || $0.lowercased().hasSuffix(n.lowercased()) })
        case "contains":
            if case .list(let l) = recv {
                let want = args.first ?? .null
                return .bool(l.contains { equal($0, want) } || l.contains { $0.text.localizedCaseInsensitiveContains(want.text) })
            }
            let n = args.first?.text ?? ""
            return .bool(haystacks(text).contains { $0.localizedCaseInsensitiveContains(n) })
        case "containsAny", "containsany":
            let needles = args.flatMap { v -> [String] in
                if case .list(let l) = v { return l.map(\.text) }
                return [v.text]
            }
            let ok = haystacks(text).contains { h in needles.contains { n in !n.isEmpty && h.localizedCaseInsensitiveContains(n) } }
            return .bool(ok)
        case "toString", "tostring", "toString()":
            return .string(text)
        case "toLower", "toLowerCase", "lower":
            return .string(text.lowercased())
        case "toUpper", "toUpperCase", "upper":
            return .string(text.uppercased())
        case "toFixed", "tofixed":
            let digits: Int = { if case .number(let n) = args.first { return Int(n) }; return 0 }()
            if case .number(let n) = recv { return .string(String(format: "%.\(max(0, min(digits, 8)))f", n)) }
            if let n = Double(text) { return .string(String(format: "%.\(max(0, min(digits, 8)))f", n)) }
            return .string(text)
        case "date":
            if case .date(let d) = recv { return .date(Calendar.current.startOfDay(for: d)) }
            return .null
        case "isEmpty", "isempty":
            return .bool(!recv.isTruthy)
        default:
            return nil
        }
    }
}

// MARK: - Small YAML subset (maps, lists, scalars; enough for .base files)

enum YAML {
    enum Value: Equatable {
        case scalar(String)
        case bool(Bool)
        case number(Double)
        case list([Value])
        case map([String: Value])
        case null

        var string: String? {
            switch self {
            case .scalar(let s): return s
            case .bool(let b): return b ? "true" : "false"
            case .number(let n): return n.rounded() == n ? String(Int(n)) : String(n)
            case .null: return nil
            default: return nil
            }
        }
        var bool: Bool? { if case .bool(let b) = self { return b }; if let s = string { return s == "true" || s == "yes" }; return nil }
        var number: Double? { if case .number(let n) = self { return n }; if let s = string { return Double(s) }; return nil }
        var int: Int? { number.map { Int($0) } }
        var list: [Value]? { if case .list(let l) = self { return l }; return nil }
        var map: [String: Value]? { if case .map(let m) = self { return m }; return nil }
    }

    struct Line {
        var indent: Int
        var text: String
        var no: Int
    }

    static func parse(_ text: String, warnings: inout [String]) -> Value {
        let raw = text.replacingOccurrences(of: "\t", with: "  ").components(separatedBy: .newlines)
        var lines: [Line] = []
        for (i, r) in raw.enumerated() {
            var s = r
            if let hash = unquotedHash(s) { s = String(s[..<hash]) }
            let t = s.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            let indent = s.prefix { $0 == " " }.count
            lines.append(Line(indent: indent, text: t, no: i + 1))
        }
        var i = 0
        if lines.isEmpty { return .map([:]) }
        return parseNode(&i, lines: lines, minIndent: lines[0].indent, warnings: &warnings)
    }

    static func unquotedHash(_ s: String) -> String.Index? {
        var quote: Character? = nil
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if let q = quote {
                if c == "\\" { i = s.index(after: i); if i < s.endIndex { i = s.index(after: i) }; continue }
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" { quote = c }
            else if c == "#", i > s.startIndex, s[s.index(before: i)] == " " { return i }
            i = s.index(after: i)
        }
        return nil
    }

    static func parseNode(_ i: inout Int, lines: [Line], minIndent: Int, warnings: inout [String]) -> Value {
        guard i < lines.count else { return .null }
        let line = lines[i]
        if line.text.hasPrefix("- ") || line.text == "-" {
            return parseList(&i, lines: lines, indent: minIndent, warnings: &warnings)
        }
        if line.text.contains(":") {
            return parseMap(&i, lines: lines, indent: minIndent, warnings: &warnings)
        }
        i += 1
        return scalar(line.text)
    }

    static func parseMap(_ i: inout Int, lines: [Line], indent: Int, warnings: inout [String]) -> Value {
        var map: [String: Value] = [:]
        while i < lines.count {
            let line = lines[i]
            if line.indent < indent { break }
            if line.indent > indent { warnings.append("YAML indent skipped on line \(line.no)."); i += 1; continue }
            if line.text.hasPrefix("- ") || line.text == "-" { break }
            guard let colon = firstColon(line.text) else { warnings.append("YAML: missing “:” on line \(line.no)."); i += 1; continue }
            let key = unquote(String(line.text[..<colon]).trimmingCharacters(in: .whitespaces))
            let rest = String(line.text[line.text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            i += 1
            if rest.isEmpty {
                if i < lines.count, lines[i].indent > indent {
                    map[key] = parseNode(&i, lines: lines, minIndent: lines[i].indent, warnings: &warnings)
                } else if i < lines.count, lines[i].indent >= indent, lines[i].text.hasPrefix("- ") || lines[i].text == "-" {
                    // Compact `- or:` / `- and:` / `- not:`: the nested list lines up with the key.
                    map[key] = parseList(&i, lines: lines, indent: lines[i].indent, warnings: &warnings)
                } else {
                    map[key] = .null
                }
            } else {
                map[key] = scalar(rest)
            }
        }
        return .map(map)
    }

    static func parseList(_ i: inout Int, lines: [Line], indent: Int, warnings: inout [String]) -> Value {
        var list: [Value] = []
        while i < lines.count {
            let line = lines[i]
            if line.indent < indent { break }
            if line.indent > indent { warnings.append("YAML indent skipped on line \(line.no)."); i += 1; continue }
            if !(line.text.hasPrefix("- ") || line.text == "-") { break }
            let rest = line.text == "-" ? "" : String(line.text.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            i += 1
            if rest.isEmpty {
                if i < lines.count, lines[i].indent > indent {
                    list.append(parseNode(&i, lines: lines, minIndent: lines[i].indent, warnings: &warnings))
                } else {
                    list.append(.null)
                }
            } else if firstColon(rest) != nil, !isInlineMap(rest) {
                // A list item that starts a map: `- property: note.name`
                var synth = [Line(indent: indent + 2, text: rest, no: line.no)]
                // Nested lists (columns, order, and/or/not) also belong to this map.
                while i < lines.count, lines[i].indent > indent {
                    synth.append(Line(indent: lines[i].indent, text: lines[i].text, no: lines[i].no))
                    i += 1
                }
                var j = 0
                list.append(parseMap(&j, lines: synth, indent: indent + 2, warnings: &warnings))
            } else {
                list.append(scalar(rest))
            }
        }
        return .list(list)
    }

    static func firstColon(_ s: String) -> String.Index? {
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

    static func isInlineMap(_ s: String) -> Bool { s.hasPrefix("{") && s.hasSuffix("}") }

    static func scalar(_ raw: String) -> Value {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t == "~" || t == "null" || t == "Null" || t == "NULL" { return .null }
        if t == "{}" { return .map([:]) }
        if t == "[]" { return .list([]) }
        if t.hasPrefix("[") && t.hasSuffix("]") {
            let inner = String(t.dropFirst().dropLast())
            if inner.trimmingCharacters(in: .whitespaces).isEmpty { return .list([]) }
            return .list(splitComma(inner).map(scalar))
        }
        if t.hasPrefix("{") && t.hasSuffix("}") {
            let inner = String(t.dropFirst().dropLast())
            if inner.trimmingCharacters(in: .whitespaces).isEmpty { return .map([:]) }
            var map: [String: Value] = [:]
            for part in splitComma(inner) {
                guard let c = firstColon(part) else { continue }
                let k = unquote(String(part[..<c]).trimmingCharacters(in: .whitespaces))
                let v = String(part[part.index(after: c)...]).trimmingCharacters(in: .whitespaces)
                map[k] = scalar(v)
            }
            return .map(map)
        }
        if t.hasPrefix("!"), !(t.hasPrefix("! ") || t.hasPrefix("!!")) {
            // YAML tag or a Bases `!expr`. Treat as an expression string.
            return .scalar(t)
        }
        if (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")) {
            return .scalar(unquote(t))
        }
        switch t.lowercased() {
        case "true", "yes", "on": return .bool(true)
        case "false", "no", "off": return .bool(false)
        default: break
        }
        if let n = Double(t), !t.hasPrefix("0") || t == "0" || t.hasPrefix("0.") { return .number(n) }
        return .scalar(unquote(t))
    }

    static func unquote(_ s: String) -> String {
        var t = s
        if t.count >= 2, (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")) {
            let q = t.first!
            t = String(t.dropFirst().dropLast())
            if q == "\"" {
                t = t.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
            }
        }
        return t
    }

    static func splitComma(_ s: String) -> [String] {
        var out: [String] = [], cur = "", quote: Character? = nil, depth = 0
        for c in s {
            if let q = quote { cur.append(c); if c == q { quote = nil }; continue }
            if c == "\"" || c == "'" { quote = c; cur.append(c); continue }
            if c == "[" || c == "{" { depth += 1 }
            if c == "]" || c == "}" { depth -= 1 }
            if c == "," && depth <= 0 { out.append(cur.trimmingCharacters(in: .whitespaces)); cur = ""; continue }
            cur.append(c)
        }
        if !cur.trimmingCharacters(in: .whitespaces).isEmpty { out.append(cur.trimmingCharacters(in: .whitespaces)) }
        return out
    }
}
