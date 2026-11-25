import Foundation

/// Obsidian's `.obsidian/bookmarks.json`: a tree of file, folder, heading, search,
/// graph, URL, and group items. Unknown keys and unknown item types are kept so a
/// round-trip does not drop what Obsidian (or a plugin) stored.
public struct BookmarkStore {
    public var items: [BookmarkItem]
    /// Top-level keys other than `items`, preserved on write.
    public var extras: [String: Any]

    public init(items: [BookmarkItem] = [], extras: [String: Any] = [:]) {
        self.items = items
        self.extras = extras
    }

    /// An empty store when `data` is missing or empty. `nil` when the file is present
    /// but isn't a JSON object, so the caller can refuse to overwrite it.
    public static func parse(data: Data?) -> BookmarkStore? {
        guard let data, !data.isEmpty else { return BookmarkStore() }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parse(object: obj)
    }

    public static func parse(object: [String: Any]) -> BookmarkStore {
        var extras = object
        let raw = extras.removeValue(forKey: "items") as? [Any] ?? []
        return BookmarkStore(items: raw.compactMap { ($0 as? [String: Any]).map(BookmarkItem.parse) }, extras: extras)
    }

    public var jsonObject: [String: Any] {
        var o = extras
        o["items"] = itemsJSON
        return o
    }

    public var itemsJSON: [[String: Any]] { items.map { $0.jsonObject } }

    public func containsFile(path: String, subpath: String? = nil) -> Bool {
        let sub = BookmarkSubpath.normalize(subpath)
        return find({ $0.isFile(path: path, subpath: sub) }) != nil
    }

    public func containsFolder(path: String) -> Bool {
        find({ $0.isFolder(path: path) }) != nil
    }

    /// A file (any heading) or a folder at `path`.
    public func containsPath(_ path: String) -> Bool {
        find({ $0.matchesPath(path) }) != nil
    }

    /// Remove the matching file bookmark if it exists (including inside a group);
    /// otherwise append a new top-level file item. Returns whether it is now bookmarked.
    @discardableResult
    public mutating func toggleFile(path: String, subpath: String? = nil, now: Int64) -> Bool {
        let sub = BookmarkSubpath.normalize(subpath)
        if removeAll({ $0.isFile(path: path, subpath: sub) }) { return false }
        items.append(BookmarkItem.file(path: path, subpath: sub, ctime: now))
        return true
    }

    @discardableResult
    public mutating func toggleFolder(path: String, now: Int64) -> Bool {
        if removeAll({ $0.isFolder(path: path) }) { return false }
        items.append(BookmarkItem.folder(path: path, ctime: now))
        return true
    }

    @discardableResult
    public mutating func remove(id: UUID) -> BookmarkItem? {
        remove(where: { $0.id == id })
    }

    /// Move `id` into `parent` (nil = top level), inserting before `beforeID`
    /// (nil = append). No-op if the move would drop an item into itself or a descendant.
    public mutating func move(id: UUID, parent: UUID?, before beforeID: UUID?) {
        guard id != beforeID, id != parent else { return }
        if let parent, isDescendant(parent, of: id) { return }
        guard let item = remove(id: id) else { return }
        if let parent {
            guard update(id: parent, { group in
                guard group.type == "group" else { return false }
                var kids = group.items ?? []
                if let beforeID, let i = kids.firstIndex(where: { $0.id == beforeID }) {
                    kids.insert(item, at: i)
                } else {
                    kids.append(item)
                }
                group.items = kids
                return true
            }) else {
                items.append(item)
                return
            }
        } else if let beforeID, let i = items.firstIndex(where: { $0.id == beforeID }) {
            items.insert(item, at: i)
        } else {
            items.append(item)
        }
    }

    /// Insert a file or folder bookmark at `parent` (nil = top level), before
    /// `beforeID` (nil = append). If an equivalent bookmark already exists
    /// anywhere in the tree, it is moved to that position instead of adding a
    /// second copy. A heading bookmark of the same file does not count as a
    /// duplicate of the whole-file pin. Returns whether the store changed.
    @discardableResult
    public mutating func insert(path: String, isFolder: Bool, subpath: String? = nil, parent: UUID?, before beforeID: UUID?, now: Int64) -> Bool {
        let sub = isFolder ? nil : BookmarkSubpath.normalize(subpath)
        if let existing = find({
            isFolder ? $0.isFolder(path: path) : $0.isFile(path: path, subpath: sub)
        }) {
            let beforeIDs = idOrder
            move(id: existing.id, parent: parent, before: beforeID)
            return idOrder != beforeIDs
        }
        let item = isFolder
            ? BookmarkItem.folder(path: path, ctime: now)
            : BookmarkItem.file(path: path, subpath: sub, ctime: now)
        if parent == nil, beforeID == nil {
            items.append(item)
            return true
        }
        items.append(item)
        move(id: item.id, parent: parent, before: beforeID)
        return true
    }

