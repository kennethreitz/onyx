import SwiftUI
import AppKit
import OnyxCore

/// Settings ▸ Files & Links and Settings ▸ Daily Notes: Obsidian's core settings, read from and written
/// to the vault's own `.obsidian/*.json`, so Obsidian and Onyx always agree. Only changed keys are
/// written; everything else in the file is kept as it is.
private func caption(_ s: String, warn: Bool = false) -> some View {
    Text(s).font(.system(size: 11)).foregroundStyle(warn ? Color.orange : Color.faint)
        .fixedSize(horizontal: false, vertical: true)
}

private extension Workspace {
    /// A config file's current contents; reading the revision makes views refresh when it changes.
    func config(_ file: String) -> [String: Any] {
        _ = obsidianConfigRevision
        return obsidianJSON(file) as? [String: Any] ?? [:]
    }
}

/// A text field that saves on Return or when it loses focus, not on every keystroke.
struct CommitField: View {
    let title: String
    let value: String
    var placeholder: String = ""
    let commit: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $draft, prompt: Text(placeholder))
            .focused($focused)
            .onAppear { draft = value }
            .onChange(of: value) { if !focused { draft = value } }
            .onChange(of: focused) { if !focused, draft != value { commit(draft) } }
            .onSubmit { if draft != value { commit(draft) } }
    }
}

/// A vault-relative folder (or note) with a picker that only accepts places inside the vault.
struct VaultPathField: View {
    @Bindable var ws: Workspace
    let title: String
    let value: String
    var placeholder: String = "Vault root"
    var pickFile = false
    var startIn: String = ""
    var emptyMeansRoot = true
    let commit: (String) -> Void

    var body: some View {
        HStack {
            CommitField(title: title, value: value, placeholder: placeholder) { commit(vaultFolder($0)) }
            Button("Choose…") { choose() }.disabled(ws.root == nil)
        }
        if let note { caption(note.0, warn: note.1) }
    }

    private var note: (String, Bool)? {
        switch VaultPathCheck.check(value) {
        case .empty: return nil
        case .outsideVault: return ("This has to be a path inside the vault.", true)
        case .invalidCharacters: return ("Obsidian doesn’t allow * \" \\ < > : | ? in names.", true)
        case .ok:
            guard let root = ws.root else { return nil }
            var p = vaultFolder(value)
            if pickFile, !p.lowercased().hasSuffix(".md") { p += ".md" }
            var dir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: root.appendingPathComponent(p).path, isDirectory: &dir)
            if pickFile { return exists ? nil : ("No note at \(p) yet; Onyx uses its built-in daily note until there is.", true) }
            return exists && dir.boolValue ? nil : ("This folder doesn’t exist yet; it’s created when first needed.", false)
        }
    }

    private func choose() {
        guard let root = ws.root?.standardizedFileURL.resolvingSymlinksInPath() else { return }
        let p = NSOpenPanel()
        p.canChooseDirectories = !pickFile; p.canChooseFiles = pickFile; p.canCreateDirectories = !pickFile
        if pickFile { p.allowedContentTypes = [.init(filenameExtension: "md")!] }
        p.directoryURL = startIn.isEmpty ? root : root.appendingPathComponent(startIn)
        p.prompt = "Choose"
        p.message = "Choose a \(pickFile ? "note" : "folder") inside \(root.lastPathComponent)."
        guard p.runModal() == .OK, let u = p.url?.standardizedFileURL.resolvingSymlinksInPath() else { return }
        if u.path == root.path { commit(""); return }
        guard u.path.hasPrefix(root.path + "/") else {
            let a = NSAlert(); a.messageText = "That’s outside the vault"; a.informativeText = "Pick a \(pickFile ? "note" : "folder") inside \(root.lastPathComponent)."; a.runModal()
            return
        }
        var rel = String(u.path.dropFirst(root.path.count + 1))
        if pickFile, rel.lowercased().hasSuffix(".md") { rel = String(rel.dropLast(3)) }   // Obsidian stores templates without .md
        commit(rel)
    }
}

private struct NoVault: View {
    var body: some View { caption("Open a vault to edit its Obsidian settings.") }
}

struct FilesSettingsPage: View {
    @Bindable var ws: Workspace
    @State private var subfolderDraft = "attachments"
    @State private var ignoreDraft = ""

