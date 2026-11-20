import Foundation

/// Lowercase hex, matching Obsidian's `Rs()` (two nibbles per byte, no separators).
public enum Hex {
    public static func encode<D: DataProtocol>(_ data: D) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var out = [UInt8](); out.reserveCapacity(data.count * 2)
        for b in data { out.append(digits[Int(b >> 4)]); out.append(digits[Int(b & 0x0f)]) }
        return String(decoding: out, as: UTF8.self)
    }

    /// Strict decode; returns nil on odd length or a non-hex digit.
    /// (Obsidian's `J2()` uses parseInt and silently yields NaN→0; we refuse instead.)
    public static func decode(_ string: String) -> Data? {
        let chars = Array(string.utf8)
        guard chars.count % 2 == 0 else { return nil }
        func nib(_ c: UInt8) -> UInt8? {
            switch c {
            case 48...57: return c - 48
            case 97...102: return c - 87
            case 65...70: return c - 55
            default: return nil
            }
        }
        var out = Data(capacity: chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let hi = nib(chars[i]), let lo = nib(chars[i + 1]) else { return nil }
            out.append(hi << 4 | lo); i += 2
        }
        return out
    }
}
