import Foundation

/// The text side of Onyx's git sync: commit messages, error classification, conflict names.
/// Pure so it can be tested; GitSync (app target) runs the commands.
public enum GitText {
    public struct Change: Equatable, Sendable {
        public var status: Character         // M A D R (C/T/U treated as M)
        public var path: String
        public var from: String?             // renames
        public init(status: Character, path: String, from: String? = nil) { self.status = status; self.path = path; self.from = from }
    }

    /// `git diff --cached --name-status -M` (tab-separated) → changes.
    public static func parseNameStatus(_ out: String) -> [Change] {
        out.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 2, let s = f[0].first else { return nil }
            if s == "R" || s == "C", f.count >= 3 { return Change(status: s == "R" ? "R" : "A", path: f[2], from: f[1]) }
            return Change(status: "MADT".contains(s) ? (s == "T" ? "M" : s) : "M", path: f[1])
        }
    }

    static func title(_ p: String) -> String {
        let last = (p as NSString).lastPathComponent
        return last.lowercased().hasSuffix(".md") ? String(last.dropLast(3)) : last
    }

    /// "Edit Mercury", "Edit Mercury, Venus", "Add Today; edit Mercury", "Rename A → B",
    /// "Delete Old Note", "Edit 7 notes: A, B, C, …". At most ~72 chars for the subject.
    public static func commitMessage(_ changes: [Change], reason: String? = nil) -> String {
        guard !changes.isEmpty else { return reason ?? "Onyx: sync" }
        if let reason, !reason.isEmpty { return clip(reason) + body(changes) }
        var groups: [(String, [String])] = []
        func add(_ verb: String, _ s: String) {
            if let i = groups.firstIndex(where: { $0.0 == verb }) { groups[i].1.append(s) } else { groups.append((verb, [s])) }
        }
        for c in changes {
            switch c.status {
            case "A": add("Add", title(c.path))
            case "D": add("Delete", title(c.path))
            case "R":
                let from = c.from ?? ""
                let moved = (from as NSString).deletingLastPathComponent != (c.path as NSString).deletingLastPathComponent
                let renamed = title(from) != title(c.path)
                if renamed && !moved { add("Rename", "\(title(from)) → \(title(c.path))") }
                else if moved && !renamed { add("Move", "\(title(c.path)) → \(dir(c.path))") }
                else { add("Move", "\(title(from)) → \(c.path.hasSuffix(".md") ? String(c.path.dropLast(3)) : c.path)") }
            default: add("Edit", title(c.path))
            }
        }
        let subject = groups.enumerated().map { i, g in
            let verb = i == 0 ? g.0 : g.0.lowercased()
            if g.1.count > 3 { return "\(verb) \(g.1.count) notes: \(g.1.prefix(3).joined(separator: ", ")), …" }
            return "\(verb) \(g.1.joined(separator: ", "))"
        }.joined(separator: "; ")
        return clip(subject) + (changes.count > 1 || subject.count > 72 ? body(changes) : "")
    }
    static func dir(_ p: String) -> String { let d = (p as NSString).deletingLastPathComponent; return d.isEmpty ? "/" : d }
    static func clip(_ s: String) -> String { s.count <= 72 ? s : String(s.prefix(71)) + "…" }
    static func body(_ changes: [Change]) -> String {
        "\n\n" + changes.prefix(40).map { c in c.from.map { "\(c.status) \($0) → \(c.path)" } ?? "\(c.status) \(c.path)" }.joined(separator: "\n")
            + (changes.count > 40 ? "\n… and \(changes.count - 40) more" : "")
    }

    /// Network or remote trouble that's worth retrying later (as opposed to a real refusal).
    public static func isNetworkError(_ stderr: String) -> Bool {
        let s = stderr.lowercased()
        return ["could not resolve host", "unable to access", "connection timed out", "operation timed out", "network is unreachable",
                "could not read from remote", "connection refused", "connection reset", "no route to host", "temporary failure",
                "ssl_connect", "the remote end hung up", "early eof", "timed out"].contains { s.contains($0) }
    }
    /// A push refused because the remote moved on (pull, then push again).
    public static func isNonFastForward(_ stderr: String) -> Bool {
        let s = stderr.lowercased()
        return s.contains("non-fast-forward") || s.contains("fetch first") || s.contains("[rejected]") || s.contains("updates were rejected")
    }

    /// "Notes/Mercury.md" → "Notes/Mercury (conflict 2026-11-20 1432).md"; numbered if taken.
    public static func conflictCopy(_ path: String, date: Date = Date(), exists: (String) -> Bool = { _ in false }) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HHmm"
        let ext = (path as NSString).pathExtension
        let base = ext.isEmpty ? path : String(path.dropLast(ext.count + 1))
        let tail = ext.isEmpty ? "" : "." + ext
        var p = "\(base) (conflict \(f.string(from: date)))\(tail)"
        var n = 2
        while exists(p) { p = "\(base) (conflict \(f.string(from: date)) \(n))\(tail)"; n += 1 }
        return p
    }

    /// Retry delay after `failures` consecutive network failures: 5s, 10s, 20s … capped at 5 min.
    public static func backoff(_ failures: Int) -> TimeInterval { min(300, 5 * pow(2, Double(max(0, failures - 1)))) }
}
