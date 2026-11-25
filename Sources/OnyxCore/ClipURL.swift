import Foundation

/// Builds `onyx://clip?…` URLs. Dependency-free on purpose: the Safari and Share extensions
/// (Extensions/, built by scripts/build-extensions.sh) compile this file directly, and
/// `WebClip.request(from:)` in the app reads what it writes.
public enum ClipURL {
    /// Parameters the clipper understands, in a stable order.
    public static let keys = ["url", "title", "selection", "text", "author", "description", "published", "site", "folder"]

    /// Percent-encode everything except unreserved characters, so `+`, `&`, `=` and `#`
    /// in a value survive (URLComponents leaves `+` alone, which some parsers read as a space).
    public static func encode(_ s: String) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    /// `onyx://clip?url=…&title=…` from string fields; empty values are left out.
    /// Nil when there is nothing to clip (no url, selection or text).
    public static func make(_ fields: [String: Any]) -> URL? {
        var parts: [String] = []
        for k in keys {
            guard let v = fields[k] as? String else { continue }
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            parts.append(k + "=" + encode(k == "selection" || k == "text" ? v : t))
        }
        let hasContent = ["url", "selection", "text"].contains { k in
            ((fields[k] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        guard hasContent else { return nil }
        return URL(string: "onyx://clip?" + parts.joined(separator: "&"))
    }
}
