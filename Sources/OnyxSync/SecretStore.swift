import Foundation
import Security

/// Where Onyx keeps its Obsidian auth token and vault keys.
public protocol SecretStore: Sendable {
    func get(_ account: String) -> Data?
    func set(_ account: String, _ value: Data) throws
    func remove(_ account: String)
}

/// Generic passwords in the login Keychain under Onyx's own service name. Never reads anyone else's items.
public struct KeychainStore: SecretStore {
    public static let onyxService = "md.onyx.sync"
    public let service: String
    public init(service: String = KeychainStore.onyxService) { self.service = service }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    public func get(_ account: String) -> Data? {
        var q = query(account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }
    public func set(_ account: String, _ value: Data) throws {
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(account)
            q[kSecValueData as String] = value
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            q[kSecAttrLabel as String] = "Onyx — Obsidian Sync (\(account.hasPrefix("key.") ? "vault key" : account))"
            let s = SecItemAdd(q as CFDictionary, nil)
            guard s == errSecSuccess else { throw KeychainError(status: s) }
        } else if status != errSecSuccess { throw KeychainError(status: status) }
    }
    public func remove(_ account: String) { SecItemDelete(query(account) as CFDictionary) }
}

public final class MemoryStore: SecretStore, @unchecked Sendable {
    private var items: [String: Data] = [:]
    private let lock = NSLock()
    public init() {}
    public func get(_ a: String) -> Data? { lock.lock(); defer { lock.unlock() }; return items[a] }
    public func set(_ a: String, _ v: Data) throws { lock.lock(); items[a] = v; lock.unlock() }
    public func remove(_ a: String) { lock.lock(); items[a] = nil; lock.unlock() }
}

public extension SecretStore {
    var token: String? { self.get("token").flatMap { String(data: $0, encoding: .utf8) } }
    func vaultKey(_ vaultID: String) -> [UInt8]? { self.get("key." + vaultID).map { Array($0) } }
}

/// A Keychain failure with its OSStatus, so callers can tell "this build has no Keychain" from the rest.
public struct KeychainError: Error, CustomStringConvertible, Equatable {
    public let status: OSStatus
    public init(status: OSStatus) { self.status = status }
    /// errSecMissingEntitlement: an unsigned build (e.g. `make ios` for the simulator) has no Keychain access.
    public var isMissingEntitlement: Bool { status == -34018 }
    public var description: String { "Keychain error \(status)" }
}

/// Secrets as files with owner-only permissions and iOS data protection, under Application Support/Onyx/Secrets.
/// Used only when the Keychain is unavailable to this build (see `ResilientSecretStore`).
public struct FileSecretStore: SecretStore {
    public let dir: URL
    public init(dir: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Onyx/Secrets", isDirectory: true)) { self.dir = dir }
    private func url(_ account: String) -> URL {
        dir.appendingPathComponent(account.replacingOccurrences(of: "/", with: "_"))
    }
    public func get(_ account: String) -> Data? { try? Data(contentsOf: url(account)) }
    public func set(_ account: String, _ value: Data) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var dirURL = dir
        var rv = URLResourceValues(); rv.isExcludedFromBackup = true
        try? dirURL.setResourceValues(rv)
        #if os(iOS)
        try value.write(to: url(account), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try value.write(to: url(account), options: [.atomic])
        #endif
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url(account).path)
    }
    public func remove(_ account: String) { try? FileManager.default.removeItem(at: url(account)) }
}

/// The Keychain, falling back to `FileSecretStore` only when the Keychain refuses this build outright
/// (errSecMissingEntitlement, as in an unsigned simulator build). Any other Keychain error is thrown.
public struct ResilientSecretStore: SecretStore {
    public let primary: any SecretStore
    public let fallback: any SecretStore
    public let onFallback: @Sendable (String) -> Void
    public init(primary: any SecretStore = KeychainStore(), fallback: any SecretStore = FileSecretStore(),
                onFallback: @escaping @Sendable (String) -> Void = { _ in }) {
        self.primary = primary; self.fallback = fallback; self.onFallback = onFallback
    }
    public func get(_ account: String) -> Data? { primary.get(account) ?? fallback.get(account) }
    public func set(_ account: String, _ value: Data) throws {
        do {
            try primary.set(account, value)
            fallback.remove(account)
        } catch let e as KeychainError where e.isMissingEntitlement {
            onFallback("Keychain unavailable to this build (\(e.status)); keeping \(account.hasPrefix("key.") ? "the vault key" : account) in a protected file")
            try fallback.set(account, value)
        }
    }
    public func remove(_ account: String) { primary.remove(account); fallback.remove(account) }
}
