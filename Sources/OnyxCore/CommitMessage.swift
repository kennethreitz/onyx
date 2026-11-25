import Foundation

extension GitText {
    /// A staged or working-tree change plus the old/new text when the file is readable.
    public struct FileEdit: Equatable, Sendable {
        public var change: Change
        public var oldText: String?
        public var newText: String?
        public init(change: Change, oldText: String? = nil, newText: String? = nil) {
            self.change = change; self.oldText = oldText; self.newText = newText
        }
    }

    public static func commitMessage(_ changes: [Change], reason: String? = nil) -> String {
        commitMessage(changes.map { FileEdit(change: $0) }, reason: reason)
    }

    /// Descriptive subject (≤72 characters) from the changes and, when texts are present,
    /// from a deterministic on-device summary of headings, tasks, frontmatter, and links.
    /// Multi-file commits keep a short subject and list per-file details in the body.
    public static func commitMessage(_ files: [FileEdit], reason: String? = nil) -> String {
        let changes = files.map(\.change)
        guard !files.isEmpty else { return reason ?? "Onyx: sync" }
        if let reason, !reason.isEmpty { return clip(reason) + body(changes) }

        let details = files.compactMap { file -> String? in
            guard let phrase = phrase(for: file) else { return nil }
            return "\(title(file.change.path)): \(phrase)"
        }

        if files.count == 1, let file = files.first, let phrase = phrase(for: file), isModified(file.change) {
            let raw = "Update \(title(file.change.path)): \(phrase)"
            if raw.count <= 72 { return raw }
            return clip("Update \(title(file.change.path))") + "\n\n" + details.joined(separator: "\n")
        }

        let subject = groupedSubject(changes)
        var out = clip(subject)
        if files.count > 1 || subject.count > 72 {
            out += details.isEmpty ? body(changes) : "\n\n" + details.joined(separator: "\n")
        } else if !details.isEmpty, !isModified(files[0].change) {
            out += "\n\n" + details.joined(separator: "\n")
        }
        return out
    }

    static func isModified(_ c: Change) -> Bool {
        c.status != "A" && c.status != "D" && c.status != "R"
    }

    static func groupedSubject(_ changes: [Change]) -> String {
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
        return groups.enumerated().map { i, g in
            let verb = i == 0 ? g.0 : g.0.lowercased()
            if g.1.count > 3 { return "\(verb) \(g.1.count) notes: \(g.1.prefix(3).joined(separator: ", ")), …" }
            return "\(verb) \(g.1.joined(separator: ", "))"
        }.joined(separator: "; ")
    }

    // MARK: - Per-file phrase

    static func phrase(for file: FileEdit) -> String? {
        let path = file.change.path
        guard isMarkdown(path) else { return nil }
        switch file.change.status {
        case "A", "D":
            // The subject already says Add/Delete plus the title.
            return nil
        default:
            guard let old = file.oldText, let new = file.newText, old != new else { return nil }
            return phrase(from: summarize(old: old, new: new))
        }
    }

    static func isMarkdown(_ path: String) -> Bool {
        path.lowercased().hasSuffix(".md")
    }

    struct NoteDelta {
        var headingsAdded: [String] = []
        var headingsRemoved: [String] = []
        var headingsEdited: [(String, String)] = []
        var tasksAdded = 0
        var tasksRemoved = 0
        var tasksChecked = 0
        var tasksUnchecked = 0
        var frontmatterAdded: [String] = []
        var frontmatterRemoved: [String] = []
        var frontmatterChanged: [String] = []
        var linksAdded: [String] = []
        var linksRemoved: [String] = []
    }

