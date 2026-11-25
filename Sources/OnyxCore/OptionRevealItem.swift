import Foundation

/// "Open in Obsidian" is a hidden menu item: it swaps in for Reveal in Finder
/// (or Open in Default App) while Option is held, or, with no such sibling, it
/// stays hidden until Option is down.
public enum OptionRevealItem {
    public static let title = "Open in Obsidian"

    public static func isTarget(_ title: String) -> Bool {
        title == Self.title || title.hasPrefix("Open in Obsidian")
    }

    /// The item it can swap with: Reveal in Finder, "Reveal N Items in Finder",
    /// or Open in Default App.
    public static func isSibling(_ title: String) -> Bool {
        if title == "Reveal in Finder" || title == "Open in Default App" { return true }
        return title.hasPrefix("Reveal ") && title.hasSuffix(" in Finder")
    }

    public enum Treatment: Equatable {
        /// `isAlternate` of the previous item; AppKit shows it while Option is held.
        case alternate
        /// No usable sibling: hide unless Option is already down.
        case optionOnly
    }

    public static func treatment(previousTitle: String?) -> Treatment {
        if let previousTitle, isSibling(previousTitle) { return .alternate }
        return .optionOnly
    }
}
