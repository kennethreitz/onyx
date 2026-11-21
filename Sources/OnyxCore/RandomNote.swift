import Foundation

/// Selection for the Open Random Note command.
public enum RandomNote {
    /// Paths the command may open. The current note is dropped when at least one other path exists.
    public static func candidates(in paths: [String], excluding current: String?) -> [String] {
        guard let current else { return paths }
        let rest = paths.filter { $0 != current }
        return rest.isEmpty ? paths : rest
    }

    public static func pick(from paths: [String], excluding current: String?, using rng: inout some RandomNumberGenerator) -> String? {
        candidates(in: paths, excluding: current).randomElement(using: &rng)
    }

    public static func pick(from paths: [String], excluding current: String?) -> String? {
        var rng = SystemRandomNumberGenerator()
        return pick(from: paths, excluding: current, using: &rng)
    }
}
