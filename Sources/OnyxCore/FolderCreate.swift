import Foundation

/// Naming for a newly created vault folder: "Untitled Folder", then "Untitled Folder 2", …
public enum FolderCreate {
    public static let defaultName = "Untitled Folder"

    /// Strip leading/trailing space and characters that would escape the parent folder.
    public static func sanitized(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        if s == "." || s == ".." { s = "" }
        // A name made only of separators isn't a usable folder name.
        if s.unicodeScalars.allSatisfy({ !CharacterSet.alphanumerics.contains($0) }) { s = "" }
        return s
    }

    /// The first name that is not in `taken`, starting at `base` then `base 2`, `base 3`, …
    public static func uniqueName(base: String = defaultName, taken: (String) -> Bool) -> String {
        let start = sanitized(base)
        let name = start.isEmpty ? defaultName : start
        if !taken(name) { return name }
        var n = 2
        while taken("\(name) \(n)") { n += 1 }
        return "\(name) \(n)"
    }

    public static func uniqueName(base: String = defaultName, existing: Set<String>) -> String {
        uniqueName(base: base, taken: { existing.contains($0) })
    }

    /// Vault-relative path of `name` inside `folder` (empty folder = vault root).
    public static func path(name: String, in folder: String) -> String {
        folder.isEmpty ? name : folder + "/" + name
    }
}