    var body: some View {
        Form {
            if ws.root == nil { Section { NoVault() } } else { content }
        }
        .formStyle(.grouped)
        .frame(width: SettingsPage.width)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func set(_ k: String, _ v: Any?) { ws.setObsidianConfig("app.json", [k: v]) }

    @ViewBuilder private var content: some View {
        let app = ws.config("app.json")
        Section {
            Picker("Default location for new notes", selection: Binding(
                get: { app["newFileLocation"] as? String ?? "" },
                set: { set("newFileLocation", $0.isEmpty ? nil : $0) })) {
                Text("Onyx default (selected or current folder)").tag("")
                Text("Vault folder").tag("root")
                Text("Same folder as current file").tag("current")
                Text("In the folder specified below").tag("folder")
            }
            if app["newFileLocation"] as? String == "folder" {
                VaultPathField(ws: ws, title: "Folder to create new notes in", value: app["newFileFolderPath"] as? String ?? "") {
                    set("newFileFolderPath", $0)
                }
            }
            caption("For ⌘N, the quick switcher’s create, and clicking a link to a note that doesn’t exist. New Note Here in the sidebar always uses that folder.")

            Picker("New link format", selection: Binding(
                get: { Attachments.Settings(appJSON: app).linkFormat },
                set: { set("newLinkFormat", $0) })) {
                Text("Shortest path when possible").tag("shortest")
                Text("Relative path to file").tag("relative")
                Text("Absolute path in vault").tag("absolute")
            }
            Toggle("Use [[Wikilinks]]", isOn: Binding(
                get: { !(app["useMarkdownLinks"] as? Bool ?? false) },
                set: { set("useMarkdownLinks", !$0) }))
            caption("Off writes Markdown links, like ![](photo.png), for dropped and pasted files.")
            Toggle("Automatically update internal links", isOn: Binding(
                get: { app["alwaysUpdateLinks"] as? Bool ?? false },
                set: { set("alwaysUpdateLinks", $0) }))
            caption("When you rename or move a note, attachment, or folder. Off asks first, the way Obsidian does.")
        } header: { settingsHeader("Files and links") }

        Section {
            let loc = AttachmentLocation(setting: app["attachmentFolderPath"] as? String)
            Picker("Default location for new attachments", selection: Binding(
                get: { loc.kind },
                set: { k in
                    switch k {
                    case "root": set("attachmentFolderPath", AttachmentLocation.vaultRoot.setting)
                    case "current": set("attachmentFolderPath", AttachmentLocation.sameFolder.setting)
                    case "subfolder": set("attachmentFolderPath", AttachmentLocation.subfolder(subfolderDraft.isEmpty ? "attachments" : subfolderDraft).setting)
                    default: set("attachmentFolderPath", AttachmentLocation.folder("Attachments").setting)
                    }
                })) {
                Text("Vault folder").tag("root")
                Text("Same folder as current file").tag("current")
                Text("In subfolder under current folder").tag("subfolder")
                Text("In the folder specified below").tag("folder")
            }
            switch loc {
            case .subfolder(let name):
                CommitField(title: "Subfolder name", value: name, placeholder: "attachments") { v in
                    let n = vaultFolder(v)
                    subfolderDraft = n
                    set("attachmentFolderPath", AttachmentLocation.subfolder(n).setting)
                }
                caption("Files go in this folder next to each note: Notes/Trip.md → Notes/\(name.isEmpty ? "attachments" : name)/.")
            case .folder(let f):
                VaultPathField(ws: ws, title: "Attachment folder path", value: f) {
                    set("attachmentFolderPath", AttachmentLocation.folder($0).setting)
                }
            default: EmptyView()
            }
            caption("Where dropped, pasted, and recorded files go.")
        } header: { settingsHeader("Attachments") }

        Section {
            Picker("Default view for new tabs", selection: Binding(
                get: { (app["defaultViewMode"] as? String) == "source" ? "source" : "preview" },
                set: { set("defaultViewMode", $0) })) {
                Text("Reading view").tag("preview")
                Text("Editing view").tag("source")
            }
            caption("Onyx opens a vault in this mode.")
            VStack(alignment: .leading, spacing: 4) {
                Text("Excluded files")
                TextField("", text: $ignoreDraft, prompt: Text("One folder or path per line, like Archive/"), axis: .vertical)
                    .lineLimit(2...6)
                    .font(.system(size: 12, design: .monospaced))
                HStack {
                    caption("Hidden from search, the graph, and the sidebar. Applying re-indexes the vault.")
                    Spacer()
                    Button("Apply") {
                        let list = ignoreDraft.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        set("userIgnoreFilters", list)
                    }.disabled(ignoreLines(app) == ignoreDraft)
                }
            }
            .onAppear { ignoreDraft = ignoreLines(app) }
            .onChange(of: ws.obsidianConfigRevision) { ignoreDraft = ignoreLines(ws.config("app.json")) }
        } header: { settingsHeader("Vault") }

        ClipperSettingsSection(ws: ws)

        Section { caption("Saved to \(ws.root?.lastPathComponent ?? "")/.obsidian/app.json, the same file Obsidian uses. Changes made in Obsidian, or arriving through Sync, show up here.") }
    }

    private func ignoreLines(_ app: [String: Any]) -> String { (app["userIgnoreFilters"] as? [String] ?? []).joined(separator: "\n") }
}

struct DailySettingsPage: View {
    @Bindable var ws: Workspace

