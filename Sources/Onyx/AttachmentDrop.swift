import AppKit
import UniformTypeIdentifiers
import OnyxCore

/// Drag-and-drop and paste of files into the editor, as Obsidian does it: outside files are copied
/// into the attachment folder (`.obsidian/app.json`), vault files are linked where they are, and the
/// link lands at the drop point or the caret.
enum DroppedItem {
    case vaultPath(String)               // already in the vault (sidebar drag, or a Finder file inside the vault)
    case file(URL)                       // copy in under its own name
    case data(Data, ext: String)         // raw image bytes: "Pasted image …"
}

enum AttachmentPasteboard {
    static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .init(UTType.jpeg.identifier), .init(UTType.gif.identifier), .tiff]

    /// What a pasteboard holds that we'd turn into attachments; empty → let the text view handle it.
    /// `paste` is stricter about images so copied rich text with a picture still pastes as text.
    static func items(_ pb: NSPasteboard, root: URL, paste: Bool, images: Bool = true) -> [DroppedItem] {
        if let s = pb.string(forType: .onyxTreePaths) {
            return s.split(separator: "\n").map { .vaultPath(String($0)) }
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let base = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
            return urls.compactMap { u in
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), !isDir.boolValue else { return nil }
                let p = u.resolvingSymlinksInPath().standardizedFileURL.path
                return p.hasPrefix(base) ? .vaultPath(String(p.dropFirst(base.count))) : .file(u)
            }
        }
        if images, let image = imageData(pb, paste: paste) { return [image] }
        return []
    }

    static func imageData(_ pb: NSPasteboard, paste: Bool) -> DroppedItem? {
        guard let t = pb.availableType(from: imageTypes) else { return nil }
        if paste {
            if pb.availableType(from: [.rtf, .rtfd]) != nil { return nil }
            if let s = pb.string(forType: .string), s.contains("\n") { return nil }
        }
        guard let d = pb.data(forType: t) else { return nil }
        switch t {
        case .png: return .data(d, ext: "png")
        case .tiff:
            guard let rep = NSBitmapImageRep(data: d), let png = rep.representation(using: .png, properties: [:]) else { return nil }
            return .data(png, ext: "png")
        default: return .data(d, ext: t.rawValue == UTType.gif.identifier ? "gif" : "jpg")
        }
    }

    /// Promised files (browser image drags, Photos, Mail) worth receiving: media and documents, not web links.
    static func promises(_ pb: NSPasteboard) -> [NSFilePromiseReceiver] {
        let rs = (pb.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver]) ?? []
        return rs.filter { r in
            r.fileTypes.contains { id in
                guard let t = UTType(id) else { return false }
                return t.conforms(to: .image) || t.conforms(to: .audiovisualContent) || t.conforms(to: .pdf)
            }
        }
    }
}

extension Workspace {
    var attachmentSettings: Attachments.Settings {
        Attachments.Settings(appJSON: obsidianJSON("app.json") as? [String: Any])
    }

    /// Bring `items` into the vault for `note` and return their links (nil when nothing could be added).
    func attachmentLinks(_ items: [DroppedItem], note: String?) -> [String]? {
        guard let root, !items.isEmpty else { return nil }
        let settings = attachmentSettings
        let fm = FileManager.default
        var links: [String] = []
        var added: [String] = []
        for item in items {
            let name: String
            switch item {
            case .vaultPath(let p): links.append(p); continue
            case .file(let url): name = url.lastPathComponent
            case .data(_, let ext): name = Attachments.pastedImageName(date: Date(), ext: ext)
            }
            let rel = Attachments.destination(name: name, note: note, settings: settings) {
                fm.fileExists(atPath: root.appendingPathComponent($0).path)
            }
            let dest = root.appendingPathComponent(rel).standardizedFileURL
            guard dest.path.hasPrefix(root.standardizedFileURL.path + "/"), !rel.split(separator: "/").contains("..") else {
                toast = "The attachment folder is outside the vault"; return nil
            }
            do {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                switch item {
                case .file(let url): try fm.copyItem(at: url, to: dest)
                case .data(let d, _): try d.write(to: dest, options: .withoutOverwriting)
                case .vaultPath: break
                }
            } catch {
                toast = "Couldn't add “\(name)”: \(error.localizedDescription)"
                continue
            }
            added.append(rel)
            links.append(rel)
        }
        for rel in added { fileAdded(rel) }
        if added.count == 1 { toast = "Added “\((added[0] as NSString).lastPathComponent)”" }
        else if added.count > 1 { toast = "Added \(added.count) attachments" }
        let snap = snapshot
        return links.isEmpty ? nil : links.map { rel in
            Attachments.link(to: rel, from: note, settings: settings) { p in Self.nameIsUnique(p, in: snap) }
        }
    }

