import Foundation

/// Reads boards written by obsidian-kanban: `## Lane` headings with `- [ ] card` items,
/// optional `**Complete**` marker, and a trailing `%% kanban:settings %%` block.
public struct KanbanBoard: Sendable, Equatable {
    public struct Card: Sendable, Equatable { public var text: String; public var done: Bool; public var line: Int }
    public struct Lane: Sendable, Equatable { public var title: String; public var cards: [Card] }
    public var lanes: [Lane]

    public static func isBoard(_ fm: Frontmatter) -> Bool { fm["kanban-plugin"] != nil }

    public static func parse(_ text: String) -> KanbanBoard {
        var lanes: [Lane] = []
        var inSettings = false
        for (i, raw) in text.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("%%") { inSettings.toggle(); if line.count > 2 && line.hasSuffix("%%") && line != "%%" { inSettings = false }; continue }
            if inSettings { continue }
            if line.hasPrefix("## ") { lanes.append(Lane(title: String(line.dropFirst(3)), cards: [])); continue }
            guard !lanes.isEmpty else { continue }
            if line.hasPrefix("- [") && line.count >= 5 {
                let mark = line[line.index(line.startIndex, offsetBy: 3)]
                let body = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                lanes[lanes.count - 1].cards.append(Card(text: body, done: mark != " ", line: i))
            } else if raw.hasPrefix("  ") || raw.hasPrefix("\t"), !line.isEmpty, var last = lanes[lanes.count - 1].cards.popLast() {
                last.text += "\n" + line
                lanes[lanes.count - 1].cards.append(last)
            }
        }
        return KanbanBoard(lanes: lanes)
    }
}