    /// Depth-first ids, used to detect a no-op move.
    var idOrder: [UUID] {
        func walk(_ items: [BookmarkItem]) -> [UUID] {
            items.flatMap { [$0.id] + walk($0.items ?? []) }
        }
        return walk(items)
    }

    /// Rewrite file and folder paths after a rename or move. Prefix matches follow a
    /// folder that moved. Returns whether anything changed.
    @discardableResult
    public mutating func remapPaths(_ map: [String: String]) -> Bool {
        guard !map.isEmpty else { return false }
        var changed = false
        func rewrite(_ path: String) -> String {
            if let direct = map[path] { return direct }
            let keys = map.keys.sorted { $0.count > $1.count }
            for from in keys where path.hasPrefix(from + "/") {
                return map[from]! + String(path.dropFirst(from.count))
            }
            return path
        }
        func walk(_ items: inout [BookmarkItem]) {
            for i in items.indices {
                if let p = items[i].path {
                    let n = rewrite(p)
                    if n != p { items[i].path = n; changed = true }
                }
                if items[i].items != nil { walk(&items[i].items!) }
            }
        }
        walk(&items)
        return changed
    }

    /// Append UserDefaults-era path bookmarks that aren't already in the store.
    /// Returns whether anything was added.
    @discardableResult
    public static func migrate(paths: [String], into store: inout BookmarkStore, now: Int64) -> Bool {
        var added = false
        for p in paths where !p.isEmpty && !store.containsFile(path: p, subpath: nil) {
            store.items.append(BookmarkItem.file(path: p, subpath: nil, ctime: now))
            added = true
        }
        return added
    }

    // MARK: Tree walk

    public func item(id: UUID) -> BookmarkItem? { find({ $0.id == id }) }

    public func find(_ pred: (BookmarkItem) -> Bool) -> BookmarkItem? {
        func walk(_ items: [BookmarkItem]) -> BookmarkItem? {
            for it in items {
                if pred(it) { return it }
                if let kids = it.items, let hit = walk(kids) { return hit }
            }
            return nil
        }
        return walk(items)
    }

    @discardableResult
    mutating func removeAll(_ pred: (BookmarkItem) -> Bool) -> Bool {
        var removed = false
        func walk(_ items: inout [BookmarkItem]) {
            let before = items.count
            var i = 0
            while i < items.count {
                if pred(items[i]) {
                    items.remove(at: i)
                    removed = true
                    continue
                }
                if items[i].items != nil { walk(&items[i].items!) }
                i += 1
            }
            if items.count != before { removed = true }
        }
        walk(&items)
        return removed
    }

    mutating func remove(where pred: (BookmarkItem) -> Bool) -> BookmarkItem? {
        func walk(_ items: inout [BookmarkItem]) -> BookmarkItem? {
            if let i = items.firstIndex(where: pred) { return items.remove(at: i) }
            for i in items.indices where items[i].items != nil {
                if let hit = walk(&items[i].items!) { return hit }
            }
            return nil
        }
        return walk(&items)
    }

    @discardableResult
    mutating func update(id: UUID, _ body: (inout BookmarkItem) -> Bool) -> Bool {
        func walk(_ items: inout [BookmarkItem]) -> Bool {
            for i in items.indices {
                if items[i].id == id { return body(&items[i]) }
                if items[i].items != nil, walk(&items[i].items!) { return true }
            }
            return false
        }
        return walk(&items)
    }

    func isDescendant(_ candidate: UUID, of ancestor: UUID) -> Bool {
        guard let root = item(id: ancestor) else { return false }
        func walk(_ items: [BookmarkItem]?) -> Bool {
            guard let items else { return false }
            for it in items {
                if it.id == candidate { return true }
                if walk(it.items) { return true }
            }
            return false
        }
        return walk(root.items)
    }
}

public struct BookmarkItem: Identifiable {
    public var id: UUID
    public var type: String
    public var ctime: Int64?
    public var title: String?
    public var path: String?
    public var subpath: String?
    public var query: String?
    public var url: String?
    public var options: Any?
    public var items: [BookmarkItem]?
    public var extras: [String: Any]

