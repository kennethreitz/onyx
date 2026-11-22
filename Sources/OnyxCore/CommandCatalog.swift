import Foundation

/// Settings and documentation groups for bindable commands.
public enum CommandGroup: String, CaseIterable, Sendable {
    case file, edit, format, view, navigate, pane, note

    public var title: String {
        switch self {
        case .file: "File"
        case .edit: "Edit"
        case .format: "Format"
        case .view: "View"
        case .navigate: "Navigate"
        case .pane: "Pane"
        case .note: "Note"
        }
    }
}

/// A bindable command: stable id, title, group, and the shipping default shortcut(s).
public struct CommandSpec: Equatable, Sendable {
    public var id: String
    public var title: String
    public var group: CommandGroup
    public var defaultChords: [KeyChord]
    public var symbol: String?

    public init(id: String, title: String, group: CommandGroup, defaultChords: [KeyChord] = [], symbol: String? = nil) {
        self.id = id
        self.title = title
        self.group = group
        self.defaultChords = defaultChords
        self.symbol = symbol
    }
}

/// Every command whose shortcut can be customized. Defaults match the shipping menus.
public enum CommandCatalog {
    public static let all: [CommandSpec] = [
        // File
        cmd("new", "New Note", .file, [.command("n")], "square.and.pencil"),
        cmd("newfolder", "New Folder", .file, [.command("n", shift: true)], "folder.badge.plus"),
        cmd("openvault", "Open Vault…", .file, [.command("o", shift: true)]),
        cmd("switcher", "Quick Switcher…", .file, [.command("o")], "doc.text.magnifyingglass"),
        cmd("palette", "Command Palette…", .file, [.command("p"), .command("p", shift: true)], "command"),
        cmd("save", "Save", .file, [.command("s")]),
        cmd("rename", "Rename Note…", .file, [], "pencil.line"),
        cmd("move", "Move Note to…", .file, [.command("m", shift: true)], "folder"),
        cmd("delete", "Delete Note…", .file, [.command("\u{7F}")], "trash"),
        cmd("exportpdf", "Export as PDF…", .file, [.command("e", shift: true)], "doc.richtext"),
        cmd("exportsel", "Export Selection as PDF…", .file, [], "doc.on.doc"),
        cmd("exportfolder", "Export Folder as PDF…", .file, [], "folder"),
        cmd("print", "Print…", .file, [.command("p", option: true)], "printer"),
        cmd("duplicate", "Duplicate Note", .file, [], "plus.square.on.square"),
        cmd("copypath", "Copy File Path", .file, [], "doc.on.clipboard"),
        cmd("openexternal", "Open in Default App", .file, [], "arrow.up.right.square"),
        cmd("settings", "Open Settings…", .file, [], "gearshape"),

        // Edit
        cmd("find", "Find in Note…", .edit, [.command("f")]),
        cmd("findreplace", "Find and Replace…", .edit, [.command("f", option: true)]),
        cmd("searchsel", "Search Vault for Selection", .edit, [], "text.magnifyingglass"),
        cmd("spellcheck", "Toggle Spellcheck", .edit, [], "textformat.abc.dottedunderline"),
        cmd("merge", "Merge Current File With Another File…", .edit, [], "arrow.triangle.merge"),
        cmd("extract", "Extract Current Selection…", .edit, [], "text.badge.plus"),
        cmd("extractheading", "Extract This Heading…", .edit, [], "text.justify.left"),

        // Format (Obsidian's editor commands; ⌘I and ⌘K stay with the inspector and sidebar)
        cmd("bold", "Toggle Bold", .format, [.command("b")], "bold"),
        cmd("italic", "Toggle Italic", .format, [], "italic"),
        cmd("strike", "Toggle Strikethrough", .format, [], "strikethrough"),
        cmd("highlight", "Toggle Highlight", .format, [], "highlighter"),
        cmd("inlinecode", "Toggle Inline Code", .format, [], "chevron.left.forwardslash.chevron.right"),
        cmd("comment", "Toggle Comment", .format, [.command("/")], "eye.slash"),
        cmd("wikilink", "Insert Wikilink", .format, [], "link"),
        cmd("mdlink", "Insert Markdown Link", .format, [], "link.badge.plus"),
        cmd("h1", "Heading 1", .format, [], "textformat.size"),
        cmd("h2", "Heading 2", .format),
        cmd("h3", "Heading 3", .format),
        cmd("h4", "Heading 4", .format),
        cmd("h5", "Heading 5", .format),
        cmd("h6", "Heading 6", .format),
        cmd("bullet", "Toggle Bullet List", .format, [], "list.bullet"),
        cmd("numbered", "Toggle Numbered List", .format, [], "list.number"),
        cmd("checklist", "Toggle Checklist", .format, [], "checklist"),
        cmd("checkbox", "Cycle Checkbox", .format, [.command("l")], "checkmark.square"),
        cmd("quote", "Toggle Blockquote", .format, [], "text.quote"),
        cmd("indent", "Indent", .format, [], "increase.indent"),
        cmd("outdent", "Outdent", .format, [], "decrease.indent"),
        cmd("callout", "Insert Callout", .format, [], "exclamationmark.bubble"),
        cmd("codeblock", "Insert Code Block", .format, [], "curlybraces"),
        cmd("table", "Insert Table", .format, [], "tablecells"),
        cmd("hr", "Insert Horizontal Rule", .format, [], "minus"),
        cmd("date", "Insert Current Date", .format, [], "calendar"),
        cmd("time", "Insert Current Time", .format, [], "clock"),
        cmd("lineup", "Move Line Up", .format, [], "arrow.up"),
        cmd("linedown", "Move Line Down", .format, [], "arrow.down"),
        cmd("dupline", "Duplicate Line", .format, [], "plus.rectangle.on.rectangle"),
        cmd("delline", "Delete Line", .format, [], "delete.left"),

        // View
        cmd("modetoggle", "Read Note / Edit Note", .view, [.command("e")]),
        cmd("mode", "Save and Read / Edit and Save", .view, [.command("\r")], "book"),
        cmd("focus", "Focus Mode", .view, [.command("f", control: true)], "arrow.up.left.and.arrow.down.right"),
        cmd("files", "Show Sidebar", .view, [.command("k")], "folder"),
        cmd("search", "Search Vault", .view, [.command("f", shift: true)], "magnifyingglass"),
        cmd("recent", "Recent Files", .view, [.command("r", shift: true)], "clock"),
        cmd("bookmarks", "Bookmarks", .view, [.command("b", shift: true)], "bookmark"),
        cmd("tags", "Tags", .view, [.command("t", shift: true)], "number"),
        cmd("git", "Source Control", .view, [.command("y", shift: true)], "arrow.triangle.branch"),
        cmd("inspector", "Inspector", .view, [.command("i")], "sidebar.right"),
        cmd("outline", "Outline", .view, [.command("1", option: true)], "list.bullet.indent"),
        cmd("backlinks", "Backlinks", .view, [.command("2", option: true)], "arrow.uturn.backward"),
        cmd("props", "Properties", .view, [.command("3", option: true)], "tablecells"),
        cmd("layout", "Three-Pane Workspace", .view, [.command("0", option: true)], "rectangle.split.3x1"),
        cmd("sidenotes", "Footnotes as Sidenotes", .view, [], "text.append"),
        cmd("light", "Appearance: Light", .view, [], "sun.max"),
        cmd("dark", "Appearance: Dark", .view, [], "moon"),
        cmd("system", "Appearance: Match System", .view, [], "circle.lefthalf.filled"),
        cmd("synclog", "Show Sync Log", .view, [], "list.bullet.rectangle"),
        cmd("zoomin", "Zoom In", .view, [.command("=")], "plus.magnifyingglass"),
        cmd("zoomout", "Zoom Out", .view, [.command("-")], "minus.magnifyingglass"),
        cmd("zoomreset", "Actual Size", .view, [.command("0")], "1.magnifyingglass"),

        // Navigate
        cmd("daily", "Today’s Daily Note", .navigate, [.command("t"), .command("\\")], "calendar"),
        cmd("daily-prev", "Previous Daily Note", .navigate, [.command("[", option: true)], "calendar.badge.minus"),
        cmd("daily-next", "Next Daily Note", .navigate, [.command("]", option: true)], "calendar.badge.plus"),
        cmd("back", "Back", .navigate, [.command("[")], "chevron.left"),
        cmd("forward", "Forward", .navigate, [.command("]")], "chevron.right"),
        cmd("home", "Homepage", .navigate, [.command("h", shift: true)], "house"),
        cmd("random", "Open Random Note", .navigate, [], "shuffle"),
        cmd("graph", "Focus Graph", .navigate, [.command("g")], "point.3.connected.trianglepath.dotted"),
        cmd("atlas", "Atlas", .navigate, [.command("g", shift: true)], "circle.hexagongrid"),
        cmd("graphpane", "Graph in a Pane", .navigate, [.command("g", option: true)]),
        cmd("daily-yesterday", "Yesterday’s Daily Note", .navigate, [], "calendar.badge.minus"),
        cmd("daily-tomorrow", "Tomorrow’s Daily Note", .navigate, [], "calendar.badge.plus"),
        cmd("headings", "Jump to Heading…", .navigate, [], "list.bullet.indent"),
        cmd("revealtree", "Reveal in Sidebar", .navigate, [], "sidebar.left"),

        // Pane
        cmd("split", "Split Side by Side", .pane, [.command("d")], "rectangle.split.2x1"),
        cmd("splitdown", "Split Stacked", .pane, [.command("d", shift: true)], "rectangle.split.1x2"),
        cmd("closepane", "Close Pane", .pane, [.command("w")], "xmark.square"),
        cmd("nextpane", "Next Pane", .pane, [.chord("\t", .control)], "arrow.right.square"),
        cmd("prevpane", "Previous Pane", .pane, [.chord("\t", [.control, .shift])]),
        cmd("newpane", "New Note in New Pane", .pane, [], "square.split.2x1"),

        // Note
        cmd("bookmark", "Bookmark", .note, [.command("d", option: true)], "bookmark.fill"),
        cmd("copy", "Copy Wikilink", .note, [.command("l", shift: true)], "link"),
        cmd("finder", "Reveal in Finder", .note, [.command("r", shift: true, option: true)], "folder.badge.gearshape"),
        cmd("obsidian", "Open in Obsidian", .note, [], "arrow.up.forward.app"),
        cmd("lint", "Lint Current Note", .note, [], "checkmark.seal"),
        cmd("lintfolder", "Lint All Notes in Folder…", .note, [], "folder.badge.gearshape"),
        cmd("readaloud", "Read Aloud", .note, [], "speaker.wave.2"),
        cmd("readpause", "Pause Reading", .note, [], "pause.fill"),
        cmd("readstop", "Stop Reading", .note, [], "stop.fill"),
        cmd("record", "Record Audio", .note, [], "mic"),
        cmd("reindex", "Rebuild Index", .note, [], "arrow.clockwise"),
        cmd("hints", "Show Shortcut Hints", .note, []),
    ]

    public static let byId: [String: CommandSpec] = {
        var d: [String: CommandSpec] = [:]
        for c in all { d[c.id] = c }
        return d
    }()

    public static func spec(_ id: String) -> CommandSpec? { byId[id] }
    public static func title(_ id: String) -> String { byId[id]?.title ?? id }

    public static func grouped() -> [(CommandGroup, [CommandSpec])] {
        CommandGroup.allCases.compactMap { g in
            let items = all.filter { $0.group == g }
            return items.isEmpty ? nil : (g, items)
        }
    }

    private static func cmd(_ id: String, _ title: String, _ group: CommandGroup, _ chords: [KeyChord] = [], _ symbol: String? = nil) -> CommandSpec {
        CommandSpec(id: id, title: title, group: group, defaultChords: chords, symbol: symbol)
    }
}
