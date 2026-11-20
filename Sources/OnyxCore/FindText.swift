import Foundation

/// Literal find for ⌘F (UTF-16 ranges, as NSTextView wants them).
public enum FindText {
    /// Every literal match, non-overlapping, in document order.
    public static func ranges(of q: String, in s: String, caseSensitive: Bool) -> [NSRange] {
        guard !q.isEmpty else { return [] }
        let ns = s as NSString
        var out: [NSRange] = []
        var from = 0
        let opts: NSString.CompareOptions = caseSensitive ? [.literal] : [.literal, .caseInsensitive]
        while from < ns.length {
            let r = ns.range(of: q, options: opts, range: NSRange(location: from, length: ns.length - from))
            if r.location == NSNotFound { break }
            out.append(r)
            from = NSMaxRange(r) > r.location ? NSMaxRange(r) : r.location + 1
        }
        return out
    }
}

