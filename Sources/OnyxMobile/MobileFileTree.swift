import Foundation
import OnyxCore

/// Prompts the Files tab presents for new items, rename, delete, and link updates.
enum FileTreePrompt: Identifiable, Equatable {
    case newNote(folder: String)
    case newFolder(folder: String)
    case rename(path: String)
    case delete(path: String)
    case updateLinks(from: String, dest: String, reason: String, linkCount: Int, fileCount: Int)

    var id: String {
        switch self {
        case .newNote(let f): "newNote:\(f)"
        case .newFolder(let f): "newFolder:\(f)"
        case .rename(let p): "rename:\(p)"
        case .delete(let p): "delete:\(p)"
        case .updateLinks(let from, let dest, _, _, _): "links:\(from)>\(dest)"
        }
    }
}

extension MobileVault {
    /// Expanded folder paths in the Files tree, remembered per vault.
    func loadTreeExpanded() {
        persistTreeExpanded = false
        treeExpanded = Set(UserDefaults.standard.stringArray(forKey: treeExpandedKey) ?? [])
        persistTreeExpanded = true
    }

    func saveTreeExpanded() {
        guard persistTreeExpanded, root != nil else { return }
        UserDefaults.standard.set(treeExpanded.sorted(), forKey: treeExpandedKey)
    }

    var treeExpandedKey: String {
        if let id = managed?.id { return "onyx.ios.treeExpanded.managed.\(id)" }
        return "onyx.ios.treeExpanded.\(root?.path ?? "")"
    }

    func treeChildren(_ node: FileNode) -> [FileNode] {
        let kids = node.children ?? []
        let s = treeOrder.sort(for: node.path)
        if s == .standard { return kids }
        guard let snap = snapshot else { return kids }
        if treeDatesCache?.gen != snapshotGeneration { treeDatesCache = (snapshotGeneration, TreeDates(snap)) }
        return treeDatesCache!.dates.ordered(kids, by: s)
    }

    func visibleTreeRows() -> [FileTreeRow] {
        guard let tree = snapshot?.tree else { return [] }
        return tree.visibleRows(expanded: treeExpanded, children: treeChildren)
    }

    func toggleFolder(_ path: String) {
        if treeExpanded.contains(path) { treeExpanded.remove(path) } else { treeExpanded.insert(path) }
    }

    /// Expand every ancestor of `path`, and the path itself when it is a folder.
    func revealInTree(_ path: String, includingSelf: Bool = false) {
        for parent in TreeReveal.ancestors(of: path) { treeExpanded.insert(parent) }
        if includingSelf, snapshot?.folders.contains(path) == true { treeExpanded.insert(path) }
        treeRevealToken += 1
    }

    /// Folder a New Note / New Folder command should use: an explicit path, else
    /// the open note's folder, else the vault root.
    func folderForNewItem(explicit: String? = nil) -> String {
        if let e = explicit { return e }
        return selectedPath.map { ($0 as NSString).deletingLastPathComponent } ?? ""
    }

    func beginNewNote(in explicit: String? = nil) {
        let folder = folderForNewItem(explicit: explicit)
        fileTreeDraft = "Untitled"
        fileTreePrompt = .newNote(folder: folder)
    }

    func beginNewFolder(in explicit: String? = nil) {
        let folder = folderForNewItem(explicit: explicit)
        let taken = takenNames(in: folder)
        fileTreeDraft = FolderCreate.uniqueName(existing: taken)
        fileTreePrompt = .newFolder(folder: folder)
    }

    func beginRename(_ path: String) {
        fileTreeDraft = InlineRename.fieldValue(path: path)
        fileTreePrompt = .rename(path: path)
        revealInTree(path)
    }

    func beginDelete(_ path: String) {
        fileTreePrompt = .delete(path: path)
    }