    var body: some View {
        Form {
            if ws.root == nil { Section { NoVault() } } else { content }
        }
        .formStyle(.grouped)
        .frame(width: SettingsPage.width)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func preview(_ format: String) -> some View {
        let parsable = MomentFormat.icuPattern(format) != nil
        return VStack(alignment: .leading, spacing: 2) {
            caption("Looks like: \(MomentFormat.format(Date(), format))")
            if !parsable { caption("Onyx can’t read dates back out of this format, so Previous and Next Daily Note won’t find these notes.", warn: true) }
        }
    }

    @ViewBuilder private var content: some View {
        let dn = ws.config("daily-notes.json")
        let daily = ws.daily
        let tpl = TemplateSettings(json: ws.config("templates.json"))
        Section {
            CommitField(title: "Date format", value: dn["format"] as? String ?? "", placeholder: DailyNotes.defaultFormat) {
                ws.setObsidianConfig("daily-notes.json", ["format": $0.trimmingCharacters(in: .whitespaces)])
            }
            preview(daily.format)
            caption("A moment.js format, as in Obsidian. A / makes folders: YYYY/MM/YYYY-MM-DD.")
            VaultPathField(ws: ws, title: "New file location", value: dn["folder"] as? String ?? "",
                           placeholder: dn["folder"] == nil ? "Daily (Onyx default)" : "Vault root") {
                ws.setObsidianConfig("daily-notes.json", ["folder": $0])
            }
            VaultPathField(ws: ws, title: "Template file location", value: dn["template"] as? String ?? "",
                           placeholder: "Onyx’s built-in daily note", pickFile: true, startIn: tpl.folder) {
                ws.setObsidianConfig("daily-notes.json", ["template": $0])
            }
            caption("In the template, {{date}} and {{title}} become the note’s date, {{time}} the time now, and {{date:dddd D MMMM}} any format you like.")
            Toggle("Open daily note on startup", isOn: Binding(
                get: { daily.autorun },
                set: { ws.setObsidianConfig("daily-notes.json", ["autorun": $0]) }))
        } header: { settingsHeader("Daily notes") }

        Section {
            VaultPathField(ws: ws, title: "Template folder location", value: tpl.folder) {
                ws.setObsidianConfig("templates.json", ["folder": $0])
            }
            caption("Where Choose… starts when you pick a daily-note template.")
            CommitField(title: "Date format", value: ws.config("templates.json")["dateFormat"] as? String ?? "", placeholder: TemplateSettings.defaultDateFormat) {
                ws.setObsidianConfig("templates.json", ["dateFormat": $0.trimmingCharacters(in: .whitespaces)])
            }
            caption("Insert Current Date: \(MomentFormat.format(Date(), tpl.dateFormat))")
            CommitField(title: "Time format", value: ws.config("templates.json")["timeFormat"] as? String ?? "", placeholder: TemplateSettings.defaultTimeFormat) {
                ws.setObsidianConfig("templates.json", ["timeFormat": $0.trimmingCharacters(in: .whitespaces)])
            }
            caption("Insert Current Time and {{time}}: \(MomentFormat.format(Date(), tpl.timeFormat))")
        } header: { settingsHeader("Templates") }

        Section { caption("Saved to .obsidian/daily-notes.json and templates.json, the same files Obsidian uses.") }
    }
}

/// Settings ▸ Files & Links ▸ Web Clipper. Stored in Onyx's preferences, not the vault.
struct ClipperSettingsSection: View {
    @Bindable var ws: Workspace
    @AppStorage(WebClip.Settings.folderKey) private var folder = WebClip.Settings.defaultFolder
    @AppStorage(WebClip.Settings.classKey) private var noteClass = ""
    @AppStorage(WebClip.Settings.tagsKey) private var tags = ""
    @AppStorage(WebClip.Settings.imagesKey) private var images = true
    @AppStorage(WebClip.Settings.templateKey) private var template = ""
    @State private var copied = false

    var body: some View {
        Section {
            VaultPathField(ws: ws, title: "Clippings folder", value: folder) { folder = $0 }
            CommitField(title: "Class", value: noteClass, placeholder: "Match the folder (else Source)") { noteClass = $0.trimmingCharacters(in: .whitespaces) }
            CommitField(title: "Tags", value: tags, placeholder: "Match the folder (else clippings)") { tags = $0.trimmingCharacters(in: .whitespaces) }
            Toggle("Download images into the attachment folder", isOn: $images)
            CommitField(title: "Template note", value: template, placeholder: "Built-in (Obsidian Web Clipper style)") { template = $0.trimmingCharacters(in: .whitespaces) }
            caption("A template can use {{title}}, {{url}}, {{author}}, {{published}}, {{date}}, {{time}}, {{description}}, {{site}}, {{tags}}, {{class}} and {{content}}.")
            HStack {
                Button(copied ? "Copied" : "Copy Bookmarklet") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(WebClip.bookmarklet, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }
                Spacer()
            }
            caption("Make a bookmark in Safari, Chrome or Firefox and paste this as its address. Clicking it clips the page, or just the selection when text is selected. File ▸ Clip Web Page… (⇧⌘K) clips a URL from inside Onyx.")
        } header: { settingsHeader("Web Clipper") }
    }
}
