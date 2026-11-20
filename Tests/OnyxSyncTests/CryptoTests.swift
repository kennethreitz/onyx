import XCTest
@testable import OnyxSync

/// Vectors come from scripts/obsidian-sync-vectors.mjs, a transcription of Obsidian 1.15.1's sync crypto run on
/// Node WebCrypto, independently cross-checked with Python `cryptography` (scrypt, HKDF, RFC 5297 AES-SIV, AES-GCM).
final class CryptoVectorTests: XCTestCase {
    struct Vectors: Decodable {
        struct Det: Decodable { let plain: String; let cipher: String }
        struct Content: Decodable { let plainHex: String; let iv: String; let cipher: String; let sha256: String }
        struct Version: Decodable { let keyHash: String; let gcmKey: String?; let deterministic: [Det]; let content: Content }
        struct Case: Decodable { let password: String; let salt: String; let key: String; let versions: [String: Version] }
        let cases: [Case]
        let ctrWrap: Det
    }

    static let vectors: Vectors = {
        let url = Bundle.module.url(forResource: "obsidian-sync-vectors", withExtension: "json")!
        return try! JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
    }()

    func bytes(_ h: String) -> [UInt8] { Array(Hex.decode(h)!) }

    func testScryptVaultKeyMatchesObsidian() throws {
        // Full-cost scrypt (N=32768) for each case, including NFKC folding of a fullwidth password.
        for c in Self.vectors.cases {
            XCTAssertEqual(Hex.encode(try ObsidianCrypto.deriveVaultKey(password: c.password, salt: c.salt)), c.key, c.password)
        }
    }

    func testV3KeyHashSIVAndGCM() throws {
        for c in Self.vectors.cases {
            let v = c.versions["3"]!
            let p = try ObsidianV2Provider(key: bytes(c.key), salt: c.salt, version: 3)
            XCTAssertEqual(p.keyHash, v.keyHash)
            XCTAssertEqual(Hex.encode(p.gcmKeyBytes), v.gcmKey)
            for d in v.deterministic {
                XCTAssertEqual(try p.encodeString(d.plain), d.cipher, "encode \(d.plain.prefix(40))")
                XCTAssertEqual(try p.decodeString(d.cipher), d.plain)
            }
            XCTAssertEqual(Hex.encode(try p.encrypt(bytes(v.content.plainHex), iv: bytes(v.content.iv))), v.content.cipher)
            XCTAssertEqual(Hex.encode(try p.decrypt(bytes(v.content.cipher))), v.content.plainHex)
            XCTAssertEqual(ObsidianCrypto.contentHash(bytes(v.content.plainHex)), v.content.sha256)
        }
    }

    func testV0Provider() throws {
        for c in Self.vectors.cases {
            let v = c.versions["0"]!
            let p = try ObsidianV0Provider(key: bytes(c.key))
            XCTAssertEqual(p.keyHash, v.keyHash)
            for d in v.deterministic {
                XCTAssertEqual(try p.encodeString(d.plain), d.cipher)
                XCTAssertEqual(try p.decodeString(d.cipher), d.plain)
            }
            XCTAssertEqual(Hex.encode(try p.encrypt(bytes(v.content.plainHex), iv: bytes(v.content.iv))), v.content.cipher)
            XCTAssertEqual(Hex.encode(try p.decrypt(bytes(v.content.cipher))), v.content.plainHex)
        }
    }

    /// Obsidian's AES-SIV CTR counter wraps in its low 16 bits (WebCrypto length:16) instead of carrying.
    func testSIVCounterWrapQuirk() throws {
        let c = Self.vectors.cases[0]
        let p = try ObsidianV2Provider(key: bytes(c.key), salt: c.salt)
        let w = Self.vectors.ctrWrap
        XCTAssertTrue(w.cipher.dropFirst(28).hasPrefix("ffff"), "probe's SIV low 16 bits should be 0xffff")
        XCTAssertEqual(try p.encodeString(w.plain), w.cipher)
        XCTAssertEqual(try p.decodeString(w.cipher), w.plain)
    }

