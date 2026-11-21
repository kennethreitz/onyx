import Foundation

/// User overrides for command shortcuts, persisted in UserDefaults.
///
/// A missing entry means “use the catalog default.” A stored `null` means the
/// command is unbound. A stored chord replaces every default for that command.
public final class ShortcutStore {
    public static let defaultsKey = "onyx.shortcuts"
    public static let didChange = Notification.Name("onyx.shortcuts.didChange")

    public static let shared = ShortcutStore()

    private let defaults: UserDefaults
    private let key: String
    private let catalog: [CommandSpec]
    private var overrides: [String: KeyChord?] = [:]

    public init(defaults: UserDefaults = .standard, key: String = ShortcutStore.defaultsKey, catalog: [CommandSpec] = CommandCatalog.all) {
        self.defaults = defaults
        self.key = key
        self.catalog = catalog
        self.overrides = Self.load(from: defaults, key: key)
    }

    /// Live chords for a command: the override (or nothing if cleared), else the defaults.
    public func chords(for id: String) -> [KeyChord] {
        if let entry = overrides[id] {
            if let chord = entry { return [chord] }
            return []
        }
        return catalog.first(where: { $0.id == id })?.defaultChords ?? []
    }

    public func display(for id: String) -> String {
        chords(for: id).map(\.display).joined(separator: "  ")
    }

    public func isOverridden(_ id: String) -> Bool { overrides[id] != nil }

    public func commandId(for chord: KeyChord) -> String? {
        for spec in catalog {
            if chords(for: spec.id).contains(chord) { return spec.id }
        }
        return nil
    }

    public func conflict(for chord: KeyChord, excluding id: String) -> (id: String, title: String)? {
        guard let other = commandId(for: chord), other != id else { return nil }
        let title = catalog.first(where: { $0.id == other })?.title ?? other
        return (other, title)
    }

    /// What would happen if `id` were given `chord`.
    public func evaluate(_ chord: KeyChord, for id: String) -> ShortcutProposal {
        ShortcutProposal(
            reservedReason: KeyChord.reservedReason(chord),
            conflictId: conflict(for: chord, excluding: id)?.id,
            conflictTitle: conflict(for: chord, excluding: id)?.title
        )
    }

    /// Conflicts that would appear if this command returned to its defaults.
    public func conflictsOnReset(_ id: String) -> [(chord: KeyChord, commandId: String, title: String)] {
        guard let spec = catalog.first(where: { $0.id == id }) else { return [] }
        var out: [(KeyChord, String, String)] = []
        for chord in spec.defaultChords {
            if let c = conflict(for: chord, excluding: id) {
                out.append((chord, c.id, c.title))
            }
        }
        return out
    }

    /// Bind `id` to `chord`. If `replacing` is set, that command is unbound first (or
    /// loses just the stolen chord when it still has others).
    public func assign(_ id: String, _ chord: KeyChord, replacing: String? = nil) {
        if let other = replacing { remove(chord, from: other) }
        overrides[id] = chord
        persist()
    }

    /// Remove any shortcut from this command.
    public func clear(_ id: String) {
        overrides[id] = .some(nil)
        persist()
    }

    /// Return this command to its shipping defaults. If `replacing` is set, those
    /// commands lose any default chord this one is taking back.
    public func reset(_ id: String, replacing: [String] = []) {
        for other in replacing {
            if let spec = catalog.first(where: { $0.id == id }) {
                for chord in spec.defaultChords { remove(chord, from: other) }
            }
        }
        overrides.removeValue(forKey: id)
        persist()
    }

    public func resetAll() {
        overrides.removeAll()
        persist()
    }

    /// Reload from UserDefaults (for a persistence round-trip in tests).
    public func reload() {
        overrides = Self.load(from: defaults, key: key)
    }

    private func remove(_ chord: KeyChord, from id: String) {
        let remaining = chords(for: id).filter { $0 != chord }
        if remaining.isEmpty {
            overrides[id] = .some(nil)
        } else if remaining.count == 1, let only = remaining.first {
            overrides[id] = only
        } else {
            // More than one remaining: record the first and drop the rest, since an
            // override is a single chord. After a steal from a multi-default command,
            // keep whatever is left; if two remain, store the first and... we only
            // support one override chord. For two remaining, clear override? That
            // would restore the stolen chord too. So store the first remaining.
            overrides[id] = remaining[0]
        }
    }

    private func persist() {
        var object: [String: Any] = [:]
        let encoder = JSONEncoder()
        for (id, value) in overrides {
            if let chord = value, let data = try? encoder.encode(chord),
               let json = try? JSONSerialization.jsonObject(with: data) {
                object[id] = json
            } else {
                object[id] = NSNull()
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: object) {
            defaults.set(data, forKey: key)
        }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    private static func load(from defaults: UserDefaults, key: String) -> [String: KeyChord?] {
        let data: Data
        if let d = defaults.data(forKey: key) {
            data = d
        } else if let object = defaults.dictionary(forKey: key),
                  let d = try? JSONSerialization.data(withJSONObject: object) {
            data = d
        } else {
            return [:]
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        let decoder = JSONDecoder()
        var out: [String: KeyChord?] = [:]
        for (id, value) in object {
            if value is NSNull {
                out[id] = .some(nil)
            } else if JSONSerialization.isValidJSONObject(value),
                      let data = try? JSONSerialization.data(withJSONObject: value),
                      let chord = try? decoder.decode(KeyChord.self, from: data) {
                out[id] = .some(chord)
            }
        }
        return out
    }
}

/// The warnings that should appear before a shortcut is assigned.
public struct ShortcutProposal: Equatable, Sendable {
    public var reservedReason: String?
    public var conflictId: String?
    public var conflictTitle: String?

    public var isReserved: Bool { reservedReason != nil }
    public var hasConflict: Bool { conflictId != nil }
    public var isClear: Bool { !isReserved && !hasConflict }
}
