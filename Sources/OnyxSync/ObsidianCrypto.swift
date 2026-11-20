import CryptoKit
import Foundation

public enum ObsidianCryptoError: Error, Equatable {
    case cipherSetupFailed(Int32)
    case truncated
    case authenticationFailed
    case invalidKey
    case invalidHex
    case invalidUTF8
    case unsupportedEncryptionVersion(Int)
}

/// Vault key derivation and the per-version encryption providers used by Obsidian Sync.
/// Transcribed from Obsidian 1.15.1 `app.js` (functions `BT`, `NQ`, `BQ`, classes `b9`/`v9`);
/// the same code ships in Obsidian's official `obsidian-headless` 0.0.14 CLI.
public enum ObsidianCrypto {
    /// The encryption version new vaults are created with (`qb = 3`) and the max version advertised
    /// to `/vault/list` (`w9 = 3`).
    public static let currentEncryptionVersion = 3

    /// scrypt(NFKC(password), NFKC(salt)), N=32768, r=8, p=1, 32 bytes. The salt is the vault's salt
    /// string as returned by `/vault/list` (used as UTF-8 text, not hex-decoded).
    public static func deriveVaultKey(password: String, salt: String) throws -> [UInt8] {
        let pw = Array(password.precomposedStringWithCompatibilityMapping.utf8)
        let s = Array(salt.precomposedStringWithCompatibilityMapping.utf8)
        return try Scrypt.derive(password: pw, salt: s, N: 32768, r: 8, p: 1, length: 32)
    }

    /// The provider for a vault's `encryption_version`.
    public static func provider(version: Int, key: [UInt8], salt: String) throws -> any SyncEncryptionProvider {
        switch version {
        case 0: return try ObsidianV0Provider(key: key)
        case 2, 3: return try ObsidianV2Provider(key: key, salt: salt, version: version)
        default: throw ObsidianCryptoError.unsupportedEncryptionVersion(version)
        }
    }

    /// The `keyhash` sent to `/vault/access`, `/vault/create` and the websocket `init`.
    public static func keyHash(key: [UInt8], salt: String, version: Int) throws -> String {
        try provider(version: version, key: key, salt: salt).keyHash
    }

    /// Content hash Obsidian compares files by: lowercase hex SHA-256 of the plaintext bytes (`Pp`).
    /// It travels deterministically encrypted (`deterministicEncodeStr`) on the wire.
    public static func contentHash<D: DataProtocol>(_ data: D) -> String {
        Hex.encode(Array(SHA256.hash(data: data)))
    }

    static func hkdf(_ key: [UInt8], salt: [UInt8], info: String) -> [UInt8] {
        let k = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: key), salt: salt,
                                       info: Array(info.utf8), outputByteCount: 32)
        return k.withUnsafeBytes { Array($0) }
    }

    /// `RT`: 12-byte IV || AES-GCM ciphertext || 16-byte tag. Random IV unless one is given.
    static func gcmSeal(_ plaintext: [UInt8], key: SymmetricKey, iv: [UInt8]? = nil) throws -> [UInt8] {
        let nonce = try iv.map { try AES.GCM.Nonce(data: $0) } ?? AES.GCM.Nonce()
        let box = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
        return Array(box.nonce) + Array(box.ciphertext) + Array(box.tag)
    }

    /// `HT`: exactly 12 bytes decrypts to empty (Obsidian's convention); fewer is an error.
    static func gcmOpen(_ sealed: [UInt8], key: SymmetricKey) throws -> [UInt8] {
        guard sealed.count >= 12 else { throw ObsidianCryptoError.truncated }
        if sealed.count == 12 { return [] }
        guard sealed.count >= 28 else { throw ObsidianCryptoError.truncated }
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: sealed[0..<12]),
                                        ciphertext: sealed[12..<(sealed.count - 16)],
                                        tag: sealed[(sealed.count - 16)...])
        do { return Array(try AES.GCM.open(box, using: key)) } catch { throw ObsidianCryptoError.authenticationFailed }
    }
}

/// What the sync connection needs from a vault's encryption.
public protocol SyncEncryptionProvider: Sendable {
    var encryptionVersion: Int { get }
    var keyHash: String { get }
    /// Deterministic string encryption for paths and hashes → lowercase hex.
    func encodeString(_ plain: String) throws -> String
    func decodeString(_ hex: String) throws -> String
    /// Randomized content encryption (AES-GCM).
    func encrypt(_ data: [UInt8]) throws -> [UInt8]
    func decrypt(_ data: [UInt8]) throws -> [UInt8]
}

