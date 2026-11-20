import Foundation

/// Edits an Obsidian Kanban board (obsidian-kanban plugin format) by splicing lines, so everything
/// it doesn't touch (frontmatter, the `%% kanban:settings %%` block, spacing, card markup) stays
/// byte-for-byte as it was. No edit means no change at all. Lane bodies keep the plugin's own
/// layout: `## Lane`, a blank line, the cards, two blank lines; an empty lane is the heading plus
/// three blank lines. Archived cards go under `***` / `## Archive`, before the settings block.
public struct KanbanDoc: Sendable {
    public struct Card: Sendable, Equatable {
        public var start: Int, end: Int   // lines [start, end): the card line plus indented continuation lines
        public var done: Bool
    }
    public struct Lane: Sendable, Equatable {
        public var heading: Int
        public var title: String
        public var cards: [Card]
    }
    public private(set) var lines: [String]
    public private(set) var lanes: [Lane] = []
    public private(set) var archiveHeading: Int?
    public private(set) var archive: [Card] = []
    public private(set) var settingsLine: Int?
    public private(set) var archiveRule: Int?

    public init(_ text: String) {
        lines = text.components(separatedBy: "\n")
        parse()
    }
    public var text: String { lines.joined(separator: "\n") }

    static func isCard(_ l: String) -> Bool {
        l.count >= 5 && l.hasPrefix("- [") && l[l.index(l.startIndex, offsetBy: 4)] == "]"
    }

    mutating func parse() {
        lanes = []; archive = []; archiveHeading = nil; settingsLine = nil; archiveRule = nil
        var i = 0
        if lines.first == "---", let close = lines.dropFirst().firstIndex(of: "---") { i = close + 1 }
        var inArchive = false
        var open: Card?   // the card whose continuation lines we're still reading
        func flush(_ s: inout KanbanDoc) {
            guard let c = open else { return }
            if inArchive { s.archive.append(c) } else if !s.lanes.isEmpty { s.lanes[s.lanes.count - 1].cards.append(c) }
            open = nil
        }
        while i < lines.count {
            let l = lines[i]
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("%% kanban:settings") { flush(&self); settingsLine = i; break }
            if var c = open, !t.isEmpty, l.first == " " || l.first == "\t" { c.end = i + 1; open = c; i += 1; continue }
            flush(&self)
            if t == "***" && !inArchive { inArchive = true; archiveRule = i }
            else if l.hasPrefix("## ") {
                if inArchive { archiveHeading = i }
                else { lanes.append(Lane(heading: i, title: String(l.dropFirst(3)), cards: [])) }
            } else if Self.isCard(l), inArchive ? archiveHeading != nil : !lanes.isEmpty {
                let mark = l[l.index(l.startIndex, offsetBy: 3)]
                open = Card(start: i, end: i + 1, done: mark != " ")
            }
            i += 1
        }
        flush(&self)
    }

