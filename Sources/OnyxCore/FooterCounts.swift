import Foundation

/// The footer's note (or attachment) counts, and the labels it shows as the bar shrinks.
///
/// Priority is words, then backlinks, then characters: a tight bar keeps the word count,
/// shortens or drops characters first, and uses compact forms ("2 links", "370w") before
/// dropping an item. The tooltip is always the full detail.
public struct FooterCounts: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case note
        case attachment(label: String)
    }

    /// Click cycle: auto-fit as much as will fit, then pin one metric at a time.
    public enum Cycle: Int, CaseIterable, Sendable {
        case auto, words, characters, backlinks
    }

    public var words: Int
    public var characters: Int
    public var backlinks: Int
    public var kind: Kind

    public init(words: Int, characters: Int, backlinks: Int, kind: Kind = .note) {
        self.words = words
        self.characters = characters
        self.backlinks = backlinks
        self.kind = kind
    }

    /// Full detail, shown in the tooltip regardless of which label fits.
    public var tooltip: String {
        switch kind {
        case .note:
            var parts = [phrase(words, "word"), phrase(characters, "character")]
            if backlinks > 0 { parts.append(phrase(backlinks, "backlink")) }
            return parts.joined(separator: " · ")
        case .attachment(let label):
            return backlinks > 0 ? "\(label) · \(phrase(backlinks, "backlink"))" : label
        }
    }

    /// Widest-first labels for `ViewThatFits`. A pinned cycle returns that metric's forms.
    public func labels(cycle: Cycle = .auto) -> [String] {
        switch cycle {
        case .auto:
            return autoLabels()
        case .words:
            switch kind {
            case .note: return uniqued([phrase(words, "word"), compactWords])
            case .attachment(let label): return [label]
            }
        case .characters:
            switch kind {
            case .note:
                return uniqued([phrase(characters, "character"), phrase(characters, "char"), "\(n(characters))c"])
            case .attachment(let label): return [label]
            }
        case .backlinks:
            guard backlinks > 0 else { return autoLabels() }
            return uniqued([phrase(backlinks, "backlink"), phrase(backlinks, "link")])
        }
    }

    public func next(_ cycle: Cycle) -> Cycle {
        switch kind {
        case .attachment:
            return (backlinks > 0 && cycle == .auto) ? .backlinks : .auto
        case .note:
            switch cycle {
            case .auto: return .words
            case .words: return .characters
            case .characters: return backlinks > 0 ? .backlinks : .auto
            case .backlinks: return .auto
            }
        }
    }

    private func autoLabels() -> [String] {
        switch kind {
        case .note:
            let w = phrase(words, "word")
            let chars = phrase(characters, "character")
            let charsShort = phrase(characters, "char")
            var out: [String] = []
            if backlinks > 0 {
                let links = phrase(backlinks, "backlink")
                let linksShort = phrase(backlinks, "link")
                out.append("\(w) · \(chars) · \(links)")
                out.append("\(w) · \(charsShort) · \(linksShort)")
                out.append("\(w) · \(links)")
                out.append("\(w) · \(linksShort)")
                out.append("\(compactWords) · \(linksShort)")
            } else {
                out.append("\(w) · \(chars)")
                out.append("\(w) · \(charsShort)")
            }
            out.append(w)
            out.append(compactWords)
            return uniqued(out)
        case .attachment(let label):
            guard backlinks > 0 else { return [label] }
            return uniqued([
                "\(label) · \(phrase(backlinks, "backlink"))",
                "\(label) · \(phrase(backlinks, "link"))",
                label
            ])
        }
    }

    private var compactWords: String { "\(n(words))w" }

    private func phrase(_ count: Int, _ singular: String) -> String {
        let unit = count == 1 ? singular : singular + "s"
        return "\(n(count)) \(unit)"
    }

    private func n(_ count: Int) -> String { count.formatted() }

    private func uniqued(_ items: [String]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for s in items where seen.insert(s).inserted { out.append(s) }
        return out
    }
}
