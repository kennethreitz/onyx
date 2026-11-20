import Foundation

/// What Onyx knows about a local file (Obsidian's `localFiles` entry).
public struct LocalEntry: Codable, Equatable, Sendable {
    public var path: String
    public var previouspath = ""
    public var folder = false
    public var ctime = 0
    public var mtime = 0
    public var size = 0
    /// sha256 of the current content ("" = not computed since the last change).
    public var hash = ""
    /// Hash of the content last uploaded or downloaded.
    public var synchash = ""
    /// When we last synced this path (ms); uploads of recently synced files wait 10/20/30 s (Obsidian's debounce).
    public var synctime = 0
    public init(path: String) { self.path = path }
}

/// The server's latest record for a path (Obsidian's `serverFiles` / `newServerFiles` entries).
public struct RemoteEntry: Codable, Equatable, Sendable {
    public var uid: Int
    public var path: String
    public var hash: String
    public var size: Int
    public var ctime: Int
    public var mtime: Int
    public var folder: Bool
    public var deleted: Bool
    public var device: String?
    public var user: Int?
    /// Arrived during this device's first (initial) sync.
    public var initial = false

    public init(_ f: ServerFile, initial: Bool) {
        uid = f.uid; path = f.path; hash = f.hash; size = f.size; ctime = f.ctime; mtime = f.mtime
        folder = f.folder; deleted = f.deleted; device = f.device; user = f.user; self.initial = initial
    }
}

public enum ConflictStrategy: String, Codable, Sendable, CaseIterable {
    /// Obsidian's default: three-way merge Markdown (see `TextMerge`).
    case merge
    /// Keep the local version as "Note (Conflicted copy <device> <yyyyMMddHHmm>).md" and take the remote one.
    case conflict
}

/// Which remote vault a local folder syncs with. Secrets (token, vault key) live in the Keychain, not here.
public struct SyncBinding: Codable, Equatable, Sendable {
    public var vaultID: String
    public var vaultName: String
    public var host: String
    public var salt: String
    public var encryptionVersion: Int
    public var deviceName: String
    public var accountEmail: String
    public init(vaultID: String, vaultName: String, host: String, salt: String, encryptionVersion: Int, deviceName: String, accountEmail: String) {
        self.vaultID = vaultID; self.vaultName = vaultName; self.host = host; self.salt = salt
        self.encryptionVersion = encryptionVersion; self.deviceName = deviceName; self.accountEmail = accountEmail
    }
}

/// Everything the engine persists between launches for one local vault (Obsidian keeps the same in IndexedDB).
public struct SyncState: Codable, Sendable {
    public var binding: SyncBinding
    /// Highest server uid applied; sent as `version` in `init`.
    public var version = 0
    /// True until the server's first `ready` (Obsidian's `initial`).
    public var initial = true
    /// Onyx's extra safety on a first connect: until the first complete pass, never delete on either side and keep
    /// both versions of any file that differs (remote saved as a conflicted copy, local stays and is uploaded).
    public var initialMerge = true
    public var paused = false
    public var filter = SyncFilter()
    public var conflictStrategy = ConflictStrategy.merge
    public var local: [String: LocalEntry] = [:]
    public var remote: [String: RemoteEntry] = [:]
    public var pending: [RemoteEntry] = []
    public var lastSynced: Date?

    public init(binding: SyncBinding) { self.binding = binding }

    public static func load(_ url: URL) throws -> SyncState {
        try JSONDecoder().decode(SyncState.self, from: Data(contentsOf: url))
    }
    public func save(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }
}
