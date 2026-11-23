import Foundation

/// Pure helpers for dropping and pasting files into a note, the way Obsidian does: where the copy
/// lands (`attachmentFolderPath`), what it's called (unique names, `Pasted image …`), and the link
/// that goes into the note (`useMarkdownLinks`, `newLinkFormat`).
public enum Attachments {
    /// The `.obsidian/app.json` settings that shape a new attachment and its link.
    public struct Settings: Equatable {
        /// `attachmentFolderPath`: nil/"/" vault root, "./" note's folder, "./sub" subfolder, else a vault folder.
        public var folder: String?
        /// `useMarkdownLinks`: `![](x.png)` instead of `![[x.png]]`.
        public var useMarkdownLinks: Bool
        /// `newLinkFormat`: "shortest" (default), "relative" or "absolute".
        public var linkFormat: String

        public init(folder: String? = nil, useMarkdownLinks: Bool = false, linkFormat: String = "shortest") {
            self.folder = folder; self.useMarkdownLinks = useMarkdownLinks; self.linkFormat = linkFormat
        }

        /// Read from a parsed app.json (missing keys → Obsidian's defaults).
        public init(appJSON: [String: Any]?) {
            let a = appJSON ?? [:]
            self.init(folder: a["attachmentFolderPath"] as? String,
                      useMarkdownLinks: a["useMarkdownLinks"] as? Bool ?? false,
                      linkFormat: (a["newLinkFormat"] as? String).flatMap { ["shortest", "relative", "absolute"].contains($0) ? $0 : nil } ?? "shortest")
        }
    }

    public static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "avif", "heic", "bmp", "tif", "tiff"]
    public static let audioExts: Set<String> = ["mp3", "m4a", "wav", "ogg", "flac", "3gp", "webm"]
    public static let videoExts: Set<String> = ["mp4", "mov", "mkv", "ogv", "webm"]

    /// Obsidian embeds the types it can show inline (images, audio, video, PDF, notes, canvases,
    /// bases) and links everything else.
    public static func isEmbeddable(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return imageExts.contains(ext) || audioExts.contains(ext) || videoExts.contains(ext)
            || ["pdf", "md", "canvas", "base"].contains(ext)
    }

    /// `Pasted image 20261123075900.png`, Obsidian's name for an image pasted or dropped without a file name.
    public static func pastedImageName(date: Date, ext: String = "png", timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyyMMddHHmmss"
        return "Pasted image \(f.string(from: date)).\(ext)"
    }

    /// A file name safe in a vault and in a link: drops the characters Obsidian refuses in names
    /// (`* " \ / < > : | ? # ^ [ ]`), and leading dots (hidden files the index skips).
    public static func sanitize(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "*\"\\/<>:|?#^[]").union(.controlCharacters)
        var s = String(String.UnicodeScalarView(name.unicodeScalars.map { bad.contains($0) ? " " : $0 }))
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        while s.hasPrefix(".") { s.removeFirst() }
        return s.isEmpty ? "Untitled" : s
    }

    /// Where a new attachment for `note` goes, with a free name (` 1`, ` 2`… before the extension).
    public static func destination(name: String, note: String?, settings: Settings, exists: (String) -> Bool) -> String {
        let folder = AudioNote.attachmentFolder(setting: settings.folder, notePath: note)
        return AudioNote.uniquePath(folder: folder, name: sanitize(name), exists: exists)
    }

    /// The link Obsidian would write in `note` for vault file `path`.
    /// `isUniqueName` answers whether the file's name alone finds it (for "shortest").
    public static func link(to path: String, from note: String?, settings: Settings,
                            embed: Bool? = nil, isUniqueName: (String) -> Bool) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        let isNote = ext == "md"
        let bang = (embed ?? (isEmbeddable(path) && !isNote)) ? "!" : ""
        let noteDir = note.map { ($0 as NSString).deletingLastPathComponent } ?? ""
        let file = (path as NSString).lastPathComponent
        var target: String
        switch settings.linkFormat {
        case "relative": target = MarkdownLinks.relative(from: noteDir, to: path)
        case "absolute": target = path
        default: target = isUniqueName(path) ? file : path
        }
        if settings.useMarkdownLinks {
            if settings.linkFormat == "relative", !target.contains("/") { target = "./" + target }
            let dest = target.addingPercentEncoding(withAllowedCharacters: MarkdownLinks.encodeAllowed) ?? target
            let text = bang.isEmpty ? (isNote ? (file as NSString).deletingPathExtension : file) : ""
            return "\(bang)[\(text)](\(dest))"
        }
        if isNote { target = (target as NSString).deletingPathExtension }
        return "\(bang)[[\(target)]]"
    }

    /// The text to insert at a drop or paste: one link inline, several on their own lines.
    public static func insertion(_ links: [String]) -> String {
        links.joined(separator: "\n")
    }

    static let markdownImage = try! NSRegularExpression(pattern: #"!\[[^\]\n]*\]\((?:<([^>\n]+)>|([^)\s]+))(?:\s+"[^"\n]*")?\)"#)

    /// The destinations of `![alt](dest)` images in a note, raw as written.
    public static func markdownImageTargets(in text: String) -> [String] {
        let ns = text as NSString
        return markdownImage.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let r = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
            let h = ns.substring(with: r)
            return MarkdownLinks.isExternal(h) ? nil : h
        }
    }

    /// The vault file a Markdown image destination means, as Obsidian reads it: relative to the
    /// note first, then from the vault root, then by name anywhere.
    public static func resolveMarkdownTarget(_ href: String, from note: String?, exists: (String) -> Bool, resolve: (String) -> String?) -> String? {
        let raw = (href.removingPercentEncoding ?? href)
        let h = raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
        let dir = note.map { ($0 as NSString).deletingLastPathComponent } ?? ""
        if !raw.hasPrefix("/"), let p = MarkdownLinks.normalize(dir.isEmpty ? h : dir + "/" + h), exists(p) { return p }
        if let p = MarkdownLinks.normalize(h), exists(p) { return p }
        return resolve(h)
    }
}
