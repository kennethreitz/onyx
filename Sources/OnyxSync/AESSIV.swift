import CommonCrypto
import Foundation

/// A single-key AES block encryptor (ECB on one 16-byte block at a time) via CommonCrypto.
final class AESBlock {
    private var ref: CCCryptorRef?

    init(key: [UInt8]) throws {
        let status = CCCryptorCreate(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                                     key, key.count, nil, &ref)
        guard status == kCCSuccess, ref != nil else { throw ObsidianCryptoError.cipherSetupFailed(status) }
    }
    deinit { if let ref { CCCryptorRelease(ref) } }

    func encrypt(_ block: [UInt8]) -> [UInt8] {
        precondition(block.count == 16)
        var out = [UInt8](repeating: 0, count: 16)
        var moved = 0
        let status = CCCryptorUpdate(ref, block, 16, &out, 16, &moved)
        precondition(status == kCCSuccess && moved == 16, "AES block encrypt failed")
        return out
    }
}

/// AES-SIV exactly as Obsidian Sync implements it for deterministic path/hash encryption
/// (encryption versions 2 and 3). It is RFC 5297 S2V/CMAC with no associated data, with one quirk:
/// the CTR stage uses WebCrypto `AES-CTR` with `length: 16`, so only the low 16 bits of the counter
/// block increment and they wrap without carrying. A strict RFC 5297 library produces different
/// ciphertext whenever those 16 bits overflow mid-message; see the `ctrWrap` test vector.
public final class ObsidianSIV {
    private let mac: AESBlock
    private let ctr: AESBlock
    private let k1: [UInt8]
    private let k2: [UInt8]

    /// `macKey` = HKDF(info "ObsidianAesSivMac"), `ctrKey` = HKDF(info "ObsidianAesSivEnc"); both 32 bytes.
    public init(macKey: [UInt8], ctrKey: [UInt8]) throws {
        mac = try AESBlock(key: macKey)
        ctr = try AESBlock(key: ctrKey)
        let L = mac.encrypt([UInt8](repeating: 0, count: 16))
        k1 = ObsidianSIV.dbl(L)
        k2 = ObsidianSIV.dbl(k1)
    }

    public func seal(_ plaintext: [UInt8]) -> [UInt8] {
        let v = s2v(plaintext)
        return v + ctrCrypt(counter: v, plaintext)
    }

    public func open(_ sealed: [UInt8]) throws -> [UInt8] {
        guard sealed.count >= 16 else { throw ObsidianCryptoError.truncated }
        let v = Array(sealed[0..<16])
        let plain = ctrCrypt(counter: v, Array(sealed[16...]))
        guard constantTimeEqual(s2v(plain), v) else { throw ObsidianCryptoError.authenticationFailed }
        return plain
    }

    // MARK: - S2V / CMAC

    func s2v(_ s: [UInt8]) -> [UInt8] {
        var d = cmac([UInt8](repeating: 0, count: 16))
        let t: [UInt8]
        if s.count >= 16 {
            var tail = Array(s[(s.count - 16)...])
            for i in 0..<16 { tail[i] ^= d[i] }
            t = Array(s[..<(s.count - 16)]) + tail
        } else {
            var padded = s + [0x80] + [UInt8](repeating: 0, count: 15 - s.count)
            d = ObsidianSIV.dbl(d)
            for i in 0..<16 { padded[i] ^= d[i] }
            t = padded
        }
        return cmac(t)
    }

    func cmac(_ m: [UInt8]) -> [UInt8] {
        let n = max(1, (m.count + 15) / 16)
        let complete = !m.isEmpty && m.count % 16 == 0
        var x = [UInt8](repeating: 0, count: 16)
        for i in 0..<(n - 1) {
            for j in 0..<16 { x[j] ^= m[i * 16 + j] }
            x = mac.encrypt(x)
        }
        var last = [UInt8](repeating: 0, count: 16)
        let start = (n - 1) * 16
        let rem = m.count - start
        for j in 0..<rem { last[j] = m[start + j] }
        if complete {
            for j in 0..<16 { last[j] ^= k1[j] }
        } else {
            last[rem] = 0x80
            for j in 0..<16 { last[j] ^= k2[j] }
        }
        for j in 0..<16 { x[j] ^= last[j] }
        return mac.encrypt(x)
    }

    static func dbl(_ b: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 16)
        var carry: UInt8 = 0
        for i in stride(from: 15, through: 0, by: -1) {
            out[i] = (b[i] << 1) | carry
            carry = b[i] >> 7
        }
        if carry == 1 { out[15] ^= 0x87 }
        return out
    }

    // MARK: - CTR (WebCrypto length:16 semantics)

    func ctrCrypt(counter v: [UInt8], _ data: [UInt8]) -> [UInt8] {
        var q = v
        q[8] &= 0x7f; q[12] &= 0x7f
        let low = UInt16(q[14]) << 8 | UInt16(q[15])
        var out = [UInt8](repeating: 0, count: data.count)
        var block = 0
        var offset = 0
        while offset < data.count {
            let c = low &+ UInt16(truncatingIfNeeded: block)
            q[14] = UInt8(c >> 8); q[15] = UInt8(c & 0xff)
            let ks = ctr.encrypt(q)
            let end = min(offset + 16, data.count)
            for i in offset..<end { out[i] = data[i] ^ ks[i - offset] }
            offset = end; block += 1
        }
        return out
    }
}

func constantTimeEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
    guard a.count == b.count, !a.isEmpty else { return false }
    var diff: UInt8 = 0
    for i in 0..<a.count { diff |= a[i] ^ b[i] }
    return diff == 0
}
