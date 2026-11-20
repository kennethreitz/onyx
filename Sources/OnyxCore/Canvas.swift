import Foundation

// MARK: - Ordered JSON

/// A JSON value that keeps object key order and the exact text of numbers, so a canvas
/// parsed and written back is byte-identical to what Obsidian wrote (and fields Onyx
/// doesn't know about survive untouched).
public indirect enum JSONValue: Equatable, Sendable {
    case object([(String, JSONValue)])
    case array([JSONValue])
    case string(String)
    case number(String)        // the literal as written, e.g. "-350" or "12.5"
    case bool(Bool)
    case null

    public static func == (a: JSONValue, b: JSONValue) -> Bool {
        switch (a, b) {
        case (.object(let x), .object(let y)): return x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        case (.array(let x), .array(let y)): return x == y
        case (.string(let x), .string(let y)): return x == y
        case (.number(let x), .number(let y)): return x == y
        case (.bool(let x), .bool(let y)): return x == y
        case (.null, .null): return true
        default: return false
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let kv) = self { return kv.first { $0.0 == key }?.1 }
        return nil
    }
    public var string: String? { if case .string(let s) = self { return s }; return nil }
    public var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    public var double: Double? { if case .number(let n) = self { return Double(n) }; return nil }

    public struct ParseError: Error, CustomStringConvertible {
        public var offset: Int; public var message: String
        public var description: String { "JSON: \(message) at byte \(offset)" }
    }

    public static func parse(_ text: String) throws -> JSONValue {
        var p = Parser(bytes: Array(text.utf8))
        p.skipWS()
        let v = try p.value()
        p.skipWS()
        guard p.i == p.bytes.count else { throw ParseError(offset: p.i, message: "trailing characters") }
        return v
    }

    struct Parser {
        let bytes: [UInt8]
        var i = 0
        mutating func skipWS() { while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 } }
        func fail(_ m: String) -> ParseError { ParseError(offset: i, message: m) }
        mutating func value() throws -> JSONValue {
            guard i < bytes.count else { throw fail("unexpected end") }
            switch bytes[i] {
            case UInt8(ascii: "{"):
                i += 1; skipWS()
                var kv: [(String, JSONValue)] = []
                if i < bytes.count, bytes[i] == UInt8(ascii: "}") { i += 1; return .object(kv) }
                while true {
                    skipWS()
                    guard i < bytes.count, bytes[i] == UInt8(ascii: "\"") else { throw fail("expected key") }
                    let k = try str()
                    skipWS()
                    guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else { throw fail("expected :") }
                    i += 1; skipWS()
                    kv.append((k, try value()))
                    skipWS()
                    guard i < bytes.count else { throw fail("unexpected end") }
                    if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                    if bytes[i] == UInt8(ascii: "}") { i += 1; return .object(kv) }
                    throw fail("expected , or }")
                }
            case UInt8(ascii: "["):
                i += 1; skipWS()
                var a: [JSONValue] = []
                if i < bytes.count, bytes[i] == UInt8(ascii: "]") { i += 1; return .array(a) }
                while true {
                    skipWS()
                    a.append(try value())
                    skipWS()
                    guard i < bytes.count else { throw fail("unexpected end") }
                    if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                    if bytes[i] == UInt8(ascii: "]") { i += 1; return .array(a) }
                    throw fail("expected , or ]")
                }
            case UInt8(ascii: "\""): return .string(try str())
            case UInt8(ascii: "t"): try lit("true"); return .bool(true)
            case UInt8(ascii: "f"): try lit("false"); return .bool(false)
            case UInt8(ascii: "n"): try lit("null"); return .null
            default:
                let s = i
                while i < bytes.count, "+-0123456789.eE".utf8.contains(bytes[i]) { i += 1 }
                guard i > s, let t = String(bytes: bytes[s..<i], encoding: .utf8), Double(t) != nil else { throw fail("bad value") }
                return .number(t)
            }
        }
        mutating func lit(_ w: String) throws {
            let u = Array(w.utf8)
            guard i + u.count <= bytes.count, Array(bytes[i..<(i + u.count)]) == u else { throw fail("bad literal") }
            i += u.count
        }
        mutating func hex4() throws -> UInt32 {
            guard i + 4 <= bytes.count, let s = String(bytes: bytes[i..<(i + 4)], encoding: .ascii), let v = UInt32(s, radix: 16) else { throw fail("bad \\u escape") }
            i += 4; return v
        }
        mutating func str() throws -> String {
            i += 1   // opening quote
            var out = [UInt8]()
            while true {
                guard i < bytes.count else { throw fail("unterminated string") }
                let c = bytes[i]
                if c == UInt8(ascii: "\"") { i += 1; break }
                if c != UInt8(ascii: "\\") { out.append(c); i += 1; continue }
                i += 1
                guard i < bytes.count else { throw fail("bad escape") }
                let e = bytes[i]; i += 1
                switch e {
                case UInt8(ascii: "\""): out.append(0x22)
                case UInt8(ascii: "\\"): out.append(0x5C)
                case UInt8(ascii: "/"): out.append(0x2F)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"):
                    var cp = try hex4()
                    if (0xD800...0xDBFF).contains(cp), i + 6 <= bytes.count, bytes[i] == UInt8(ascii: "\\"), bytes[i + 1] == UInt8(ascii: "u") {
                        let save = i
                        i += 2
                        let lo = try hex4()
                        if (0xDC00...0xDFFF).contains(lo) { cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00) } else { i = save }
                    }
                    let scalar = Unicode.Scalar(cp) ?? "\u{FFFD}"
                    out.append(contentsOf: Array(String(Character(scalar)).utf8))
                default: throw fail("bad escape")
                }
            }
            return String(decoding: out, as: UTF8.self)
        }
    }

    /// Compact text exactly like JavaScript's JSON.stringify (no spaces; only `"`, `\` and
    /// control characters escaped; non-ASCII written as is).
    public var compact: String { var s = ""; write(into: &s); return s }

    func write(into s: inout String) {
        switch self {
        case .object(let kv):
            s += "{"
            for (n, (k, v)) in kv.enumerated() {
                if n > 0 { s += "," }
                JSONValue.quote(k, into: &s); s += ":"; v.write(into: &s)
            }
            s += "}"
        case .array(let a):
            s += "["
            for (n, v) in a.enumerated() { if n > 0 { s += "," }; v.write(into: &s) }
            s += "]"
        case .string(let t): JSONValue.quote(t, into: &s)
        case .number(let n): s += n
        case .bool(let b): s += b ? "true" : "false"
        case .null: s += "null"
        }
    }

    static func quote(_ t: String, into s: inout String) {
        s += "\""
        for u in t.unicodeScalars {
            switch u {
            case "\"": s += "\\\""
            case "\\": s += "\\\\"
            case "\u{08}": s += "\\b"
            case "\u{0C}": s += "\\f"
            case "\n": s += "\\n"
            case "\r": s += "\\r"
            case "\t": s += "\\t"
            default:
                if u.value < 0x20 { s += String(format: "\\u%04x", u.value) } else { s.unicodeScalars.append(u) }
            }
        }
        s += "\""
    }
}

