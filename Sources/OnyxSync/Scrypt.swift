import CommonCrypto
import Foundation

/// scrypt (RFC 7914) with PBKDF2-HMAC-SHA256 from CommonCrypto and a Salsa20/8 core in Swift.
/// CryptoKit has no scrypt, so this is a small self-contained implementation.
public enum Scrypt {
    public enum Error: Swift.Error { case invalidParameters, pbkdf2Failed(Int32) }

    public static func derive(password: [UInt8], salt: [UInt8], N: Int, r: Int, p: Int, length: Int) throws -> [UInt8] {
        guard N > 1, N & (N - 1) == 0, r > 0, p > 0, length > 0 else { throw Error.invalidParameters }
        let blockBytes = 128 * r
        var B = try pbkdf2(password: password, salt: salt, length: p * blockBytes)
        let wordsPerBlock = 32 * r
        var X = [UInt32](repeating: 0, count: wordsPerBlock)
        var Y = [UInt32](repeating: 0, count: wordsPerBlock)
        var V = [UInt32](repeating: 0, count: wordsPerBlock * N)
        for chunk in 0..<p {
            let base = chunk * blockBytes
            for k in 0..<wordsPerBlock {
                let o = base + 4 * k
                X[k] = UInt32(B[o]) | UInt32(B[o + 1]) << 8 | UInt32(B[o + 2]) << 16 | UInt32(B[o + 3]) << 24
            }
            X.withUnsafeMutableBufferPointer { x in
                Y.withUnsafeMutableBufferPointer { y in
                    V.withUnsafeMutableBufferPointer { v in
                        roMix(x, y, v, r: r, N: N)
                    }
                }
            }
            for k in 0..<wordsPerBlock {
                let o = base + 4 * k, w = X[k]
                B[o] = UInt8(truncatingIfNeeded: w); B[o + 1] = UInt8(truncatingIfNeeded: w >> 8)
                B[o + 2] = UInt8(truncatingIfNeeded: w >> 16); B[o + 3] = UInt8(truncatingIfNeeded: w >> 24)
            }
        }
        return try pbkdf2(password: password, salt: B, length: length)
    }

    static func pbkdf2(password: [UInt8], salt: [UInt8], length: Int) throws -> [UInt8] {
        var out = [UInt8](repeating: 0, count: length)
        let status = password.withUnsafeBufferPointer { pw in
            salt.withUnsafeBufferPointer { s in
                pw.baseAddress!.withMemoryRebound(to: Int8.self, capacity: max(pw.count, 1)) { pwp in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pwp, pw.count,
                                         s.baseAddress, s.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 1,
                                         &out, length)
                }
            }
        }
        guard status == kCCSuccess else { throw Error.pbkdf2Failed(status) }
        return out
    }

    private static func roMix(_ X: UnsafeMutableBufferPointer<UInt32>, _ Y: UnsafeMutableBufferPointer<UInt32>,
                              _ V: UnsafeMutableBufferPointer<UInt32>, r: Int, N: Int) {
        let n = 32 * r
        for i in 0..<N {
            _ = UnsafeMutableBufferPointer(rebasing: V[(i * n)..<(i * n + n)]).update(fromContentsOf: X)
            blockMix(X, Y, r: r)
        }
        for _ in 0..<N {
            let j = Int(X[(2 * r - 1) * 16] & UInt32(N - 1))
            let vb = j * n
            for k in 0..<n { X[k] ^= V[vb + k] }
            blockMix(X, Y, r: r)
        }
    }

    /// BlockMix_salsa20/8: in place on X, Y as scratch.
    private static func blockMix(_ B: UnsafeMutableBufferPointer<UInt32>, _ Y: UnsafeMutableBufferPointer<UInt32>, r: Int) {
        var x = [UInt32](repeating: 0, count: 16)
        for k in 0..<16 { x[k] = B[(2 * r - 1) * 16 + k] }
        x.withUnsafeMutableBufferPointer { xp in
            for i in 0..<(2 * r) {
                for k in 0..<16 { xp[k] ^= B[i * 16 + k] }
                salsa208(xp)
                // Even blocks go to the first half, odd to the second.
                let dst = (i % 2 == 0 ? i / 2 : r + i / 2) * 16
                for k in 0..<16 { Y[dst + k] = xp[k] }
            }
        }
        for k in 0..<(32 * r) { B[k] = Y[k] }
    }

    @inline(__always) private static func R(_ a: UInt32, _ b: UInt32) -> UInt32 { (a << b) | (a >> (32 - b)) }

    private static func salsa208(_ B: UnsafeMutableBufferPointer<UInt32>) {
        var x0 = B[0], x1 = B[1], x2 = B[2], x3 = B[3], x4 = B[4], x5 = B[5], x6 = B[6], x7 = B[7]
        var x8 = B[8], x9 = B[9], x10 = B[10], x11 = B[11], x12 = B[12], x13 = B[13], x14 = B[14], x15 = B[15]
        for _ in 0..<4 {
            x4 ^= R(x0 &+ x12, 7); x8 ^= R(x4 &+ x0, 9); x12 ^= R(x8 &+ x4, 13); x0 ^= R(x12 &+ x8, 18)
            x9 ^= R(x5 &+ x1, 7); x13 ^= R(x9 &+ x5, 9); x1 ^= R(x13 &+ x9, 13); x5 ^= R(x1 &+ x13, 18)
            x14 ^= R(x10 &+ x6, 7); x2 ^= R(x14 &+ x10, 9); x6 ^= R(x2 &+ x14, 13); x10 ^= R(x6 &+ x2, 18)
            x3 ^= R(x15 &+ x11, 7); x7 ^= R(x3 &+ x15, 9); x11 ^= R(x7 &+ x3, 13); x15 ^= R(x11 &+ x7, 18)
            x1 ^= R(x0 &+ x3, 7); x2 ^= R(x1 &+ x0, 9); x3 ^= R(x2 &+ x1, 13); x0 ^= R(x3 &+ x2, 18)
            x6 ^= R(x5 &+ x4, 7); x7 ^= R(x6 &+ x5, 9); x4 ^= R(x7 &+ x6, 13); x5 ^= R(x4 &+ x7, 18)
            x11 ^= R(x10 &+ x9, 7); x8 ^= R(x11 &+ x10, 9); x9 ^= R(x8 &+ x11, 13); x10 ^= R(x9 &+ x8, 18)
            x12 ^= R(x15 &+ x14, 7); x13 ^= R(x12 &+ x15, 9); x14 ^= R(x13 &+ x12, 13); x15 ^= R(x14 &+ x13, 18)
        }
        B[0] &+= x0; B[1] &+= x1; B[2] &+= x2; B[3] &+= x3; B[4] &+= x4; B[5] &+= x5; B[6] &+= x6; B[7] &+= x7
        B[8] &+= x8; B[9] &+= x9; B[10] &+= x10; B[11] &+= x11; B[12] &+= x12; B[13] &+= x13; B[14] &+= x14; B[15] &+= x15
    }
}