    @discardableResult
    func createNote(named rawName: String, folder: String) -> String? {
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "Untitled" }
        name = name.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-")
        var path = folder.isEmpty ? name : folder + "/" + name
        if !path.lowercased().hasSuffix(".md") { path += ".md" }
        let base = String(path.dropLast(3))
        var n = 1
        while pathOccupied(path) {
            n += 1
            path = "\(base) \(n).md"
        }
        let title = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        guard writeNote("# \(title)\n\n", to: path, create: true) else { return nil }
        revealInTree(path)
        openNote(path)
        return path
    }

    @discardableResult
    func createFolder(named rawName: String, in folder: String) -> String? {
        guard canWrite, root != nil else { return nil }
        let taken = takenNames(in: folder)
        let name = FolderCreate.uniqueName(base: rawName, existing: taken)
        let rel = FolderCreate.path(name: name, in: folder)
        guard let url = vaultURL(for: rel) else { return nil }
        var ok = false
        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordError) { url in
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                ok = true
            } catch {
                self.error = "Couldn’t create folder: \(error.localizedDescription)"
            }
        }
        if let coordError { error = coordError.localizedDescription; return nil }
        guard ok else { return nil }
        refreshSnapshot(paths: [rel])
        syncEdited()
        revealInTree(rel, includingSelf: true)
        return rel
    }

    func commitRename() {
        guard case .rename(let path) = fileTreePrompt else { return }
        let taken = { (dest: String) in self.pathOccupied(dest) }
        switch InlineRename.evaluate(path: path, typed: fileTreeDraft, occupied: taken) {
        case .cancel:
            fileTreePrompt = nil
        case .invalid(let message), .collision(let message):
            error = message
        case .commit(let dest, let from, let to):
            fileTreePrompt = nil
            proposeRelocate(path, to: dest, reason: "Rename \(from) → \(to)")
        }
    }

    func confirmDelete() {
        guard case .delete(let path) = fileTreePrompt else { return }
        fileTreePrompt = nil
        deleteItem(path)
    }

    /// If the rename/move would change links, ask first (unless app.json says always update).
    func proposeRelocate(_ from: String, to dest: String, reason: String) {
        guard let snap = snapshot, let root else { return }
        let format = Attachments.Settings(appJSON: appJSON()).linkFormat
        let plan = LinkUpdater.plan(snap, from: from, to: dest, linkFormat: format) { c in
            try? String(contentsOf: root.appendingPathComponent(c), encoding: .utf8)
        }
        let always = (appJSON()?["alwaysUpdateLinks"] as? Bool) == true
        if plan.isEmpty || always {
            _ = relocate(from, to: dest, reason: reason, updateLinks: true)
        } else {
            pendingRelocate = (from, dest, reason)
            fileTreePrompt = .updateLinks(from: from, dest: dest, reason: reason,
                                          linkCount: plan.linkCount, fileCount: plan.edits.count)
        }
    }

    func finishRelocate(updateLinks: Bool) {
        guard let pending = pendingRelocate else { return }
        pendingRelocate = nil
        fileTreePrompt = nil
        _ = relocate(pending.from, to: pending.dest, reason: pending.reason, updateLinks: updateLinks)
    }

    @discardableResult
    func relocate(_ from: String, to dest: String, reason: String, updateLinks: Bool) -> Bool {
        guard let root, var snap = snapshot else { return false }
        let fm = FileManager.default
        guard let src = vaultURL(for: from), let dst = vaultURL(for: dest) else { return false }
        if fm.fileExists(atPath: dst.path), from.lowercased() != dest.lowercased() {
            error = "“\((dest as NSString).lastPathComponent)” already exists there"
            return false
        }
        let format = Attachments.Settings(appJSON: appJSON()).linkFormat
        let plan = LinkUpdater.plan(snap, from: from, to: dest, linkFormat: format) { c in
            try? String(contentsOf: root.appendingPathComponent(c), encoding: .utf8)
        }
        var edited: [String] = []
        if updateLinks {
            for e in plan.edits {
                guard writeNote(e.text, to: e.path) else { continue }
                snap.update(path: e.path, content: e.text)
                edited.append(e.path)
            }
        }
        var moved = false
        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: src, options: .forMoving, error: &coordError) { src in
            do {
                try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                if from.lowercased() == dest.lowercased() {
                    let tmp = src.deletingLastPathComponent().appendingPathComponent(".onyx-rename-\(UUID().uuidString)")
                    try fm.moveItem(at: src, to: tmp)
                    try fm.moveItem(at: tmp, to: dst)
                } else {
                    try fm.moveItem(at: src, to: dst)
                }
                moved = true
            } catch {
                self.error = "Couldn’t rename: \(error.localizedDescription)"
            }
        }
        if let coordError { error = coordError.localizedDescription; return false }
        guard moved else { return false }

        snap.refresh(paths: Array(plan.fileMoves.keys) + Array(plan.fileMoves.values) + [from, dest] + edited)
        snapshot = snap

        func remap(_ p: String) -> String { plan.fileMoves[p] ?? p }
        if let cur = selectedPath { selectedPath = remap(cur) }
        treeExpanded = Set(treeExpanded.map { p in
            if p == from || p.hasPrefix(from + "/") { return dest + String(p.dropFirst(from.count)) }
            return p
        })
        if bookmarkStore.remapPaths(plan.fileMoves) { persistBookmarks() }
        revealInTree(dest, includingSelf: snapshot?.folders.contains(dest) == true)
        syncEdited()
        if !updateLinks, !plan.isEmpty {
            error = "\(reason) · links not updated"
        }
        return true
    }

    func deleteItem(_ path: String) {
        guard canWrite, let url = vaultURL(for: path) else { return }
        let gone: (String) -> Bool = { p in p == path || p.hasPrefix(path + "/") }
        let affected = Array(Set((snapshot?.notes.keys.filter(gone) ?? []) + [path])).sorted()
        var ok = false
        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordError) { url in
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                ok = true
            } catch {
                do {
                    try FileManager.default.removeItem(at: url)
                    ok = true
                } catch {
                    self.error = "Couldn’t delete: \(error.localizedDescription)"
                }
            }
        }
        if let coordError { error = coordError.localizedDescription; return }
        guard ok else { return }
        refreshSnapshot(paths: affected)
        if let cur = selectedPath, gone(cur) { selectedPath = nil }
        treeExpanded = treeExpanded.filter { !gone($0) }
        pruneBookmarks(gone: gone)
        syncEdited()
    }

    func pruneBookmarks(gone: (String) -> Bool) {
        guard canWrite, !bookmarksLocked else { return }
        var ids: [UUID] = []
        func walk(_ items: [BookmarkItem]) {
            for it in items {
                if let p = it.path, gone(p) { ids.append(it.id) }
                if let kids = it.items { walk(kids) }
            }
        }
        walk(bookmarkStore.items)
        guard !ids.isEmpty else { return }
        for id in ids { _ = bookmarkStore.remove(id: id) }
        persistBookmarks()
    }

    func deleteConfirmationTitle(_ path: String) -> String {
        let last = (path as NSString).lastPathComponent
        let name = last.lowercased().hasSuffix(".md") ? String(last.dropLast(3)) : last
        let isFolder = snapshot?.folders.contains(path) == true
        return isFolder ? "Delete “\(name)” and its contents?" : "Delete “\(name)”?"
    }

    func deleteConfirmationMessage(_ path: String) -> String {
        if snapshot?.folders.contains(path) == true {
            let n = snapshot?.notes.keys.filter { $0.hasPrefix(path + "/") }.count ?? 0
            return "The folder and the \(n) note\(n == 1 ? "" : "s") in it will be removed from this vault."
        }
        return "This note will be removed from this vault."
    }

    func pathOccupied(_ dest: String) -> Bool {
        if let url = vaultURL(for: dest) { return FileManager.default.fileExists(atPath: url.path) }
        return snapshot?.notes[dest] != nil
            || snapshot?.folders.contains(dest) == true
            || snapshot?.attachments[dest] != nil
    }

    func takenNames(in folder: String) -> Set<String> {
        var taken = Set((snapshot?.folders ?? []).filter { ($0 as NSString).deletingLastPathComponent == folder }.map { ($0 as NSString).lastPathComponent })
        if let kids = (folder.isEmpty ? root : root?.appendingPathComponent(folder)).flatMap({ try? FileManager.default.contentsOfDirectory(atPath: $0.path) }) {
            taken.formUnion(kids)
        }
        return taken
    }

    func appJSON() -> [String: Any]? {
        guard let root else { return nil }
        let url = root.appendingPathComponent(".obsidian/app.json")
        return (try? Data(contentsOf: url)).flatMap { ObsidianConfig.parse($0) }
    }

    func refreshSnapshot(paths: [String]) {
        guard var snap = snapshot else { return }
        snap.refresh(paths: paths)
        snapshot = snap
    }

    func handleFolderTap(_ node: FileNode) {
        let a = FolderTreeClick.action(.row, hasFolderNote: node.folderNote != nil)
        if a.toggleExpansion { toggleFolder(node.path) }
        if a.openFolderNote, let fn = node.folderNote { openNote(fn, revealInTree: false) }
    }

    func handleFileTap(_ node: FileNode) {
        if node.isNote {
            openNote(node.path)
        } else {
            error = "“\(node.displayName)” can’t be opened on iPhone yet."
        }
    }
}
