import Foundation

/// Standard Markdown links and embeds (`[text](dest)`, `![alt](dest)`) for rename/move:
/// find the vault file each one points at, and re-express it after files move, keeping the
/// link's own style: relative (`../x.md`, `./x.md`), vault-absolute (`Folder/x.md`, `/Folder/x.md`)
/// or bare name, URL-encoded (`%20`) or raw or `<angle>`, with `#heading` anchors and titles intact.
public enum MarkdownLinks {
    static let link = try! NSRegularExpression(pattern:
        #"(!?)\[(?:[^\[\]\n]|\[[^\]\n]*\])*\]\([ \t]*(<[^>\n]*>|[^\s()<>]*(?:\([^\s()]*\)[^\s()<>]*)*)(?:[ \t]+(?:"[^"\n]*"|'[^'\n]*'|\([^)\n]*\)))?[ \t]*\)"#)
    static let fence = try! NSRegularExpression(pattern: #"(?ms)^[ \t]*(```|~~~).*?^[ \t]*\1[^\n]*$"#)
    static let codeSpan = try! NSRegularExpression(pattern: #"(`+)[^`\n].*?\1"#)
    static let comment = try! NSRegularExpression(pattern: #"(?s)%%.*?%%|<!--.*?-->"#)

    enum Style: Equatable { case relative(dot: Bool), vault(slash: Bool), name }

    /// Destination ranges (inside the parentheses) of every local link, outside code and comments.
    public static func destinations(in text: String) -> [NSRange] {
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        let skip = (fence.matches(in: text, range: all) + codeSpan.matches(in: text, range: all) + comment.matches(in: text, range: all)).map(\.range)
        return link.matches(in: text, range: all).compactMap { m in
            let r = m.range(at: 2)
            guard r.location != NSNotFound, r.length > 0, !skip.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) else { return nil }
            return r
        }
    }

    static func isExternal(_ p: String) -> Bool {
        p.hasPrefix("#") || p.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) != nil
    }

    /// `a/b/../c` → `a/c`; nil if it climbs out of the vault.
    public static func normalize(_ p: String) -> String? {
        var out: [Substring] = []
        for c in p.split(separator: "/", omittingEmptySubsequences: true) {
            if c == "." { continue }
            if c == ".." { if out.isEmpty { return nil }; out.removeLast() } else { out.append(c) }
        }
        return out.joined(separator: "/")
    }

    public static func relative(from dir: String, to path: String) -> String {
        let a = dir.split(separator: "/").map(String.init), b = path.split(separator: "/").map(String.init)
        var i = 0
        while i < a.count, i < b.count - 1, a[i] == b[i] { i += 1 }
        return (Array(repeating: "..", count: a.count - i) + b[i...]).joined(separator: "/")
    }

    static let encodeAllowed: CharacterSet = {
        var s = CharacterSet.alphanumerics; s.insert(charactersIn: "-._~/!$&'*+,;=:@"); return s
    }()

    /// Rewrite the Markdown links of a note that lives (or lived) at `oldNote` and now lives at
    /// `newNote`. `exists` answers for vault paths as they were before the move, `resolveName`
    /// finds a bare file name, `moved` maps old vault paths to new ones. nil = nothing changed.
    public static func rewrite(_ text: String, oldNote: String, newNote: String,
                               exists: (String) -> Bool, resolveName: (String) -> String?, moved: (String) -> String?) -> String? {
        let oldDir = (oldNote as NSString).deletingLastPathComponent, newDir = (newNote as NSString).deletingLastPathComponent
        var out = text as NSString
        var changed = false
        for r in destinations(in: text).reversed() {
            let raw = out.substring(with: r)
            let angle = raw.hasPrefix("<") && raw.hasSuffix(">")
            let dest = angle ? String(raw.dropFirst().dropLast()) : raw
            guard !dest.isEmpty, !isExternal(dest) else { continue }
            let hash = dest.firstIndex(of: "#")
            let pathPart = hash.map { String(dest[..<$0]) } ?? dest
            let anchor = hash.map { String(dest[$0...]) } ?? ""
            guard !pathPart.isEmpty else { continue }
            let encoded = pathPart.contains("%")
            let decoded = pathPart.removingPercentEncoding ?? pathPart
            // find the file, the way Obsidian does: relative to the note, then from the vault root, then by name
            func hit(_ p: String?) -> (String, Bool)? {
                guard let p, !p.isEmpty else { return nil }
                if exists(p) { return (p, false) }
                if (p as NSString).pathExtension.isEmpty, exists(p + ".md") { return (p + ".md", true) }
                return nil
            }
            var target: (path: String, addedExt: Bool)?
            var style: Style
            if decoded.hasPrefix("/") {
                style = .vault(slash: true); target = hit(normalize(decoded)).map { ($0.0, $0.1) }
            } else if let t = hit(normalize(oldDir.isEmpty ? decoded : oldDir + "/" + decoded)) {
                style = .relative(dot: decoded.hasPrefix("./")); target = t
                if !decoded.contains("/") { style = oldDir.isEmpty ? .vault(slash: false) : .relative(dot: false) }
            } else if let t = hit(normalize(decoded)) {
                style = .vault(slash: false); target = t
            } else if !decoded.contains("/"), let p = resolveName(decoded) ?? resolveName(decoded + ".md") {
                style = .name; target = (p, !decoded.lowercased().hasSuffix((p as NSString).pathExtension.lowercased()))
            } else { continue }
            guard let t = target else { continue }
            let newTarget = moved(t.path) ?? t.path
            if newTarget == t.path && oldDir == newDir { continue }
            var np: String
            switch style {
            case .relative(let dot):
                np = relative(from: newDir, to: newTarget)
                if dot && !np.hasPrefix("../") { np = "./" + np }
            case .vault(let slash):
                // a root-level note's "x.md" was relative too: keep it relative once the note moves
                if !slash && oldDir.isEmpty && !decoded.contains("/") && newDir != "" { np = relative(from: newDir, to: newTarget) }
                else { np = (slash ? "/" : "") + newTarget }
            case .name:
                if (newTarget as NSString).lastPathComponent == (t.path as NSString).lastPathComponent { continue }
                np = (newTarget as NSString).lastPathComponent
            }
            if t.addedExt, np.lowercased().hasSuffix(".md") { np = String(np.dropLast(3)) }
            if np == decoded { continue }
            if encoded || (!angle && np.contains(" ")) {
                np = np.addingPercentEncoding(withAllowedCharacters: encodeAllowed) ?? np
            }
            let rebuilt = angle ? "<" + np + anchor + ">" : np + anchor
            guard rebuilt != raw else { continue }
            out = out.replacingCharacters(in: r, with: rebuilt) as NSString
            changed = true
        }
        return changed ? out as String : nil
    }
}
