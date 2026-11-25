import Foundation

/// Shared typeset reading options: the same keys and `typeset` payload the Mac
/// Settings pane and the iOS reader both feed to `typeset.js`.
public enum TypesetSettings {
    public enum Key {
        public static let on = "onyx.typeset"
        public static let oldstyle = "onyx.oldstyleFigures"
        public static let hyphens = "onyx.hyphenation"
        public static let smallCaps = "onyx.smallCaps"
        public static let face = "onyx.typeface"              // "lm" | "et" | "od"
        public static let opening = "onyx.opening"            // "smallcaps" | "dropcap" | "none"
        public static let justify = "onyx.justify"
        /// Retired: OpenDyslexic is a typeface (`od`), not a separate toggle.
        public static let openDyslexicLegacy = "onyx.openDyslexic"
    }

    public static let faces: [(id: String, title: String)] = [
        ("lm", "Latin Modern (Reitz LaTeX)"),
        ("et", "ET Book (Tufte)"),
        ("od", "OpenDyslexic"),
    ]

    public static func normalizedFace(_ raw: String?) -> String {
        (raw == "et" || raw == "od") ? raw! : "lm"
    }

    /// Promote the old `onyx.openDyslexic` toggle to the OpenDyslexic typeface and drop the key.
    public static func migrateOpenDyslexic(in defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: Key.openDyslexicLegacy) != nil else { return }
        if defaults.bool(forKey: Key.openDyslexicLegacy) {
            defaults.set("od", forKey: Key.face)
            defaults.set(true, forKey: Key.on)
        }
        defaults.removeObject(forKey: Key.openDyslexicLegacy)
    }

    public static func options(
        on: Bool,
        onum: Bool,
        hyphens: Bool,
        smallCaps: Bool,
        justify: Bool,
        face: String,
        opening: String,
        preview: Bool = false,
        print: [String: Any]? = nil
    ) -> [String: Any] {
        let face = normalizedFace(face)
        let open = preview ? "none" : ((face == "od" && opening == "dropcap") ? "smallcaps" : opening)
        var o: [String: Any] = [
            "on": on, "onum": onum, "hyphens": hyphens, "smallCaps": smallCaps,
            "justify": justify, "face": face, "opening": open,
        ]
        if let print { o["print"] = print }
        return o
    }

    /// Load from UserDefaults using the shared keys.
    public static func options(from defaults: UserDefaults = .standard, preview: Bool = false, print: [String: Any]? = nil) -> [String: Any] {
        migrateOpenDyslexic(in: defaults)
        func bool(_ k: String, dflt: Bool = true) -> Bool { defaults.object(forKey: k) as? Bool ?? dflt }
        return options(
            on: bool(Key.on),
            onum: bool(Key.oldstyle),
            hyphens: bool(Key.hyphens),
            smallCaps: bool(Key.smallCaps),
            justify: bool(Key.justify, dflt: false),
            face: defaults.string(forKey: Key.face) ?? "lm",
            opening: defaults.string(forKey: Key.opening) ?? "smallcaps",
            preview: preview,
            print: print
        )
    }
}
