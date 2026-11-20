import CryptoKit
import Foundation

/// Walks a vault folder the way Obsidian's vault sees it: everything except dot-paths, plus the config dir's
/// syncable files (root *.json, themes/*/{manifest.json,theme.css}, snippets/*.css, plugins/*/{manifest.json,
/// main.js,styles.css,data.json}, and the legacy `config`).
public struct LocalScanner {
    public struct Item: Equatable { public var path: String; public var folder: Bool; public var mtime: Int; public var ctime: Int; public var size: Int }
    public let root: URL
    public let configDir: String
    public init(root: URL, configDir: String = ".obsidian") { self.root = root.standardizedFileURL.resolvingSymlinksInPath(); self.configDir = configDir }

    /// Obsidian uses Math.ceil(stat.mtime) in ms.
    public static func ms(_ d: Date?) -> Int { guard let d else { return 0 }; return Int((d.timeIntervalSince1970 * 1000).rounded(.up)) }

    public func isConfigCandidate(_ rel: String) -> Bool {
        guard rel.hasPrefix(configDir + "/") else { return false }
        let r = String(rel.dropFirst(configDir.count + 1))
        let parts = r.split(separator: "/").map(String.init)
        if parts.count == 1 { return parts[0] == "config" || SyncPath.ext(parts[0]) == "json" }
        if parts.count == 3 && parts[0] == "themes" { return parts[2] == "manifest.json" || parts[2] == "theme.css" }
        if parts.count == 2 && parts[0] == "snippets" { return SyncPath.ext(parts[1]) == "css" }
        if parts.count == 3 && parts[0] == "plugins" { return SyncFilter.isPluginFile(parts[2]) }
        return false
    }

    public func scan() throws -> [String: Item] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else {
            throw CocoaError(.fileReadNoPermission)
        }
        var out: [String: Item] = [:]
        let base = root.path
        for case let url as URL in e {
            let p = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard p.hasPrefix(base + "/") else { continue }
            let rel = String(p.dropFirst(base.count + 1))
            let v = try? url.resourceValues(forKeys: Set(keys))
            if v?.isSymbolicLink == true { e.skipDescendants(); continue }
            let dir = v?.isDirectory ?? false
            if SyncPath.isHidden(rel) {
                let inConfig = rel == configDir || rel.hasPrefix(configDir + "/")
                if !inConfig { if dir { e.skipDescendants() }; continue }
                if dir {
                    let comps = rel.split(separator: "/")
                    if comps.count > 3 || comps.contains(where: { $0 == "node_modules" }) || comps.dropFirst().contains(where: { $0.hasPrefix(".") }) { e.skipDescendants() }
                    continue
                }
                guard isConfigCandidate(rel) else { continue }
            }
            out[rel] = Item(path: rel, folder: dir, mtime: dir ? 0 : Self.ms(v?.contentModificationDate),
                            ctime: dir ? 0 : Self.ms(v?.creationDate), size: dir ? 0 : (v?.fileSize ?? 0))
        }
        return out
    }

    public func url(_ rel: String) -> URL { root.appendingPathComponent(rel) }

    public static func sha256(_ data: Data) -> String { ObsidianCrypto.contentHash(data) }
}
