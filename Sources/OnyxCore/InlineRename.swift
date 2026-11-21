import Foundation

/// Commit / cancel / error rules for Finder-style inline rename in the file tree.
public enum InlineRename {
    public enum Outcome: Equatable, Sendable {
        /// `dest` is the vault-relative path; `fromName` / `toName` are the shown stems (no `.md`).
        case commit(dest: String, fromName: String, toName: String)
        case cancel
        case invalid(String)
        case collision(String)
    }

    /// The text shown in the field: a note's name without `.md`, otherwise the last path component.
    public static func fieldValue(path: String) -> String {
        let last = (path as NSString).lastPathComponent
        if last.lowercased().hasSuffix(".md") { return String(last.dropLast(3)) }
        return last
    }

    /// How many leading characters of `fieldValue` should be selected.
    /// Notes and folders select the whole name; other files select the stem, without the last extension.
    public static func selectionLength(for fieldValue: String, wholeName: Bool) -> Int {
        let s = fieldValue as NSString
        if wholeName { return s.length }
        let dot = s.range(of: ".", options: .backwards)
        if dot.location != NSNotFound, dot.location > 0 { return dot.location }
        return s.length
    }

    /// Decide what a typed name should do. `occupied` is true when a path already exists
    /// (the source path may also report true on a case-insensitive disk; that is not a collision).
    public static func evaluate(path: String, typed: String, occupied: (String) -> Bool) -> Outcome {
        let last = (path as NSString).lastPathComponent
        let isNote = last.lowercased().hasSuffix(".md")
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .cancel }
        if trimmed.contains("/") || trimmed.contains(":") {
            return .invalid("Name can’t contain “/” or “:”.")
        }
        if trimmed.contains(where: { $0.isNewline }) {
            return .invalid("Name can’t contain a line break.")
        }
        if trimmed == "." || trimmed == ".." {
            return .invalid("That name isn’t allowed.")
        }
        if trimmed.hasPrefix(".") {
            return .invalid("Name can’t start with a period.")
        }

        var new = trimmed
        if isNote, !new.lowercased().hasSuffix(".md") { new += ".md" }
        let dir = (path as NSString).deletingLastPathComponent
        let dest = dir.isEmpty ? new : dir + "/" + new
        if dest == path { return .cancel }
        if occupied(dest), dest.lowercased() != path.lowercased() {
            let shown = displayName(new, isNote: isNote)
            return .collision("“\(shown)” already exists there.")
        }
        return .commit(dest: dest, fromName: displayName(last, isNote: isNote), toName: displayName(new, isNote: isNote))
    }

    public static func displayName(_ last: String, isNote: Bool) -> String {
        isNote && last.lowercased().hasSuffix(".md") ? String(last.dropLast(3)) : last
    }
}