// MARK: - JSON Canvas files (https://jsoncanvas.org)

public enum CanvasFile {
    /// Canvas text the way Obsidian writes it: tab-indented top level, one compact node or
    /// edge per line, no trailing newline.
    public static func format(_ v: JSONValue) -> String {
        guard case .object(let kv) = v else { return v.compact }
        if kv.isEmpty { return "{}" }
        var s = "{\n"
        for (n, (k, val)) in kv.enumerated() {
            s += "\t"; JSONValue.quote(k, into: &s); s += ":"
            if case .array(let items) = val, !items.isEmpty {
                s += "[\n"
                for (j, it) in items.enumerated() { s += "\t\t"; it.write(into: &s); if j < items.count - 1 { s += "," }; s += "\n" }
                s += "\t]"
            } else {
                val.write(into: &s)
            }
            s += n < kv.count - 1 ? ",\n" : "\n"
        }
        return s + "}"
    }

    /// Parse canvas text; an empty file (a canvas Obsidian just created) is an empty canvas.
    public static func parse(_ text: String) throws -> JSONValue {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .object([("nodes", .array([])), ("edges", .array([]))]) }
        return try JSONValue.parse(text)
    }

    /// Re-format any JSON text (e.g. JSON.stringify from the canvas page) in Obsidian's layout.
    public static func normalize(_ json: String) throws -> String { format(try JSONValue.parse(json)) }

    /// Point file nodes at moved files. `newPath` gets each node's `file` and returns its new
    /// vault path (nil = unchanged). Returns the rewritten text, or nil when nothing moved.
    /// Only the `file` values change; everything else is kept byte for byte.
    public static func rewriteFiles(_ text: String, _ newPath: (String) -> String?) -> String? {
        guard case .object(var top)? = try? parse(text) else { return nil }
        var changed = false
        for (ti, (k, v)) in top.enumerated() where k == "nodes" {
            guard case .array(var nodes) = v else { continue }
            for (ni, n) in nodes.enumerated() {
                guard case .object(var kv) = n, n["type"]?.string == "file",
                      let fi = kv.firstIndex(where: { $0.0 == "file" }), let f = kv[fi].1.string,
                      let np = newPath(f), np != f else { continue }
                kv[fi].1 = .string(np); nodes[ni] = .object(kv); changed = true
            }
            top[ti].1 = .array(nodes)
        }
        return changed ? format(.object(top)) : nil
    }

    /// What a canvas links to: its file nodes, plus [[links]] written in its text cards.
    public static func summarize(_ text: String) -> CanvasSummary {
        guard let v = try? parse(text) else { return CanvasSummary() }
        var out = CanvasSummary()
        for n in v["nodes"]?.array ?? [] {
            switch n["type"]?.string {
            case "file": if let f = n["file"]?.string, !f.isEmpty { out.files.append(f) }
            case "text": if let t = n["text"]?.string { out.links += NoteParser.parseWikiLinks(t).map(\.target).filter { !$0.isEmpty } }
            default: break
            }
        }
        out.nodeCount = v["nodes"]?.array?.count ?? 0
        out.edgeCount = v["edges"]?.array?.count ?? 0
        return out
    }
}

public struct CanvasSummary: Sendable, Equatable {
    /// Vault paths of file nodes, as written (Obsidian stores full vault-relative paths).
    public var files: [String] = []
    /// Wikilink targets inside text nodes.
    public var links: [String] = []
    public var nodeCount = 0
    public var edgeCount = 0
    public init() {}
}

public extension String {
    var isCanvasPath: Bool { lowercased().hasSuffix(".canvas") }
}
