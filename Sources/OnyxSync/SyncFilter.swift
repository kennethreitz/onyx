import Foundation

/// Which paths Obsidian Sync syncs. A port of Obsidian 1.15.1's `RA` filter (`allowSyncFile`), with its defaults:
/// attachment types image/audio/pdf/video on, "unsupported" (other files) off; config categories app, appearance,
/// appearance-data, hotkey, core-plugin, core-plugin-data on; community plugins off.
public struct SyncFilter: Codable, Equatable, Sendable {
    public static let defaultTypes: Set<String> = ["image", "audio", "pdf", "video"]
    public static let allTypes = ["image", "audio", "video", "pdf", "unsupported"]
    public static let defaultSpecial: Set<String> = ["app", "appearance", "appearance-data", "hotkey", "core-plugin", "core-plugin-data"]
    public static let allSpecial = ["app", "appearance", "appearance-data", "hotkey", "core-plugin", "core-plugin-data",
                                    "community-plugin", "community-plugin-data"]

    static let images: Set<String> = ["bmp", "png", "jpg", "jpeg", "gif", "svg", "webp", "avif"]
    static let audio: Set<String> = ["mp3", "wav", "m4a", "3gp", "flac", "ogg", "oga", "opus"]
    static let video: Set<String> = ["mp4", "webm", "ogv", "mov", "mkv"]

    public var allowTypes: Set<String>
    public var allowSpecialFiles: Set<String>
    public var ignoreFolders: [String]
    public var configDir: String

    public init(allowTypes: Set<String> = defaultTypes, allowSpecialFiles: Set<String> = defaultSpecial,
                ignoreFolders: [String] = [], configDir: String = ".obsidian") {
        self.allowTypes = allowTypes; self.allowSpecialFiles = allowSpecialFiles
        self.ignoreFolders = ignoreFolders; self.configDir = configDir
    }

    public static func isPluginFile(_ name: String) -> Bool {
        name == "manifest.json" || name == "main.js" || name == "styles.css" || name == "data.json"
    }

    public func allows(_ path: String, folder: Bool) -> Bool {
        for f in ignoreFolders where (folder && path == f) || path.hasPrefix(f + "/") { return false }
        if !folder && path.hasPrefix(configDir + "/") {
            let rel = String(path.dropFirst(configDir.count + 1))
            let parts = rel.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            if parts.contains(where: { $0 == "node_modules" || $0.hasPrefix(".") }) { return false }
            let base = SyncPath.basename(rel), ext = SyncPath.ext(base)
            if rel == "workspace.json" || rel == "workspace-mobile.json" { return false }
            var cat: String?
            if rel == "app.json" || rel == "types.json" { cat = "app" }
            else if rel == "appearance.json" { cat = "appearance" }
            else if rel == "hotkeys.json" { cat = "hotkey" }
            else if rel == "core-plugins.json" || rel == "core-plugins-migration.json" { cat = "core-plugin" }
            else if rel == "community-plugins.json" { cat = "community-plugin" }
            else if (parts[0] == "themes" && parts.count == 3 && (base == "theme.css" || base == "manifest.json"))
                        || (parts[0] == "snippets" && parts.count == 2 && ext == "css") { cat = "appearance-data" }
            else if parts.count == 1 && ext == "json" { cat = "core-plugin-data" }
            else if parts[0] == "plugins" && parts.count == 3 && Self.isPluginFile(base) { cat = "community-plugin-data" }
            return cat.map { allowSpecialFiles.contains($0) } ?? false
        }
        if SyncPath.isHidden(path) { return false }
        if folder { return true }
        let ext = SyncPath.ext(SyncPath.basename(path))
        if ext == "md" || ext == "canvas" || ext == "base" { return true }
        if Self.images.contains(ext) { return allowTypes.contains("image") }
        if ext == "webm" { return allowTypes.contains("audio") || allowTypes.contains("video") }
        if Self.audio.contains(ext) { return allowTypes.contains("audio") }
        if Self.video.contains(ext) { return allowTypes.contains("video") }
        if ext == "pdf" { return allowTypes.contains("pdf") }
        return allowTypes.contains("unsupported")
    }
}

/// Obsidian's path helpers (`pe`, `he`, `Ci`, `hh`, `Use`).
public enum SyncPath {
    public static func basename(_ p: String) -> String { p.lastIndex(of: "/").map { String(p[p.index(after: $0)...]) } ?? p }
    public static func parent(_ p: String) -> String { p.lastIndex(of: "/").map { String(p[..<$0]) } ?? "" }
    /// Lowercased extension; "" for none, a leading dot, or a trailing dot.
    public static func ext(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex, name.index(after: dot) != name.endIndex else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }
    /// Path without its basename's extension.
    public static func stripExt(_ p: String) -> String {
        let e = ext(basename(p)); return e.isEmpty ? p : String(p.dropLast(e.count + 1))
    }
    /// Any component starting with "." (Obsidian never syncs these, except the config dir via its own rules).
    public static func isHidden(_ p: String) -> Bool { p.split(separator: "/").contains { $0.hasPrefix(".") } }
    /// Obsidian's `Use`: no "file:" URLs, NULs, "..", or components over 255 chars.
    public static func isValidRemoteName(_ p: String) -> Bool {
        if p.hasPrefix("file:") || p.contains("\0") || p.isEmpty || p.hasPrefix("/") { return false }
        return !p.split(separator: "/", omittingEmptySubsequences: false).contains { $0 == ".." || $0 == "." || $0.isEmpty || $0.utf8.count > 255 }
    }
    /// Obsidian's `TT`: replace characters illegal in file names, collapse repeats.
    public static func sanitize(_ s: String, with r: String = "_") -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return t }
        var out = s.replacingOccurrences(of: #"[\\/:*?"<>|#^\[\]]"#, with: r, options: .regularExpression)
        while out.contains(r + r) { out = out.replacingOccurrences(of: r + r, with: r) }
        return out
    }
}