    public init(
        id: UUID = UUID(),
        type: String,
        ctime: Int64? = nil,
        title: String? = nil,
        path: String? = nil,
        subpath: String? = nil,
        query: String? = nil,
        url: String? = nil,
        options: Any? = nil,
        items: [BookmarkItem]? = nil,
        extras: [String: Any] = [:]
    ) {
        self.id = id
        self.type = type
        self.ctime = ctime
        self.title = title
        self.path = path
        self.subpath = BookmarkSubpath.normalize(subpath)
        self.query = query
        self.url = url
        self.options = options
        self.items = items
        self.extras = extras
    }

    public static func file(path: String, subpath: String?, ctime: Int64, title: String? = nil) -> BookmarkItem {
        BookmarkItem(type: "file", ctime: ctime, title: title, path: path, subpath: subpath)
    }

    public static func folder(path: String, ctime: Int64, title: String? = nil) -> BookmarkItem {
        BookmarkItem(type: "folder", ctime: ctime, title: title, path: path)
    }

    public static func group(title: String, items: [BookmarkItem], ctime: Int64) -> BookmarkItem {
        BookmarkItem(type: "group", ctime: ctime, title: title, items: items)
    }

    static func parse(_ dict: [String: Any]) -> BookmarkItem {
        var extras = dict
        let type = (extras.removeValue(forKey: "type") as? String) ?? ""
        let ctime = BookmarkItem.int64(extras.removeValue(forKey: "ctime"))
        let title = extras.removeValue(forKey: "title") as? String
        let path = extras.removeValue(forKey: "path") as? String
        let subpath = extras.removeValue(forKey: "subpath") as? String
        let query = extras.removeValue(forKey: "query") as? String
        let url = extras.removeValue(forKey: "url") as? String
        let options = extras.removeValue(forKey: "options")
        var children: [BookmarkItem]? = nil
        if let raw = extras.removeValue(forKey: "items") as? [Any] {
            children = raw.compactMap { ($0 as? [String: Any]).map(parse) }
        }
        return BookmarkItem(
            type: type, ctime: ctime, title: title, path: path, subpath: subpath,
            query: query, url: url, options: options, items: children, extras: extras
        )
    }

    public var jsonObject: [String: Any] {
        var o: [String: Any] = extras
        o["type"] = type
        if let ctime { o["ctime"] = NSNumber(value: ctime) }
        if let path { o["path"] = path }
        if let subpath { o["subpath"] = subpath }
        if let title { o["title"] = title }
        if let query { o["query"] = query }
        if let url { o["url"] = url }
        if let options { o["options"] = options }
        if type == "group" || items != nil { o["items"] = (items ?? []).map { $0.jsonObject } }
        return o
    }

    public var isGroup: Bool { type == "group" }

    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        switch type {
        case "file":
            let name = Self.stem(path ?? "")
            if let heading = BookmarkSubpath.headingName(subpath) { return name + " › " + heading }
            if let block = BookmarkSubpath.blockID(subpath) { return name + " › ^" + block }
            return name
        case "folder":
            let p = path ?? ""
            return p.isEmpty ? "Vault" : (p as NSString).lastPathComponent
        case "search":
            return query ?? "Search"
        case "url":
            return url ?? "Link"
        case "graph":
            return "Graph"
        case "group":
            return "Group"
        default:
            return type.isEmpty ? "Bookmark" : type
        }
    }

    /// Folder path shown under a file bookmark, or the heading when that's the distinctive bit.
    public var displayDetail: String? {
        if type == "file" {
            if BookmarkSubpath.normalize(subpath) != nil {
                return path.map(Self.stem)
            }
            let folder = ((path ?? "") as NSString).deletingLastPathComponent
            return folder.isEmpty ? nil : folder
        }
        if type == "folder" { return path }
        if type == "search" { return query }
        if type == "url", title != nil { return url }
        return nil
    }

    func isFile(path: String, subpath: String?) -> Bool {
        type == "file" && self.path == path && BookmarkSubpath.normalize(self.subpath) == subpath
    }

    func isFolder(path: String) -> Bool { type == "folder" && self.path == path }

    func matchesPath(_ path: String) -> Bool {
        self.path == path && (type == "file" || type == "folder")
    }

    static func stem(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent as NSString
        return name.deletingPathExtension
    }

    static func int64(_ value: Any?) -> Int64? {
        switch value {
        case let n as Int64: return n
        case let n as Int: return Int64(n)
        case let n as NSNumber: return n.int64Value
        case let d as Double: return Int64(d)
        default: return nil
        }
    }
}

