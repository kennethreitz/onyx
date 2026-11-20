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
            guard s == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(s)) }
        } else if status != errSecSuccess { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
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