    func testTamperingIsRejected() throws {
        let c = Self.vectors.cases[0]
        let p = try ObsidianV2Provider(key: bytes(c.key), salt: c.salt)
        var enc = Array(Hex.decode(try p.encodeString("Daily/2026-11-20.md"))!)
        enc[enc.count - 1] ^= 1
        XCTAssertThrowsError(try p.decodeString(Hex.encode(enc)))
        var ct = try p.encrypt(Array("hello".utf8)); ct[ct.count - 1] ^= 1
        XCTAssertThrowsError(try p.decrypt(ct))
        XCTAssertEqual(try p.decrypt(Array(repeating: 0, count: 12)), [])   // Obsidian: bare IV = empty file
    }

    func testRoundTripRandom() throws {
        let p = try ObsidianV2Provider(key: (0..<32).map { _ in UInt8.random(in: 0...255) }, salt: "abc")
        for n in [0, 1, 15, 16, 17, 31, 32, 33, 255, 4097] {
            let s = String((0..<n).map { _ in "abcdefghijklmnopqrstuvwxyzäöü/ .".randomElement()! })
            XCTAssertEqual(try p.decodeString(try p.encodeString(s)), s)
            XCTAssertEqual(try p.encodeString(s), try p.encodeString(s), "deterministic")
            let d = (0..<n).map { _ in UInt8.random(in: 0...255) }
            XCTAssertEqual(try p.decrypt(try p.encrypt(d)), d)
        }
    }
}

final class ScryptTests: XCTestCase {
    // RFC 7914 §12 test vectors.
    func testRFC7914() throws {
        XCTAssertEqual(Hex.encode(try Scrypt.derive(password: [], salt: [], N: 16, r: 1, p: 1, length: 64)),
                       "77d6576238657b203b19ca42c18a0497f16b4844e3074ae8dfdffa3fede21442fcd0069ded0948f8326a753a0fc81f17e8d3e0fb2e0d3628cf35e20c38d18906")
        XCTAssertEqual(Hex.encode(try Scrypt.derive(password: Array("password".utf8), salt: Array("NaCl".utf8), N: 1024, r: 8, p: 16, length: 64)),
                       "fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b3731622eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640")
    }
}

final class APIShapeTests: XCTestCase {
    func testHostRules() throws {
        XCTAssertEqual(try SyncConnection.url(forHost: "sync-7.obsidian.md").absoluteString, "wss://sync-7.obsidian.md")
        XCTAssertThrowsError(try SyncConnection.url(forHost: "evil.example.com"))
        XCTAssertThrowsError(try SyncConnection.url(forHost: "obsidian.md.evil.com"))
        XCTAssertThrowsError(try SyncConnection.url(forHost: "127.0.0.1:3003"))
        XCTAssertEqual(try SyncConnection.url(forHost: "127.0.0.1:3003", allowLocal: true).absoluteString, "ws://127.0.0.1:3003")
    }

    func testExtension() {
        XCTAssertEqual(SyncConnection.fileExtension("Daily/Note.MD"), "md")
        XCTAssertEqual(SyncConnection.fileExtension(".obsidian/app.json"), "json")
        XCTAssertEqual(SyncConnection.fileExtension("folder.d/.hidden"), "")
        XCTAssertEqual(SyncConnection.fileExtension("README"), "")
        XCTAssertEqual(SyncConnection.fileExtension("trailing."), "")
    }

    func testVaultListDecodes() throws {
        let json = #"{"vaults":[{"id":"abc","name":"Notes","host":"sync-3.obsidian.md","salt":"s","encryption_version":3,"size":1}],"shared":[],"limit":10}"#
        let l = try JSONDecoder().decode(ObsidianAPI.VaultList.self, from: Data(json.utf8))
        XCTAssertEqual(l.vaults.first?.host, "sync-3.obsidian.md")
        XCTAssertNil(l.vaults.first?.password)
    }
}