/// Encryption version 0 (legacy): the scrypt key is the AES-GCM key; keyhash = sha256(key);
/// deterministic strings use AES-GCM with IV = first 12 bytes of sha256(plaintext).
public final class ObsidianV0Provider: SyncEncryptionProvider, @unchecked Sendable {
    public let encryptionVersion = 0
    public let keyHash: String
    private let key: SymmetricKey

    public init(key: [UInt8]) throws {
        guard key.count == 32 else { throw ObsidianCryptoError.invalidKey }
        self.key = SymmetricKey(data: key)
        keyHash = Hex.encode(Array(SHA256.hash(data: key)))
    }

    public func encodeString(_ plain: String) throws -> String {
        let bytes = Array(plain.utf8)
        let iv = Array(SHA256.hash(data: bytes)).prefix(12)
        return Hex.encode(try ObsidianCrypto.gcmSeal(bytes, key: key, iv: Array(iv)))
    }

    public func decodeString(_ hex: String) throws -> String {
        guard let d = Hex.decode(hex) else { throw ObsidianCryptoError.invalidHex }
        guard let s = String(bytes: try ObsidianCrypto.gcmOpen(Array(d), key: key), encoding: .utf8) else { throw ObsidianCryptoError.invalidUTF8 }
        return s
    }

    public func encrypt(_ data: [UInt8]) throws -> [UInt8] { try ObsidianCrypto.gcmSeal(data, key: key) }
    public func decrypt(_ data: [UInt8]) throws -> [UInt8] { try ObsidianCrypto.gcmOpen(data, key: key) }
}

/// Encryption versions 2 and 3 (identical client-side; the number is reported to the server).
/// All sub-keys come from HKDF-SHA256 over the 32-byte scrypt key:
/// - keyhash  = hex(HKDF(salt: UTF-8 vault salt, info: "ObsidianKeyHash"))
/// - SIV MAC  = HKDF(salt: vault salt, info: "ObsidianAesSivMac")   (AES-256 for CMAC)
/// - SIV CTR  = HKDF(salt: vault salt, info: "ObsidianAesSivEnc")   (AES-256 for CTR)
/// - content  = HKDF(salt: empty,      info: "ObsidianAesGcm")      (AES-256-GCM)
public final class ObsidianV2Provider: SyncEncryptionProvider, @unchecked Sendable {
    public let encryptionVersion: Int
    public let keyHash: String
    private let gcm: SymmetricKey
    private let siv: ObsidianSIV
    let gcmKeyBytes: [UInt8]

    public init(key: [UInt8], salt: String, version: Int = 3) throws {
        guard key.count == 32 else { throw ObsidianCryptoError.invalidKey }
        guard version == 2 || version == 3 else { throw ObsidianCryptoError.unsupportedEncryptionVersion(version) }
        encryptionVersion = version
        let s = Array(salt.utf8)
        keyHash = Hex.encode(ObsidianCrypto.hkdf(key, salt: s, info: "ObsidianKeyHash"))
        siv = try ObsidianSIV(macKey: ObsidianCrypto.hkdf(key, salt: s, info: "ObsidianAesSivMac"),
                              ctrKey: ObsidianCrypto.hkdf(key, salt: s, info: "ObsidianAesSivEnc"))
        gcmKeyBytes = ObsidianCrypto.hkdf(key, salt: [], info: "ObsidianAesGcm")
        gcm = SymmetricKey(data: gcmKeyBytes)
    }

    public func encodeString(_ plain: String) throws -> String { Hex.encode(siv.seal(Array(plain.utf8))) }

    public func decodeString(_ hex: String) throws -> String {
        guard let d = Hex.decode(hex) else { throw ObsidianCryptoError.invalidHex }
        guard let s = String(bytes: try siv.open(Array(d)), encoding: .utf8) else { throw ObsidianCryptoError.invalidUTF8 }
        return s
    }

    public func encrypt(_ data: [UInt8]) throws -> [UInt8] { try ObsidianCrypto.gcmSeal(data, key: gcm) }
    public func decrypt(_ data: [UInt8]) throws -> [UInt8] { try ObsidianCrypto.gcmOpen(data, key: gcm) }

    /// Test hook: content encryption with a fixed IV.
    func encrypt(_ data: [UInt8], iv: [UInt8]) throws -> [UInt8] { try ObsidianCrypto.gcmSeal(data, key: gcm, iv: iv) }
}

extension ObsidianV0Provider {
    func encrypt(_ data: [UInt8], iv: [UInt8]) throws -> [UInt8] { try ObsidianCrypto.gcmSeal(data, key: key, iv: iv) }
}
