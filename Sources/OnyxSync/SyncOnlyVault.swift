import CryptoKit
import Foundation
import OnyxCore

/// Where Obsidian Sync state lives (outside every vault): `Application Support/Onyx/Sync`.
public enum SyncStorage {
    public static var defaultSupportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Onyx/Sync", isDirectory: true)
    }

    /// The state file for a local vault folder. A sync-only vault is keyed by its remote vault id (its
    /// container path can change on iOS); any other folder by a hash of its path, as before.
    public static func stateURL(for root: URL, library: SyncVaultLibrary = .default, supportDir: URL = defaultSupportDir) -> URL {
        if let v = library.vault(at: root) { return stateURL(managed: v, supportDir: supportDir) }
        let id = Hex.encode(Array(SHA256.hash(data: Data(root.standardizedFileURL.path.utf8))).prefix(8))
        return supportDir.appendingPathComponent("\(id).json")
    }
    public static func stateURL(managed v: ManagedVault, supportDir: URL = defaultSupportDir) -> URL {
        supportDir.appendingPathComponent("vault-\(SyncPath.sanitize(v.id)).json")
    }
    /// Where text overwritten by a merge or download (and, without a Trash, deleted files) is copied first.
    public static func backupDir(forState stateURL: URL) -> URL {
        stateURL.deletingLastPathComponent().appendingPathComponent("Backups").appendingPathComponent(stateURL.deletingPathExtension().lastPathComponent)
    }
}

/// Sync-only vaults: an Obsidian Sync remote vault kept as a local copy inside Onyx's own container.
/// Shared by the Mac and iOS apps; the UI only signs in, picks a vault and asks for its password.
public struct SyncOnlyVaults: Sendable {
    public var library: SyncVaultLibrary
    public var store: any SecretStore
    public var supportDir: URL

    public init(library: SyncVaultLibrary = .default, store: any SecretStore, supportDir: URL = SyncStorage.defaultSupportDir) {
        self.library = library; self.store = store; self.supportDir = supportDir
    }

    /// Check the vault password against the server (`/vault/access`) and return the binding and derived key.
    /// Vaults with Obsidian-managed encryption carry their password in the vault list; end-to-end vaults need
    /// the one the user typed. Key derivation (scrypt) runs off the caller's actor.
    public static func unlock(api: ObsidianAPI, token: String, vault v: ObsidianAPI.RemoteVault, password: String,
                              deviceName: String, accountEmail: String) async throws -> (binding: SyncBinding, key: [UInt8]) {
        let salt = v.salt ?? ""
        let version = v.encryption_version ?? 0
        let pw = v.password ?? password
        guard !pw.isEmpty else { throw ObsidianAPI.APIError(message: "Enter the vault’s encryption password.") }
        let key = try await Task.detached(priority: .userInitiated) { try ObsidianCrypto.deriveVaultKey(password: pw, salt: salt) }.value
        let crypto = try ObsidianCrypto.provider(version: version, key: key, salt: salt)
        try await api.access(token: token, vaultID: v.id, keyhash: crypto.keyHash, host: v.host, encryptionVersion: version)
        let b = SyncBinding(vaultID: v.id, vaultName: v.name, host: v.host, salt: salt, encryptionVersion: version,
                            deviceName: deviceName, accountEmail: accountEmail)
        return (b, key)
    }

    public func folder(_ v: ManagedVault) -> URL { library.url(for: v) }
    public func stateURL(_ v: ManagedVault) -> URL { SyncStorage.stateURL(managed: v, supportDir: supportDir) }
    public func isConnected(_ v: ManagedVault) -> Bool { FileManager.default.fileExists(atPath: stateURL(v).path) }

    /// Create (or reuse) the local copy of `binding`'s vault, store its key and write the sync state, so the
    /// first engine run pulls everything down. A reused copy that still has state keeps it; a copy that has
    /// files but no state gets a fresh first sync, which never deletes on either side (initial merge).
    @discardableResult
    public func connect(binding: SyncBinding, key: [UInt8], now: Date = Date()) throws -> ManagedVault {
        let v = try library.prepare(remoteID: binding.vaultID, name: binding.vaultName, accountEmail: binding.accountEmail, now: now)
        try store.set("key." + binding.vaultID, Data(key))
        let url = stateURL(v)
        if var existing = try? SyncState.load(url), existing.binding.vaultID == binding.vaultID {
            existing.binding = binding     // a new device name or password salt
            try existing.save(url)
        } else {
            try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
            try SyncState(binding: binding).save(url)
        }
        return v
    }

    /// The engine for a connected sync-only vault (nil if it isn't connected or its key is missing).
    public func engine(for v: ManagedVault, token: String, options: SyncEngine.Options = SyncEngine.Options(),
                       onStatus: @escaping @Sendable (SyncStatus) -> Void = { _ in },
                       onLog: @escaping @Sendable (String, String?) -> Void = { _, _ in }) throws -> SyncEngine? {
        let url = stateURL(v)
        guard let state = try? SyncState.load(url) else { return nil }
        guard let key = store.vaultKey(state.binding.vaultID) else { return nil }
        let crypto = try ObsidianCrypto.provider(version: state.binding.encryptionVersion, key: key, salt: state.binding.salt)
        var o = options
        if o.backupDir == nil { o.backupDir = SyncStorage.backupDir(forState: url) }
        return SyncEngine(root: try library.checkedFolder(v), state: state, crypto: crypto, token: token, stateURL: url,
                          options: o, onStatus: onStatus, onLog: onLog)
    }

    /// Stop syncing (forget the state and the key) but keep the local copy and its library entry, so it can be
    /// reconnected later. Deletes nothing in the folder or on the server.
    public func disconnect(_ v: ManagedVault) {
        let url = stateURL(v)
        try? FileManager.default.removeItem(at: url)
        if !keyInUse(v.id, except: url) { store.remove("key." + v.id) }
    }

    /// Delete this device's copy: disconnect, drop its backups, and remove the folder (only if it really is
    /// a sync-only folder inside the library). The remote vault and other devices are not touched.
    public func removeLocalCopy(_ v: ManagedVault) throws {
        _ = try library.checkedFolder(v)
        let url = stateURL(v)
        disconnect(v)
        try? FileManager.default.removeItem(at: SyncStorage.backupDir(forState: url))
        try library.removeLocalCopy(v)
    }

    /// Whether another local folder's sync state still uses this remote vault's key.
    func keyInUse(_ vaultID: String, except: URL) -> Bool {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: supportDir.path) else { return false }
        for n in names where n.hasSuffix(".json") {
            let u = supportDir.appendingPathComponent(n)
            guard u.standardizedFileURL != except.standardizedFileURL, let s = try? SyncState.load(u) else { continue }
            if s.binding.vaultID == vaultID { return true }
        }
        return false
    }
}