/// Obsidian stores a heading or block target on a file bookmark as `subpath`
/// (`#Heading` or `#^blockid`).
public enum BookmarkSubpath {
    public static func normalize(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty, s != "#" else { return nil }
        if !s.hasPrefix("#") { s = "#" + s }
        return s
    }

    public static func headingName(_ subpath: String?) -> String? {
        guard let s = normalize(subpath), !s.hasPrefix("#^") else { return nil }
        let name = String(s.dropFirst())
        return name.isEmpty ? nil : name
    }

    public static func blockID(_ subpath: String?) -> String? {
        guard let s = normalize(subpath), s.hasPrefix("#^") else { return nil }
        let id = String(s.dropFirst(2))
        return id.isEmpty ? nil : id
    }

    /// 0-based source line for a heading or `^blockid`, when it can be found.
    public static func line(subpath: String?, text: String, headings: [Heading]) -> Int? {
        if let name = headingName(subpath) {
            return headings.first(where: { $0.text.caseInsensitiveCompare(name) == .orderedSame })?.line
        }
        guard let id = blockID(subpath) else { return nil }
        let escaped = NSRegularExpression.escapedPattern(for: id)
        let pattern = "(?<![A-Za-z0-9])\\^" + escaped + "(?![A-Za-z0-9_\\-])"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var line = 0
        var i = 0
        let u = Array(text.utf16)
        let target = m.range.location
        while i < target && i < u.count {
            if u[i] == 10 { line += 1 }
            i += 1
        }
        return line
    }
}


/// Resolve a dropped file URL to a vault-relative path. The vault root itself
/// and anything outside the vault are rejected.
public enum VaultFileDrop {
    public static func relativePath(of url: URL, vaultRoot root: URL) -> String? {
        if let rel = relative(url.standardizedFileURL, root: root.standardizedFileURL) {
            return rel
        }
        return relative(
            url.standardizedFileURL.resolvingSymlinksInPath(),
            root: root.standardizedFileURL.resolvingSymlinksInPath()
        )
    }

    /// Vault-relative paths from an in-app path list and/or file URLs, skipping
    /// anything outside the vault and de-duplicating.
    public static func items(treePaths: String?, urls: [URL], vaultRoot root: URL?, isFolder: (String, URL?) -> Bool) -> [(path: String, isFolder: Bool)] {
        var result: [(path: String, isFolder: Bool)] = []
        var seen = Set<String>()
        func add(_ path: String, url: URL?) {
            guard !path.isEmpty, !seen.contains(path) else { return }
            seen.insert(path)
            result.append((path, isFolder(path, url)))
        }
        if let treePaths {
            for raw in treePaths.split(whereSeparator: \.isNewline) {
                add(String(raw), url: nil)
            }
        }
        if let root {
            for url in urls {
                if let rel = relativePath(of: url, vaultRoot: root) {
                    add(rel, url: url)
                }
            }
        }
        return result
    }

    private static func relative(_ url: URL, root: URL) -> String? {
        let urlParts = url.pathComponents
        let rootParts = root.pathComponents
        guard urlParts.count > rootParts.count else { return nil }
        let matched = zip(rootParts, urlParts).allSatisfy {
            $0.caseInsensitiveCompare($1) == .orderedSame
        }
        guard matched else { return nil }
        return urlParts.dropFirst(rootParts.count).joined(separator: "/")
    }
}


/// What a click on a Bookmarks row should do.
public enum BookmarkActivation: Equatable, Sendable {
    case toggleGroup
    case open
    /// ⌘-click a file or folder bookmark: open it in a new split pane.
    case openInNewPane

    public static func action(type: String, command: Bool) -> BookmarkActivation {
        if type == "group" { return .toggleGroup }
        if command, type == "file" || type == "folder" { return .openInNewPane }
        return .open
    }
}

/// Whether a Bookmarks overlay should claim the pointer. Leftover pasteboard
/// types after a finished drag must not steal clicks.
public enum BookmarkPointerHit {
    public static func claimsHit(
        isRow: Bool,
        isLeftMouseDown: Bool,
        isLeftMouseUp: Bool,
        isControlClick: Bool,
        mouseButtonHeld: Bool,
        eventIsDrag: Bool,
        pasteboardHasDrop: Bool
    ) -> Bool {
        let liveDrop = pasteboardHasDrop && (eventIsDrag || (mouseButtonHeld && !isLeftMouseDown && !isLeftMouseUp))
        if liveDrop { return true }
        if isRow && isLeftMouseDown && !isControlClick { return true }
        return false
    }
}

