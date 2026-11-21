import Foundation

/// Where a new note should land, and how an Untitled file gets a real name on save.
public enum NoteNaming {
    /// `Untitled.md`, `Untitled 2.md`, … — the placeholder name `createNote` uses.
    public static func isUntitled(_ path: String) -> Bool {
        let base = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        if base.compare("Untitled", options: .caseInsensitive) == .orderedSame { return true }
        return base.range(of: #"^Untitled \d+$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Folder to create a new note in: a uniquely selected folder, else the title-path
    /// folder, else the open note's folder, else the vault root.
    public static func folderForNewNote(selected: Set<String>, folders: Set<String>,
                                        selectedFolder: String?, currentPath: String?) -> String {
        let chosen = selected.filter { folders.contains($0) }
        if chosen.count == 1, let f = chosen.first { return f }
        if let sf = selectedFolder, !sf.isEmpty { return sf }
        return currentPath.map { ($0 as NSString).deletingLastPathComponent } ?? ""
    }

    /// First H1 (else first heading, else first non-empty body line), stripped and
    /// safe as a filename. Nil when empty or still “Untitled”.
    public static func title(fromContent text: String) -> String? {
        let fm = Frontmatter.parse(text)
        let headings = NoteParser.parseHeadings(text, from: fm.bodyOffset)
        let raw: String?
        if let h = headings.first(where: { $0.level == 1 }) ?? headings.first {
            raw = h.text
        } else {
            raw = firstBodyLine(text, from: fm.bodyOffset)
        }
        guard let raw else { return nil }
        let name = fileName(fromTitle: raw)
        guard !name.isEmpty, !isUntitled(name + ".md") else { return nil }
        return name
    }

    /// Vault-relative path for `title` in `folder`, adding " 2", " 3", … when taken.
    /// `occupied` is true for a path that already exists (the Untitled source should
    /// return false so a no-op rename is possible).
    public static func dest(folder: String, title: String, occupied: (String) -> Bool) -> String {
        let name = fileName(fromTitle: title)
        let base = folder.isEmpty ? name : folder + "/" + name
        var path = base + ".md"
        var n = 1
        while occupied(path) {
            n += 1
            path = "\(base) \(n).md"
        }
        return path
    }

    public static func fileName(fromTitle title: String) -> String {
        var s = title.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "/", with: "-")
        s = s.replacingOccurrences(of: ":", with: "-")
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        while s.hasPrefix(".") { s = String(s.dropFirst()) }   // hidden files are skipped by the snapshot
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstBodyLine(_ text: String, from offset: Int) -> String? {
        let ns = text as NSString
        let start = min(max(offset, 0), ns.length)
        for line in ns.substring(from: start).split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            return t
        }
        return nil
    }
}
