import Foundation

/// The edit a smart-pair keystroke should make, or a caret move when typing
/// a closer that is already the next character.
public enum SmartPairsAction: Equatable, Sendable {
    case replace(TextEdit)
    case move(NSRange)
}

/// Auto-pairing for brackets, quotes, and Markdown markers, matching Obsidian's
/// "Auto pair brackets" and "Auto pair Markdown syntax". Ranges are UTF-16.
public enum SmartPairs {

    public struct Settings: Equatable, Sendable {
        public var autoPairBrackets: Bool
        public var autoPairMarkdown: Bool

        public init(autoPairBrackets: Bool = true, autoPairMarkdown: Bool = true) {
            self.autoPairBrackets = autoPairBrackets
            self.autoPairMarkdown = autoPairMarkdown
        }

        /// Missing keys mean on, as in Obsidian.
        public static func from(appJSON: [String: Any]?) -> Settings {
            Settings(
                autoPairBrackets: appJSON?["autoPairBrackets"] as? Bool ?? true,
                autoPairMarkdown: appJSON?["autoPairMarkdown"] as? Bool ?? true
            )
        }
    }

    /// `(`, `[`, `{` and quotes. Quotes also close themselves.
    static let brackets: [Character: Character] = [
        "(": ")", "[": "]", "{": "}",
        "\"": "\"", "'": "'", "`": "`",
    ]
    /// Wrap-only Markdown markers (`*` `_` `~` `=`). Not auto-paired without a selection.
    static let markdown: Set<Character> = ["*", "_", "~", "="]

    /// The edit for a typed string, or `nil` to insert it as usual. Only a single
    /// pairing character is intercepted (paste and `]]` completions pass through).
    public static func insert(_ text: String, _ sel: NSRange, typed: String, settings: Settings) -> SmartPairsAction? {
        guard typed.count == 1, let ch = typed.first else { return nil }
        let ns = text as NSString
        let sel = EditCommands.clamp(sel, ns.length)
        let isOpener = brackets[ch] != nil
        let isMarkdown = markdown.contains(ch)
        let isTypedCloser = brackets.contains { $0.value == ch && $0.key != ch }
        guard isOpener || isMarkdown || isTypedCloser else { return nil }

        if isMarkdown {
            guard settings.autoPairMarkdown, !inFence(text, sel) else { return nil }
        } else {
            guard settings.autoPairBrackets else { return nil }
        }

        if sel.length > 0 {
            guard isOpener || isMarkdown else { return nil }
            let closer = brackets[ch] ?? ch
            let inner = ns.substring(with: sel)
            let rep = String(ch) + inner + String(closer)
            let innerStart = sel.location + 1
            return .replace(TextEdit(
                range: sel,
                replacement: rep,
                selection: NSRange(location: innerStart, length: sel.length)
            ))
        }

        // Step over a closer that's already there. Typing `[` in `[|]` is not
        // a close — it inserts a second pair, `[[|]]`.
        if shouldStepOver(ch, next: next(ns, after: sel.location)) {
            return .move(NSRange(location: sel.location + 1, length: 0))
        }
        guard isOpener else { return nil }
        if isQuote(ch), midWord(ns, before: sel.location) { return nil }
        let closer = brackets[ch]!
        let rep = String(ch) + String(closer)
        return .replace(TextEdit(
            range: sel,
            replacement: rep,
            selection: NSRange(location: sel.location + 1, length: 0)
        ))
    }

    /// Backspace between an empty pair (`(|)`) deletes both characters.
    public static func deleteBackward(_ text: String, _ sel: NSRange, settings: Settings) -> TextEdit? {
        let ns = text as NSString
        let sel = EditCommands.clamp(sel, ns.length)
        guard sel.length == 0, sel.location > 0, sel.location < ns.length else { return nil }
        let prevRange = ns.rangeOfComposedCharacterSequence(at: sel.location - 1)
        let nextRange = ns.rangeOfComposedCharacterSequence(at: sel.location)
        guard prevRange.length == 1, nextRange.length == 1 else { return nil }
        let prev = ns.substring(with: prevRange)
        let next = ns.substring(with: nextRange)
        guard let opener = prev.first, let following = next.first else { return nil }
        guard let closer = closer(for: opener), closer == following else { return nil }
        if markdown.contains(opener) {
            guard settings.autoPairMarkdown, !inFence(text, sel) else { return nil }
        } else {
            guard settings.autoPairBrackets, brackets[opener] != nil else { return nil }
        }
        let range = NSRange(location: prevRange.location, length: NSMaxRange(nextRange) - prevRange.location)
        return TextEdit(range: range, replacement: "", selection: NSRange(location: prevRange.location, length: 0))
    }

    // MARK: Helpers

    /// Typing a closer (or a self-closing quote / Markdown marker) steps over
    /// that same character when it is already next. An opener like `[` in `[|]`
    /// does not step; it inserts a nested pair.
    static func shouldStepOver(_ ch: Character, next: Character?) -> Bool {
        guard let next else { return false }
        if markdown.contains(ch) { return ch == next }
        if let pair = brackets[ch], pair == ch { return ch == next }   // quotes
        return brackets.contains { $0.value == ch && $0.key != ch } && ch == next
    }

    static func closer(for ch: Character) -> Character? {
        if let c = brackets[ch] { return c }
        if markdown.contains(ch) { return ch }
        if brackets.contains(where: { $0.value == ch && $0.key != ch }) { return ch }
        return nil
    }

    static func isQuote(_ ch: Character) -> Bool { ch == "\"" || ch == "'" || ch == "`" }

    static func midWord(_ ns: NSString, before loc: Int) -> Bool {
        guard loc > 0 else { return false }
        let r = ns.rangeOfComposedCharacterSequence(at: loc - 1)
        guard let ch = (ns.substring(with: r) as String).first else { return false }
        return ch.isLetter || ch.isNumber || ch == "_"
    }

    static func next(_ ns: NSString, after loc: Int) -> Character? {
        guard loc < ns.length else { return nil }
        let r = ns.rangeOfComposedCharacterSequence(at: loc)
        return (ns.substring(with: r) as String).first
    }

    /// Markdown markers are left alone inside a fenced code block (including an
    /// unclosed fence through EOF). Brackets and quotes still pair there.
    static func inFence(_ text: String, _ sel: NSRange) -> Bool {
        let n = (text as NSString).length
        let loc = sel.location
        for r in NoteParser.codeRanges(text) {
            if sel.length == 0 {
                if loc >= r.location && loc < NSMaxRange(r) { return true }
                if loc == n, NSMaxRange(r) == n, loc >= r.location { return true }
            } else if NSIntersectionRange(r, sel).length > 0 {
                return true
            }
        }
        return false
    }
}