    static func phrase(from d: NoteDelta) -> String? {
        var bits: [String] = []
        if !d.headingsAdded.isEmpty { bits.append(listed(d.headingsAdded, verb: "add", noun: "headings")) }
        if !d.headingsRemoved.isEmpty { bits.append(listed(d.headingsRemoved, verb: "remove", noun: "headings")) }
        if !d.headingsEdited.isEmpty {
            if d.headingsEdited.count == 1, d.headingsEdited[0].0.count <= 24, d.headingsEdited[0].1.count <= 24 {
                bits.append("retitle \(d.headingsEdited[0].0) → \(d.headingsEdited[0].1)")
            } else {
                bits.append("edit \(d.headingsEdited.count) heading\(d.headingsEdited.count == 1 ? "" : "s")")
            }
        }
        if d.tasksChecked > 0 { bits.append("check \(d.tasksChecked) task\(d.tasksChecked == 1 ? "" : "s")") }
        if d.tasksUnchecked > 0 { bits.append("uncheck \(d.tasksUnchecked) task\(d.tasksUnchecked == 1 ? "" : "s")") }
        if d.tasksAdded > 0 { bits.append("add \(d.tasksAdded) task\(d.tasksAdded == 1 ? "" : "s")") }
        if d.tasksRemoved > 0 { bits.append("remove \(d.tasksRemoved) task\(d.tasksRemoved == 1 ? "" : "s")") }
        let fm = d.frontmatterAdded + d.frontmatterChanged
        if !fm.isEmpty { bits.append(listed(fm, verb: d.frontmatterChanged.isEmpty ? "set" : (d.frontmatterAdded.isEmpty ? "change" : "update"), noun: "fields")) }
        if !d.frontmatterRemoved.isEmpty { bits.append(listed(d.frontmatterRemoved, verb: "remove", noun: "fields")) }
        if !d.linksAdded.isEmpty { bits.append(linkPhrase(d.linksAdded, verb: "add")) }
        if !d.linksRemoved.isEmpty { bits.append(linkPhrase(d.linksRemoved, verb: "remove")) }
        if bits.isEmpty { return nil }
        return bits.joined(separator: ", ")
    }

    static func listed(_ items: [String], verb: String, noun: String) -> String {
        if items.count <= 2, items.allSatisfy({ $0.count <= 24 }) {
            return "\(verb) \(items.joined(separator: ", "))"
        }
        return "\(verb) \(items.count) \(noun)"
    }

    static func linkPhrase(_ targets: [String], verb: String) -> String {
        let names = targets.map(linkName).filter { !$0.isEmpty }
        if names.isEmpty { return "\(verb) \(targets.count) link\(targets.count == 1 ? "" : "s")" }
        if names.count == 1 { return "\(verb) link to \(names[0])" }
        if names.count == 2, names.allSatisfy({ $0.count <= 24 }) { return "\(verb) links to \(names.joined(separator: ", "))" }
        return "\(verb) \(names.count) links"
    }

    static func linkName(_ target: String) -> String {
        let t = target.trimmingCharacters(in: .whitespaces)
        if t.contains("://") { return "" }   // URLs are counted, not named
        let path = t.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? t
        return title(path.hasSuffix(".md") ? path : path + ".md")
    }

    // MARK: - Summarize

    static func summarize(old: String, new: String) -> NoteDelta {
        var d = NoteDelta()
        let a = NoteParser.summarize(old)
        let b = NoteParser.summarize(new)
        headingDelta(a.headings.map(\.text), b.headings.map(\.text), into: &d)
        taskDelta(tasks(in: old), tasks(in: new), into: &d)
        frontmatterDelta(a.frontmatter, b.frontmatter, into: &d)
        linkDelta(linkTargets(a), linkTargets(b), into: &d)
        return d
    }

    static func headingDelta(_ old: [String], _ new: [String], into d: inout NoteDelta) {
        var pendingDel: [String] = []
        var pendingIns: [String] = []
        func flush() {
            var used = Array(repeating: false, count: pendingIns.count)
            for od in pendingDel {
                if let j = pendingIns.indices.first(where: { !used[$0] && headingSimilar(od, pendingIns[$0]) }) {
                    used[j] = true
                    d.headingsEdited.append((od, pendingIns[j]))
                } else {
                    d.headingsRemoved.append(od)
                }
            }
            for (j, ins) in pendingIns.enumerated() where !used[j] { d.headingsAdded.append(ins) }
            pendingDel = []; pendingIns = []
        }
        for row in NoteDiff.myers(old, new) {
            switch row {
            case .same: flush()
            case .delete(let s): pendingDel.append(s)
            case .insert(let s): pendingIns.append(s)
            }
        }
        flush()
    }

