import Foundation

/// Everyday shortcuts shown on the first-run (and hold-⌘) hint sheet.
/// Keys come from ShortcutStore, so the sheet follows Settings ▸ Shortcuts.
public enum ShortcutHints {
    /// Rows as `(keycaps, caption)`. Unbound commands are omitted.
    public static func all(store: ShortcutStore = .shared) -> [(String, String)] {
        var rows: [(String, String)] = []

        func displays(for ids: [String]) -> [String] {
            ids.flatMap { store.chords(for: $0) }.map(\.display)
        }

        /// First chord in the key column; any further chords go in the caption as "also …".
        func add(_ ids: [String], _ caption: String) {
            let keys = displays(for: ids)
            guard let first = keys.first else { return }
            let rest = keys.dropFirst()
            var cap = caption
            if !rest.isEmpty { cap += " (also " + rest.joined(separator: " ") + ")" }
            rows.append((first, cap))
        }

        /// Every chord in the key column (bold · italic, back · forward).
        func addCombined(_ ids: [String], _ caption: String) {
            let keys = displays(for: ids)
            guard !keys.isEmpty else { return }
            rows.append((keys.joined(separator: "  "), caption))
        }

        add(["switcher"], "Find or create a note")
        add(["palette"], "Every command")
        add(["files"], "Show or hide the sidebar")
        add(["search"], "Search the vault")
        add(["mode", "modetoggle"], "Read ⇄ edit, saving")
        add(["daily"], "Today’s daily note")
        add(["inspector"], "Inspector: outline, backlinks, properties")
        addCombined(["bold", "italic"], "Bold · italic")

        let graph = displays(for: ["graph"])
        if let graphKey = graph.first {
            var cap = "Focus graph overlay · click or " + graphKey + " again to close"
            let atlas = store.display(for: "atlas")
            if !atlas.isEmpty { cap += " · " + atlas + " atlas" }
            cap += " · double-click a folder to fill the view · Esc fits all, then closes"
            let pane = store.display(for: "graphpane")
            if !pane.isEmpty { cap += " · " + pane + " graph in a pane (title-bar button: ⇧-click for the atlas)" }
            rows.append((graphKey, cap))
        }

        addCombined(["back", "forward"], "Back · forward (mouse buttons, swipe)")
        rows.append(("⌘⌫", "Delete to the start of the line · in the sidebar, delete the selection"))
        add(["move"], "Move note to… (links follow)")

        let split = displays(for: ["split"])
        if let splitKey = split.first {
            var cap = "Split"
            let stacked = store.display(for: "splitdown")
            if !stacked.isEmpty { cap += " · " + stacked + " stacked" }
            let close = store.display(for: "closepane")
            if !close.isEmpty { cap += " · " + close + " close" }
            rows.append((splitKey, cap))
        }

        let find = displays(for: ["find"])
        if let findKey = find.first {
            var cap = "Find in note"
            let replace = store.display(for: "findreplace")
            if !replace.isEmpty { cap += " · " + replace + " replace" }
            let vault = store.display(for: "replacevault")
            if !vault.isEmpty { cap += " · " + vault + " replace in the vault" }
            cap += " · ⌘G/⇧⌘G or ↩/⇧↩ next/previous while finding"
            rows.append((findKey, cap))
        }

        add(["focus"], "Focus: just the text")
        rows.append(("Esc", "Put things away · in the editor, return to reading"))
        return rows
    }
}