    /// Does the file's name alone resolve to it ("shortest path when possible")?
    static func nameIsUnique(_ path: String, in snap: VaultSnapshot?) -> Bool {
        guard let snap else { return true }
        let isNote = path.lowercased().hasSuffix(".md")
        let name = (path as NSString).lastPathComponent
        let key = isNote ? (name as NSString).deletingPathExtension.lowercased() : name.lowercased()
        var n = 0
        for p in snap.notes.keys where ((p as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased() == key { n += 1 }
        if !isNote { n = 0; for p in snap.attachments.keys where (p as NSString).lastPathComponent.lowercased() == key { n += 1 } }
        return n <= 1
    }
}

extension OnyxTextView {
    /// Insert link text at `offset` (UTF-16) as one undoable edit, caret after it.
    func insertLinks(_ links: [String], at offset: Int) {
        let at = max(0, min(offset, (string as NSString).length))
        let ins = Attachments.insertion(links)
        let r = NSRange(location: at, length: 0)
        guard shouldChangeText(in: r, replacementString: ins) else { return }
        replaceCharacters(in: r, with: ins)
        didChangeText()
        setSelectedRange(NSRange(location: at + (ins as NSString).length, length: 0))
        window?.makeFirstResponder(self)
    }
}

extension OnyxTextView {
    /// The drag types the editor takes on top of NSTextView's own (text, file URLs, images).
    static var attachmentDragTypes: [NSPasteboard.PasteboardType] {
        [.onyxTreePaths] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    }

    /// Whether a drag is ours to handle (files, vault paths, promised media, images), not plain text.
    func isAttachmentDrag(_ sender: NSDraggingInfo) -> Bool {
        guard isEditable, onAttach != nil, let root = vaultRoot() else { return false }
        let pb = sender.draggingPasteboard
        return !AttachmentPasteboard.items(pb, root: root, paste: false, images: false).isEmpty
            || !AttachmentPasteboard.promises(pb).isEmpty
            || (pb.availableType(from: [.string]) == nil && AttachmentPasteboard.imageData(pb, paste: false) != nil)
    }

    func attachmentDragOperation(_ sender: NSDraggingInfo) -> NSDragOperation {
        let mask = sender.draggingSourceOperationMask
        for op: NSDragOperation in [.copy, .link, .generic, .move] where mask.contains(op) { return op }
        return []
    }

    /// Handle a drop; false → not ours, let NSTextView insert text.
    func performAttachmentDrop(_ sender: NSDraggingInfo) -> Bool {
        guard isEditable, let onAttach, let root = vaultRoot() else { return false }
        let pb = sender.draggingPasteboard
        let at = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
        let files = AttachmentPasteboard.items(pb, root: root, paste: false, images: false)
        if !files.isEmpty {
            guard let links = onAttach(files) else { return true }
            insertLinks(links, at: at); return true
        }
        let promises = AttachmentPasteboard.promises(pb)
        if !promises.isEmpty {
            receive(promises, at: at); return true
        }
        if pb.availableType(from: [.string]) == nil, let image = AttachmentPasteboard.imageData(pb, paste: false) {
            if let links = onAttach([image]) { insertLinks(links, at: at) }
            return true
        }
        return false
    }

    /// Promised files arrive one by one in a temp folder; each is copied in and linked after the last.
    private func receive(_ promises: [NSFilePromiseReceiver], at offset: Int) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("onyx-drops/" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var next = offset, count = 0
        for r in promises {
            r.receivePromisedFiles(atDestination: dir, options: [:], operationQueue: .main) { [weak self] url, error in
                MainActor.assumeIsolated {
                    guard let self, error == nil, let links = self.onAttach?([.file(url)]) else { return }
                    let ins = (count > 0 ? "\n" : "") + Attachments.insertion(links)
                    let r = NSRange(location: min(next, (self.string as NSString).length), length: 0)
                    guard self.shouldChangeText(in: r, replacementString: ins) else { return }
                    self.replaceCharacters(in: r, with: ins)
                    self.didChangeText()
                    next = r.location + (ins as NSString).length
                    count += 1
                    self.setSelectedRange(NSRange(location: next, length: 0))
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    /// ⌘V with files or an image on the clipboard; false → paste as text.
    func pasteAttachments() -> Bool {
        guard isEditable, let onAttach, let root = vaultRoot() else { return false }
        let items = AttachmentPasteboard.items(.general, root: root, paste: true)
        guard !items.isEmpty else { return false }
        if let links = onAttach(items) {
            let sel = selectedRange()
            let ins = Attachments.insertion(links)
            guard shouldChangeText(in: sel, replacementString: ins) else { return true }
            replaceCharacters(in: sel, with: ins)
            didChangeText()
            setSelectedRange(NSRange(location: sel.location + (ins as NSString).length, length: 0))
        }
        return true
    }
}