    static func headingSimilar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let wa = a.split { !$0.isLetter && !$0.isNumber }.map { $0.lowercased() }
        let wb = b.split { !$0.isLetter && !$0.isNumber }.map { $0.lowercased() }
        if wa.isEmpty || wb.isEmpty { return false }
        let same = Set(wa).intersection(Set(wb)).count
        return Double(same) / Double(max(wa.count, wb.count)) >= 0.4
    }

    struct TaskItem: Equatable {
        var done: Bool
        var text: String
    }

    static func tasks(in text: String) -> [TaskItem] {
        var out: [TaskItem] = []
        var inFence = false
        for line in NoteDiff.splitLines(text) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle(); continue }
            if inFence { continue }
            guard let item = taskItem(line) else { continue }
            out.append(item)
        }
        return out
    }

    static func taskItem(_ line: String) -> TaskItem? {
        let t = line.trimmingCharacters(in: .whitespaces)
        // "- [ ] title", "* [x] title", "1. [X] title"
        let pat = #"^([-*+]|\d{1,9}[.)])[ \t]+\[([ xX])\][ \t]+(.*)$"#
        guard let r = try? NSRegularExpression(pattern: pat) else { return nil }
        let ns = t as NSString
        guard let m = r.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let mark = ns.substring(with: m.range(at: 2))
        let title = ns.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespaces)
        return TaskItem(done: mark == "x" || mark == "X", text: title)
    }

    static func taskDelta(_ old: [TaskItem], _ new: [TaskItem], into d: inout NoteDelta) {
        var remaining = old
        for n in new {
            if let i = remaining.firstIndex(where: { $0.text == n.text && $0.done == n.done }) {
                remaining.remove(at: i)
            } else if let i = remaining.firstIndex(where: { $0.text == n.text }) {
                if n.done { d.tasksChecked += 1 } else { d.tasksUnchecked += 1 }
                remaining.remove(at: i)
            } else {
                d.tasksAdded += 1
            }
        }
        d.tasksRemoved += remaining.count
    }

    static let timestampKeys: Set<String> = [
        "updated", "modified", "updatedat", "updated_at", "lastmod", "last-modified",
        "modified_at", "datemodified", "date modified", "mtime"
    ]

    static func frontmatterDelta(_ old: Frontmatter, _ new: Frontmatter, into d: inout NoteDelta) {
        func keep(_ k: String) -> Bool { !timestampKeys.contains(k.lowercased()) }
        var a: [String: (String, String)] = [:]
        for p in old.properties where keep(p.key) { a[p.key.lowercased()] = (p.key, p.value.display) }
        var b: [String: (String, String)] = [:]
        for p in new.properties where keep(p.key) { b[p.key.lowercased()] = (p.key, p.value.display) }
        for (k, nv) in b {
            if let ov = a[k] {
                if ov.1 != nv.1 { d.frontmatterChanged.append(nv.0) }
            } else {
                d.frontmatterAdded.append(nv.0)
            }
        }
        for (k, ov) in a where b[k] == nil { d.frontmatterRemoved.append(ov.0) }
    }

    static func linkTargets(_ sum: NoteSummary) -> [String] {
        sum.links.map(\.target) + sum.markdownLinks
    }

    static func linkDelta(_ old: [String], _ new: [String], into d: inout NoteDelta) {
        var remaining = old
        for n in new {
            if let i = remaining.firstIndex(of: n) { remaining.remove(at: i) }
            else { d.linksAdded.append(n) }
        }
        d.linksRemoved = remaining
    }
}
