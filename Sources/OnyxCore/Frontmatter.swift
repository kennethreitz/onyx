import Foundation

/// A frontmatter property value. Onyx keeps YAML as the source of truth and
/// only reads a pragmatic subset: scalars, inline lists and block lists.
public enum PropertyValue: Equatable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case list([String])

    public var display: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n.rounded() == n ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        case .list(let l): return l.joined(separator: ", ")
        }
    }

    public var strings: [String] {
        switch self {
        case .list(let l): return l
        default: return [display]
        }
    }
}

public struct Property: Equatable, Hashable, Sendable {
    public var key: String
    public var value: PropertyValue
    public init(key: String, value: PropertyValue) { self.key = key; self.value = value }
}

public struct Frontmatter: Sendable {
    public var properties: [Property]
    /// UTF-16 offset where the body starts (after the closing ---).
    public var bodyOffset: Int
    /// Number of lines the frontmatter block occupies (0 if none).
    public var lineCount: Int

    public subscript(key: String) -> PropertyValue? {
        properties.first { $0.key.lowercased() == key.lowercased() }?.value
    }

    public static let empty = Frontmatter(properties: [], bodyOffset: 0, lineCount: 0)

    public static func parse(_ text: String) -> Frontmatter {
        guard text.hasPrefix("---") else { return .empty }
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1, lines[0].trimmingCharacters(in: .whitespaces) == "---" else { return .empty }
        var end = -1
        for i in 1..<lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t == "---" || t == "..." { end = i; break }
        }
        guard end > 0 else { return .empty }
        var offset = 0
        for i in 0...end { offset += (lines[i] as NSString).length + 1 }
        offset = min(offset, (text as NSString).length)
        let props = parseYAML(Array(lines[1..<end]))
        return Frontmatter(properties: props, bodyOffset: offset, lineCount: end + 1)
    }

    static func parseYAML(_ lines: [String]) -> [Property] {
        var props: [Property] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            i += 1
            if line.trimmingCharacters(in: .whitespaces).isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix(" ") || line.hasPrefix("\t") || line.hasPrefix("-") { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let rest = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if rest.isEmpty {
                // block list or nested map
                var items: [String] = []
                while i < lines.count {
                    let l = lines[i]
                    let t = l.trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("- ") || t == "-" {
                        items.append(unquote(String(t.dropFirst(1)).trimmingCharacters(in: .whitespaces)))
                        i += 1
                    } else if t.isEmpty || l.hasPrefix(" ") || l.hasPrefix("\t") {
                        i += 1
                    } else { break }
                }
                props.append(Property(key: key, value: items.isEmpty ? .string("") : .list(items)))
            } else if rest.hasPrefix("[") && rest.hasSuffix("]") {
                let inner = rest.dropFirst().dropLast()
                let items = splitInline(String(inner)).map { unquote($0) }.filter { !$0.isEmpty }
                props.append(Property(key: key, value: .list(items)))
            } else {
                props.append(Property(key: key, value: scalar(rest)))
            }
        }
        return props
    }

    static func splitInline(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var quote: Character? = nil
        var depth = 0
        for ch in s {
            if let q = quote { cur.append(ch); if ch == q { quote = nil }; continue }
            if ch == "\"" || ch == "'" { quote = ch; cur.append(ch); continue }
            if ch == "[" { depth += 1 }
            if ch == "]" { depth -= 1 }
            if ch == "," && depth <= 0 { out.append(cur.trimmingCharacters(in: .whitespaces)); cur = ""; continue }
            cur.append(ch)
        }
        if !cur.trimmingCharacters(in: .whitespaces).isEmpty { out.append(cur.trimmingCharacters(in: .whitespaces)) }
        return out
    }

    static func unquote(_ s: String) -> String {
        var t = s
        if let hash = t.range(of: " #"), !(t.hasPrefix("\"") || t.hasPrefix("'")) { t = String(t[..<hash.lowerBound]) }
        if t.count >= 2, (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")) {
            t = String(t.dropFirst().dropLast())
        }
        return t
    }

    static func scalar(_ raw: String) -> PropertyValue {
        let s = unquote(raw)
        if raw.hasPrefix("\"") || raw.hasPrefix("'") { return .string(s) }
        switch s.lowercased() {
        case "true", "yes": return .bool(true)
        case "false", "no": return .bool(false)
        default: break
        }
        if let d = Double(s), !s.hasPrefix("0") || s == "0" || s.hasPrefix("0.") { return .number(d) }
        return .string(s)
    }
}
