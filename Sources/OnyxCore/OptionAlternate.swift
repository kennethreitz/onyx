import Foundation

/// Hidden Option-hold alternates in menus: the item is invisible until Option is held,
/// and when it sits just after a sibling (Copy File Path, Reveal in Finder, …) AppKit
/// swaps the two. The command palette is left alone.
public enum OptionAlternate {
    public struct Rule: Equatable, Sendable {
        public var title: String
        /// Also treat titles that start with this as targets (for "Open in Obsidian" prefixes).
        public var titleHasPrefix: String?
        public var exactSiblings: [String]
        /// e.g. ("Reveal ", " in Finder") also matches "Reveal 3 Items in Finder".
        public var siblingPrefix: String?
        public var siblingSuffix: String?

        public init(title: String, titleHasPrefix: String? = nil, exactSiblings: [String] = [],
                    siblingPrefix: String? = nil, siblingSuffix: String? = nil) {
            self.title = title; self.titleHasPrefix = titleHasPrefix
            self.exactSiblings = exactSiblings
            self.siblingPrefix = siblingPrefix; self.siblingSuffix = siblingSuffix
        }

        public func isTarget(_ title: String) -> Bool {
            title == self.title || (titleHasPrefix.map { title.hasPrefix($0) && !$0.isEmpty } ?? false)
        }

        public func isSibling(_ title: String) -> Bool {
            if exactSiblings.contains(title) { return true }
            if let p = siblingPrefix, let s = siblingSuffix, title.hasPrefix(p), title.hasSuffix(s) { return true }
            return false
        }

        public func treatment(previousTitle: String?) -> OptionRevealItem.Treatment {
            if let previousTitle, isSibling(previousTitle) { return .alternate }
            return .optionOnly
        }
    }

    public static let all: [Rule] = [
        Rule(title: OptionRevealItem.title, titleHasPrefix: OptionRevealItem.title,
             exactSiblings: ["Reveal in Finder", "Open in Default App"],
             siblingPrefix: "Reveal ", siblingSuffix: " in Finder"),
        Rule(title: "Copy Onyx URL",
             exactSiblings: ["Copy File Path", "Copy Wikilink"]),
    ]

    public static func rule(for title: String) -> Rule? { all.first { $0.isTarget(title) } }
}
