import Foundation

/// Saved split for one vault: axis, ratios, and the note (or docked graph) in each pane.
/// Stored beside the other per-vault keys (`recent`, `treeSort`, `bookmarks`).
public struct SplitLayout: Codable, Equatable, Sendable {
    public enum Axis: String, Codable, Sendable { case vertical, horizontal }

    public struct Pane: Codable, Equatable, Sendable {
        public var path: String?
        public var isGraph: Bool

        public init(path: String?, isGraph: Bool = false) {
            self.path = path
            self.isGraph = isGraph
        }
    }

    public var axis: Axis
    public var ratios: [Double]
    public var panes: [Pane]
    public var focused: Int

    public init(axis: Axis, ratios: [Double], panes: [Pane], focused: Int) {
        self.axis = axis
        self.ratios = ratios
        self.panes = panes
        self.focused = focused
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    public static func decode(_ data: Data) -> SplitLayout? {
        try? JSONDecoder().decode(SplitLayout.self, from: data)
    }

    /// Keep graph panes and notes that still exist, remap focus, and clamp ratios
    /// to a `minPane` floor in `total` points along the axis. Nil when nothing useful remains.
    public func sanitized(existing: (String) -> Bool, total: Double, minPane: Double = PaneRatios.minPane) -> SplitLayout? {
        var kept: [Pane] = []
        var keptRatios: [Double] = []
        let r = PaneRatios.normalized(ratios, count: panes.count)
        let oldFocused = panes.isEmpty ? 0 : min(max(focused, 0), panes.count - 1)
        var newFocused = 0
        for (i, p) in panes.enumerated() {
            let keep = p.isGraph || (p.path.map(existing) ?? false)
            guard keep else { continue }
            if i == oldFocused { newFocused = kept.count }
            kept.append(p)
            keptRatios.append(i < r.count ? r[i] : 0)
        }
        guard kept.contains(where: { !$0.isGraph && $0.path != nil }) else { return nil }
        if !kept.indices.contains(newFocused) || kept[newFocused].isGraph {
            newFocused = kept.indices.first(where: { !kept[$0].isGraph }) ?? 0
        }
        if kept.count == 1 {
            return SplitLayout(axis: axis, ratios: [1], panes: kept, focused: 0)
        }
        let clamped = PaneRatios.clamped(keptRatios, count: kept.count, total: total, minPane: minPane)
        return SplitLayout(axis: axis, ratios: clamped, panes: kept, focused: newFocused)
    }
}

/// Whether this process may write per-vault session state (split layout, etc.).
/// Screenshot and test hooks share the installed app's defaults, so they must not.
public enum SessionPersistence {
    public static func isEnabled(environment env: [String: String] = ProcessInfo.processInfo.environment,
                                 arguments: [String] = CommandLine.arguments,
                                 vaultPath: String?) -> Bool {
        if env["ONYX_SHOT_QUIET"] == "1" { return false }
        if env["ONYX_NO_DEFAULT_VAULT"] != nil { return false }
        if env["ONYX_TYPE_TEST"] != nil { return false }
        if env["ONYX_KEY_SELFTEST"] != nil { return false }
        if env["ONYX_SCROLL_TEST"] != nil { return false }
        if env["ONYX_OPEN_SETTINGS"] != nil { return false }
        if arguments.contains("--split") || arguments.contains("--pane-ratios") { return false }
        if let p = vaultPath, p.hasPrefix("/tmp/") || p.hasPrefix("/private/tmp/") { return false }
        return true
    }
}