    func block(_ c: Card) -> [String] { Array(lines[c.start..<c.end]) }
    /// The card's text as shown: the first line after `- [ ] `, then its continuation lines.
    public func cardText(_ c: Card) -> String {
        let b = block(c)
        return ([String(b[0].dropFirst(5)).trimmingCharacters(in: .whitespaces)] + b.dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }).joined(separator: "\n")
    }
    func valid(_ lane: Int, _ card: Int) -> Bool { lanes.indices.contains(lane) && lanes[lane].cards.indices.contains(card) }

    /// Where a card lands in a lane at `index` (0...count).
    func insertionLine(lane: Int, index: Int) -> Int {
        let ln = lanes[lane]
        if index < ln.cards.count { return ln.cards[index].start }
        if let last = ln.cards.last { return last.end }
        var at = ln.heading + 1
        if at < lines.count, lines[at].trimmingCharacters(in: .whitespaces).isEmpty { at += 1 }
        if at < lines.count, lines[at].trimmingCharacters(in: .whitespaces) == "**Complete**" { at += 1 }
        return at
    }

    // MARK: Operations (false = nothing to do; the text is unchanged)

    @discardableResult public mutating func toggle(lane: Int, card: Int) -> Bool {
        guard valid(lane, card) else { return false }
        let i = lanes[lane].cards[card].start
        var chars = Array(lines[i])
        chars[3] = chars[3] == " " ? "x" : " "
        lines[i] = String(chars)
        parse()
        return true
    }

    /// Move a card; `index` is its position in the destination lane once it has left its old place.
    @discardableResult public mutating func move(lane: Int, card: Int, toLane: Int, index: Int) -> Bool {
        guard valid(lane, card), lanes.indices.contains(toLane) else { return false }
        if lane == toLane && (index == card) { return false }
        let c = lanes[lane].cards[card]
        let b = block(c)
        lines.removeSubrange(c.start..<c.end)
        parse()
        let at = insertionLine(lane: toLane, index: max(0, min(index, lanes[toLane].cards.count)))
        lines.insert(contentsOf: b, at: at)
        parse()
        return true
    }

    @discardableResult public mutating func add(lane: Int, text: String, index: Int? = nil) -> Bool {
        guard lanes.indices.contains(lane) else { return false }
        let b = Self.cardLines(text, done: false, indent: "    ")
        guard !b.isEmpty else { return false }
        lines.insert(contentsOf: b, at: insertionLine(lane: lane, index: index ?? lanes[lane].cards.count))
        parse()
        return true
    }

    @discardableResult public mutating func edit(lane: Int, card: Int, text: String) -> Bool {
        guard valid(lane, card) else { return false }
        let c = lanes[lane].cards[card]
        let old = block(c)
        let indent = old.dropFirst().first.map { String($0.prefix { $0 == " " || $0 == "\t" }) } ?? "    "
        let b = Self.cardLines(text, done: c.done, indent: indent, mark: old[0][old[0].index(old[0].startIndex, offsetBy: 3)])
        guard !b.isEmpty, b != old else { return false }
        lines.replaceSubrange(c.start..<c.end, with: b)
        parse()
        return true
    }

    @discardableResult public mutating func delete(lane: Int, card: Int) -> Bool {
        guard valid(lane, card) else { return false }
        let c = lanes[lane].cards[card]
        lines.removeSubrange(c.start..<c.end)
        parse()
        return true
    }

    /// The plugin's archive: `***`, `## Archive`, then the cards, ahead of the settings block.
    @discardableResult public mutating func archive(lane: Int, card: Int) -> Bool {
        guard valid(lane, card) else { return false }
        let c = lanes[lane].cards[card]
        let b = block(c)
        lines.removeSubrange(c.start..<c.end)
        parse()
        if let h = archiveHeading {
            var at = archive.last?.end ?? h + 1
            if archive.isEmpty, at < lines.count, lines[at].trimmingCharacters(in: .whitespaces).isEmpty { at += 1 }
            lines.insert(contentsOf: b, at: at)
        } else {
            // after the last lane's two trailing blank lines, before the blank run ahead of the settings
            var at = settingsLine ?? lines.count
            while at > 0, lines[at - 1].trimmingCharacters(in: .whitespaces).isEmpty { at -= 1 }
            let lastLaneEnd = at
            at = min(lastLaneEnd + 2, settingsLine ?? lines.count)
            var section = ["***", "", "## Archive", ""] + b
            if at < lastLaneEnd + 2 { section = Array(repeating: "", count: lastLaneEnd + 2 - at) + section }
            section += ["", ""]
            if settingsLine == nil && at == lines.count && lines.last == "" { section.removeLast() }
            lines.insert(contentsOf: section, at: at)
        }
        parse()
        return true
    }

    /// A card's markdown: `- [ ] first line`, later lines indented (how the plugin keeps multi-line cards).
    static func cardLines(_ text: String, done: Bool, indent: String, mark: Character? = nil) -> [String] {
        let parts = text.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var trimmed = parts
        while trimmed.last?.isEmpty == true { trimmed.removeLast() }
        while trimmed.first?.isEmpty == true { trimmed.removeFirst() }
        guard let first = trimmed.first else { return [] }
        let m = mark ?? (done ? "x" : " ")
        return ["- [\(m)] " + first] + trimmed.dropFirst().filter { !$0.isEmpty }.map { indent + $0 }
    }
}
