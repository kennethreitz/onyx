import Foundation

/// A "sync-only" vault: a local copy of an Obsidian Sync remote vault that Onyx keeps inside its own
/// container (Application Support/Onyx/Vaults/<folder>) instead of a folder the user picked.
public struct ManagedVault: Codable, Equatable, Identifiable, Sendable {
    /// The remote (Obsidian Sync) vault id.
    public var id: String
    /// The remote vault's name when it was connected.
    public var name: String
    /// Folder name directly under the library root.
    public var folder: String
    public var accountEmail: String
    public var created: Date
    public init(id: String, name: String, folder: String, accountEmail: String, created: Date) {
        self.id = id; self.name = name; self.folder = folder; self.accountEmail = accountEmail; self.created = created
    }
}

public enum SyncVaultLibraryError: Error, Equatable, CustomStringConvertible {
    case notManaged(String)
    case outsideLibrary(String)
    case folderNotEmpty(String)
    public var description: String {
        switch self {
        case .notManaged(let p): "“\(p)” is not a sync-only vault Onyx created, so Onyx won’t delete it."
        case .outsideLibrary(let p): "“\(p)” is outside Onyx’s vault folder, so Onyx won’t delete it."
        case .folderNotEmpty(let p): "“\(p)” already has files that Onyx didn’t create."
        }
    }
}

/// The list of sync-only vaults and their folders. Pure file logic (no networking, no Keychain), shared by
/// the Mac and iOS apps. The manifest is `<root>/.onyx-vaults.json`; dot-names are never vaults.
public struct SyncVaultLibrary: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root.standardizedFileURL }

    /// `Application Support/Onyx/Vaults` in this app's container (~/Library/… on the Mac, the app sandbox on iOS).
    public static func defaultRoot(_ fm: FileManager = .default) -> URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Onyx/Vaults", isDirectory: true)
    }
    public static var `default`: SyncVaultLibrary { SyncVaultLibrary(root: defaultRoot()) }

    public var manifestURL: URL { root.appendingPathComponent(".onyx-vaults.json") }

    // MARK: Manifest

    public func load() -> [ManagedVault] {
        guard let d = try? Data(contentsOf: manifestURL) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([ManagedVault].self, from: d)) ?? []
    }

    public func save(_ vaults: [ManagedVault]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(vaults).write(to: manifestURL, options: .atomic)
    }

    public func url(for v: ManagedVault) -> URL { root.appendingPathComponent(v.folder, isDirectory: true) }

    /// The managed vault whose folder is `url`, if any.
    public func vault(at url: URL) -> ManagedVault? {
        let p = Self.canonical(url)
        return load().first { Self.canonical(self.url(for: $0)) == p }
    }
    public func vault(remoteID: String) -> ManagedVault? { load().first { $0.id == remoteID } }
    public func isManaged(_ url: URL) -> Bool { vault(at: url) != nil }

    // MARK: Naming

    /// A safe, unique folder name for a remote vault name: no path separators, control characters or
    /// leading dots, at most 80 characters, and not already taken (compared case-insensitively, as on
    /// APFS): "Notes", "Notes 2", "Notes 3"…
    public static func folderName(for remoteName: String, taken: Set<String>) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
        var s = String(String.UnicodeScalarView(remoteName.unicodeScalars.map { bad.contains($0) ? "-" : $0 }))
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix(".") { s.removeFirst() }
        s = s.trimmingCharacters(in: .whitespaces)
        if s.count > 80 { s = String(s.prefix(80)).trimmingCharacters(in: .whitespaces) }
        if s.isEmpty || s == "-" { s = "Vault" }
        let lower = Set(taken.map { $0.lowercased() })
        if !lower.contains(s.lowercased()) { return s }
        var n = 2
        while lower.contains("\(s) \(n)".lowercased()) { n += 1 }
        return "\(s) \(n)"
    }

    // MARK: Lifecycle

    /// The local copy for a remote vault: the existing one if this remote was connected before (so
    /// reconnecting never makes a second copy), else a new empty folder. Records it in the manifest.
    @discardableResult
    public func prepare(remoteID: String, name: String, accountEmail: String, now: Date = Date()) throws -> ManagedVault {
        let fm = FileManager.default
        var all = load()
        if let v = all.first(where: { $0.id == remoteID }) {
            try fm.createDirectory(at: url(for: v), withIntermediateDirectories: true)
            return v
        }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let existing = Set((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).union(all.map(\.folder))
        let folder = Self.folderName(for: name, taken: existing)
        // Whole seconds, so the value round-trips through the manifest's ISO 8601 dates unchanged.
        let created = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down))
        let v = ManagedVault(id: remoteID, name: name, folder: folder, accountEmail: accountEmail, created: created)
        try fm.createDirectory(at: url(for: v), withIntermediateDirectories: false)
        all.append(v)
        try save(all)
        return v
    }

    /// Forget a vault without touching its files (they stay where they are, as a plain folder).
    public func forget(_ v: ManagedVault) throws {
        try save(load().filter { $0.id != v.id })
    }

    /// Delete a sync-only vault's local copy. Refuses anything that isn't a manifest entry whose folder is a
    /// real directory directly inside the library root (no symlinks, no "..", nothing elsewhere on disk).
    public func removeLocalCopy(_ v: ManagedVault) throws {
        guard let known = load().first(where: { $0.id == v.id }), known.folder == v.folder else { throw SyncVaultLibraryError.notManaged(v.folder) }
        let dir = try checkedFolder(known)
        if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.removeItem(at: dir) }
        try forget(known)
    }

    /// The folder for `v`, verified to be a direct child of `root` and not a symlink.
    public func checkedFolder(_ v: ManagedVault) throws -> URL {
        let name = v.folder
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.hasPrefix(".") else {
            throw SyncVaultLibraryError.outsideLibrary(name)
        }
        let dir = url(for: v)
        if let vals = try? dir.resourceValues(forKeys: [.isSymbolicLinkKey]), vals.isSymbolicLink == true {
            throw SyncVaultLibraryError.outsideLibrary(dir.path)
        }
        guard Self.canonical(dir.deletingLastPathComponent()) == Self.canonical(root) else { throw SyncVaultLibraryError.outsideLibrary(dir.path) }
        return dir
    }

    /// Whether a folder has no visible files yet (a fresh local copy).
    public static func isEmptyFolder(_ url: URL) -> Bool {
        let kids = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return kids.allSatisfy { $0 == ".DS_Store" }
    }

    static func canonical(_ url: URL) -> String {
        var p = url.standardizedFileURL.resolvingSymlinksInPath().path
        if p.hasPrefix("/private/") { p.removeFirst("/private".count) }
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }
}
