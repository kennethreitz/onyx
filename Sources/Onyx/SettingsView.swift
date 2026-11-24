import SwiftUI
import AppKit
import AVFoundation
import OnyxCore

enum Prefs {
    static let appearance = "onyx.appearance"     // "system" | "light" | "dark"
    static let readerSize = "onyx.readerSize"     // px, reading view body
    static let editorSize = "onyx.editorSize"     // pt, source editor
    static let measure = "onyx.measure"           // rem, the reading measure (editor follows)
    static let startFocus = "onyx.startFocus"
    static let sidenotes = "onyx.sidenotes"
    static let escToReading = "onyx.escToReading"  // Esc in the editor returns to reading; default on

    static var editorPoints: CGFloat { CGFloat(UserDefaults.standard.object(forKey: editorSize) as? Double ?? 14) }
    static var escReturnsToReading: Bool { UserDefaults.standard.object(forKey: escToReading) as? Bool ?? true }
    static var measureRem: CGFloat { CGFloat(UserDefaults.standard.object(forKey: measure) as? Double ?? 41) }
    /// The editor's 760px measure corresponds to the reader's 41rem; keep them in proportion.
    static var editorMeasure: CGFloat { (measureRem / 41 * 760).rounded() }
}

/// Typeset reading (Settings ▸ Reading). Read fresh at every render, so a toggle applies at once.
enum Typeset {
    static let on = "onyx.typeset"                 // the whole pass; off = plain Reitz LaTeX
    static let oldstyle = "onyx.oldstyleFigures"
    static let hyphens = "onyx.hyphenation"
    static let smallCaps = "onyx.smallCaps"        // runs of capitals (PSF, HTTP) in true small caps
    static let face = "onyx.typeface"              // "lm" (Latin Modern, Reitz LaTeX) | "et" (ET Book, Tufte)
    static let opening = "onyx.opening"            // "smallcaps" | "dropcap" | "none"
    static let justify = "onyx.justify"            // justified paragraphs; off = ragged right (default)

    static func bool(_ k: String, dflt: Bool = true) -> Bool { UserDefaults.standard.object(forKey: k) as? Bool ?? dflt }
    static var faceName: String { UserDefaults.standard.string(forKey: face) ?? "lm" }
    static var openingName: String { UserDefaults.standard.string(forKey: opening) ?? "smallcaps" }

    /// The `typeset` object the reader's typeset.js and typeset.css key off.
    static func options(preview: Bool = false, print: [String: Any]? = nil) -> [String: Any] {
        var o: [String: Any] = ["on": bool(on), "onum": bool(oldstyle), "hyphens": bool(hyphens), "smallCaps": bool(smallCaps),
                                "justify": bool(justify, dflt: false), "face": faceName, "opening": preview ? "none" : openingName]
        if let print { o["print"] = print }
        return o
    }
    static var signature: String { "\(bool(on))\(bool(oldstyle))\(bool(hyphens))\(bool(smallCaps))\(bool(justify, dflt: false))\(faceName)\(openingName)" }
}

/// Pages in the Settings window. `ONYX_SETTINGS_TAB` opens one at launch (screenshots).
enum SettingsTab: String, CaseIterable, Hashable, Identifiable {
    case general, files, daily, editor, linter, shortcuts, reading, graph, sync, updates

    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "General"
        case .files: "Files & Links"
        case .daily: "Daily Notes"
        case .linter: "Linter"
        case .editor: "Editor"
        case .shortcuts: "Shortcuts"
        case .reading: "Reading"
        case .graph: "Graph"
        case .sync: "Sync"
        case .updates: "Updates"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .files: "folder"
        case .daily: "calendar"
        case .linter: "checkmark.seal"
        case .editor: "character.cursor.ibeam"
        case .shortcuts: "keyboard"
        case .reading: "book"
        case .graph: "point.3.connected.trianglepath.dotted"
        case .sync: "arrow.triangle.2.circlepath.icloud"
        case .updates: "arrow.down.app"
        }
    }

    /// Accepts the tab id plus a few aliases (typography, typesetting, atlas, advanced, …).
    static func fromEnvironment() -> SettingsTab {
        let raw = ProcessInfo.processInfo.environment["ONYX_SETTINGS_TAB"]?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch raw {
        case "", "general", "appearance", "vault", "focus": return .general
        case "files", "links", "files-and-links", "attachments", "obsidian-settings": return .files
        case "daily", "daily-notes", "dailynotes", "templates": return .daily
        case "linter", "lint": return .linter
        case "editor", "composer", "notecomposer", "note-composer": return .editor
        case "shortcuts", "keys", "keyboard", "hotkeys", "hotkey": return .shortcuts
        case "reading", "typesetting", "typeset", "typography", "speech": return .reading
        case "graph", "atlas", "startup": return .graph
        case "sync", "obsidian": return .sync
        case "updates", "update", "advanced": return .updates
        default: return .general
        }
    }
}

struct SettingsView: View {
    @Bindable var ws: Workspace
    @State private var tab: SettingsTab = .fromEnvironment()

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettingsPage(ws: ws)
                .tabItem { Label(SettingsTab.general.title, systemImage: SettingsTab.general.symbol) }
                .tag(SettingsTab.general)
            FilesSettingsPage(ws: ws)
                .tabItem { Label(SettingsTab.files.title, systemImage: SettingsTab.files.symbol) }
                .tag(SettingsTab.files)
            DailySettingsPage(ws: ws)
                .tabItem { Label(SettingsTab.daily.title, systemImage: SettingsTab.daily.symbol) }
                .tag(SettingsTab.daily)
            EditorSettingsPage(ws: ws)
                .tabItem { Label(SettingsTab.editor.title, systemImage: SettingsTab.editor.symbol) }
                .tag(SettingsTab.editor)
            LinterSettingsPage()
                .tabItem { Label(SettingsTab.linter.title, systemImage: SettingsTab.linter.symbol) }
                .tag(SettingsTab.linter)
            ShortcutsSettingsPage()
                .tabItem { Label(SettingsTab.shortcuts.title, systemImage: SettingsTab.shortcuts.symbol) }
                .tag(SettingsTab.shortcuts)
            ReadingSettingsPage(ws: ws)
                .tabItem { Label(SettingsTab.reading.title, systemImage: SettingsTab.reading.symbol) }
                .tag(SettingsTab.reading)
            GraphSettingsPage(ws: ws)
                .tabItem { Label(SettingsTab.graph.title, systemImage: SettingsTab.graph.symbol) }
                .tag(SettingsTab.graph)
            SyncSettingsPage(ws: ws)
                .tabItem { Label(SettingsTab.sync.title, systemImage: SettingsTab.sync.symbol) }
                .tag(SettingsTab.sync)
            UpdatesSettingsPage()
                .tabItem { Label(SettingsTab.updates.title, systemImage: SettingsTab.updates.symbol) }
                .tag(SettingsTab.updates)
        }
        .frame(width: SettingsPage.width)
        .background(SettingsWindowHook(tab: tab))
    }
}

enum SettingsPage {
    static let width: CGFloat = 560
}

func settingsHeader(_ s: String) -> some View {
    Text(s).font(Theme.serif(14, bold: true)).foregroundStyle(Color.ink).textCase(nil)
}

private extension View {
    func settingsPage() -> some View {
        self
            .formStyle(.grouped)
            .frame(width: SettingsPage.width)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct GeneralSettingsPage: View {
    @Bindable var ws: Workspace
    @AppStorage(Prefs.appearance) private var appearance = "system"
    @AppStorage(Prefs.startFocus) private var startFocus = false

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                    Text("Auto").tag("system")
                }
                .pickerStyle(.segmented)
                Text("Auto follows the system’s light and dark setting.").font(.system(size: 11)).foregroundStyle(Color.faint)
            } header: { settingsHeader("Appearance") }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ws.root?.lastPathComponent ?? "No vault").font(Theme.serif(15, bold: true))
                        Text(ws.root?.path ?? "Choose a folder of Markdown notes.").font(.system(size: 11)).foregroundStyle(Color.faint).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button("Choose…") { chooseVault() }
                }
                if let snap = ws.snapshot {
                    Text("\(snap.notes.count) notes · \(snap.attachments.count) attachments · indexed in \(ws.indexMillis) ms")
                        .font(.system(size: 11)).foregroundStyle(Color.faint)
                }
            } header: { settingsHeader("Vault") }

            Section {
                Toggle("Open in focus mode (just the text)", isOn: $startFocus)
                Text("⌃⌘F toggles focus mode any time; Esc leaves it.").font(.system(size: 11)).foregroundStyle(Color.faint)
            } header: { settingsHeader("Focus") }
        }
        .settingsPage()
        .onChange(of: appearance) { OnyxApp.applyAppearance(appearance) }
    }

    func chooseVault() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.prompt = "Open Vault"
        p.directoryURL = ws.root
        if p.runModal() == .OK, let u = p.url { OnyxApp.remember(u); ws.open(vault: u) }
    }
}

struct EditorSettingsPage: View {
    @Bindable var ws: Workspace
    @AppStorage(Prefs.editorSize) private var editorSize = 14.0
    @AppStorage(Prefs.escToReading) private var escToReading = true
    @AppStorage(EditorPrefs.spellcheck) private var spellcheck = true
    @AppStorage(EditorPrefs.foldHeadings) private var foldHeadings = true
    @AppStorage(EditorPrefs.foldLists) private var foldLists = true
    @AppStorage(NoteComposer.Settings.confirmMergeKey) private var confirmMerge = true
    @AppStorage(NoteComposer.Settings.placementKey) private var mergePlacement = NoteComposer.Placement.append.rawValue
    @AppStorage(NoteComposer.Settings.locationKey) private var extractLocation = NoteComposer.NewLocation.sameFolder.rawValue
    @AppStorage(NoteComposer.Settings.afterExtractKey) private var afterExtract = NoteComposer.AfterExtract.link.rawValue
    @AppStorage(NoteComposer.Settings.openAfterExtractKey) private var openAfterExtract = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Editing size") {
                    HStack { Slider(value: $editorSize, in: 11...22, step: 1); Text("\(Int(editorSize)) pt").monospacedDigit().frame(width: 44, alignment: .trailing) }
                }
                Text("Line width is under Reading; the editor follows the same measure.")
                    .font(.system(size: 11)).foregroundStyle(Color.faint)
                Toggle("Check spelling while typing", isOn: $spellcheck)
                    .onChange(of: spellcheck) { Workspace.applySpellcheck(spellcheck) }
            } header: { settingsHeader("Editor") }

            Section {
                Toggle("Fold headings", isOn: $foldHeadings)
                    .onChange(of: foldHeadings) { Workspace.applyFoldPrefs() }
                Toggle("Fold indent (nested lists)", isOn: $foldLists)
                    .onChange(of: foldLists) { Workspace.applyFoldPrefs() }
                Text("A quiet chevron in the margin folds a section; folded text stays in the note. Folds are remembered per note on this Mac.")
                    .font(.system(size: 11)).foregroundStyle(Color.faint)
            } header: { settingsHeader("Folding") }

            Section {
                Toggle("Esc returns to reading view", isOn: $escToReading)
                Text("When nothing else is open, Esc in the editor saves and shows the reader. Esc never leaves reading view.")
                    .font(.system(size: 11)).foregroundStyle(Color.faint)
                if ws.root != nil {
                    Toggle("Smart indent lists", isOn: Binding(
                        get: {
                            _ = ws.obsidianConfigRevision
                            return (ws.obsidianJSON("app.json") as? [String: Any])?["smartIndentList"] as? Bool ?? true
                        },
                        set: { ws.setObsidianConfig("app.json", ["smartIndentList": $0]) }
                    ))
                    Text("Return in a list starts the next item with the same marker, or the next number, and following numbered items are renumbered. Return on an empty item ends the list, or outdents a nested one. Shift-Return inserts a plain newline. Tab and Shift-Tab indent and outdent list items, and both the level left and the level joined are renumbered (a newly nested item starts at 1). Saved as smartIndentList in the vault’s app.json, the same key Obsidian uses.")
                        .font(.system(size: 11)).foregroundStyle(Color.faint)
                    Toggle("Auto pair brackets", isOn: Binding(
                        get: {
                            _ = ws.obsidianConfigRevision
                            return (ws.obsidianJSON("app.json") as? [String: Any])?["autoPairBrackets"] as? Bool ?? true
                        },
                        set: { ws.setObsidianConfig("app.json", ["autoPairBrackets": $0]) }
                    ))
                    Toggle("Auto pair Markdown syntax", isOn: Binding(
                        get: {
                            _ = ws.obsidianConfigRevision
                            return (ws.obsidianJSON("app.json") as? [String: Any])?["autoPairMarkdown"] as? Bool ?? true
                        },
                        set: { ws.setObsidianConfig("app.json", ["autoPairMarkdown": $0]) }
                    ))
                    Text("Brackets and quotes insert their closer, with the caret in between; [[ becomes [[|]]. A selection is wrapped, including * _ ~ = (so ** makes bold). Typing the closer steps over it, and Backspace in an empty pair deletes both. Quotes do not pair mid-word, so don’t is unchanged. Markdown markers are not paired inside fenced code. Saved as autoPairBrackets and autoPairMarkdown in app.json, the same keys Obsidian uses.")
                        .font(.system(size: 11)).foregroundStyle(Color.faint)
                }
            } header: { settingsHeader("Keys") }

            Section {
                Toggle("Confirm file merge", isOn: $confirmMerge)
                Picker("Merge placement", selection: $mergePlacement) {
                    ForEach(NoteComposer.Placement.allCases, id: \.rawValue) { p in
                        Text(p.title).tag(p.rawValue)
                    }
                }
                Text("Merge Current File With Another File… appends or prepends the open note’s body to the note you pick, combines frontmatter, rewrites links to the source so they point at the target, and moves the source to the Trash.")
                    .font(.system(size: 11)).foregroundStyle(Color.faint)
                Picker("Location for new notes", selection: $extractLocation) {
                    ForEach(NoteComposer.NewLocation.allCases, id: \.rawValue) { loc in
                        Text(loc.title).tag(loc.rawValue)
                    }
                }
                Picker("Text after extraction", selection: $afterExtract) {
                    ForEach(NoteComposer.AfterExtract.allCases, id: \.rawValue) { s in
                        Text(s.title).tag(s.rawValue)
                    }
                }
                Toggle("Open new file after extracting", isOn: $openAfterExtract)
                Text("Extract Current Selection… and Extract This Heading… move the text into a new note, or append it to one you pick. The heading’s name is offered when the selection starts with a heading. Replacing the selection with a link is one undo step in the editor.")
                    .font(.system(size: 11)).foregroundStyle(Color.faint)
            } header: { settingsHeader("Note composer") }
        }
        .settingsPage()
    }
}


struct ReadingSettingsPage: View {
    @Bindable var ws: Workspace
    @AppStorage(Prefs.readerSize) private var readerSize = 19.0
    @AppStorage(Prefs.editorSize) private var editorSize = 14.0
    @AppStorage(Prefs.measure) private var measure = 41.0
    @AppStorage(Prefs.sidenotes) private var sidenotes = true
    @AppStorage(Typeset.on) private var typeset = true
    @AppStorage(Typeset.oldstyle) private var oldstyle = true
    @AppStorage(Typeset.hyphens) private var hyphens = true
    @AppStorage(Typeset.smallCaps) private var smallCaps = true
    @AppStorage(Typeset.face) private var face = "lm"
    @AppStorage(Typeset.opening) private var opening = "smallcaps"
    @AppStorage(Typeset.justify) private var justify = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Reading size") {
                    HStack { Slider(value: $readerSize, in: 15...26, step: 1); Text("\(Int(readerSize)) px").monospacedDigit().frame(width: 44, alignment: .trailing) }
                }
                LabeledContent("Line width") {
                    HStack { Slider(value: $measure, in: 30...60, step: 1); Text("\(Int(measure)) rem").monospacedDigit().frame(width: 52, alignment: .trailing) }
                }
                Toggle("Footnotes as sidenotes in the margin", isOn: $sidenotes)
                Button("Restore Reitz LaTeX defaults") {
                    readerSize = 19; editorSize = 14; measure = 41; sidenotes = true
                    typeset = true; oldstyle = true; hyphens = true; smallCaps = true; justify = false; face = "lm"; opening = "smallcaps"
                }
                    .buttonStyle(.link).font(.system(size: 11.5))
            } header: { settingsHeader("Typography") }

            Section {
                Toggle("Typeset reading", isOn: $typeset)
                Group {
                    Picker("Typeface", selection: $face) {
                        Text("Latin Modern (Reitz LaTeX)").tag("lm")
                        Text("ET Book (Tufte)").tag("et")
                    }
                    Picker("Opening paragraph", selection: $opening) {
                        Text("Small-caps lead-in").tag("smallcaps")
                        Text("Drop cap").tag("dropcap")
                        Text("Plain").tag("none")
                    }
                    Toggle("Old-style figures in text", isOn: $oldstyle)
                    Toggle("Hyphenation", isOn: $hyphens)
                    Toggle("Justified paragraphs", isOn: $justify)
                    Toggle("Small caps for abbreviations (PSF, HTTP)", isOn: $smallCaps)
                }
                .disabled(!typeset)
                Text("Smart quotes and dashes, ties, true small caps, hanging punctuation and a baseline rhythm. Off is the plain Reitz LaTeX page. Code is never touched.")
                    .font(.system(size: 11)).foregroundStyle(Color.faint)
            } header: { settingsHeader("Typesetting") }

            SpeechSettingsSection()
        }
        .settingsPage()
        .onChange(of: sidenotes) { ws.sidenotes = sidenotes }
    }
}


private struct SpeechSettingsSection: View {
    @AppStorage(SpeechPrefs.voice) private var voice = ""
    @AppStorage(SpeechPrefs.rate) private var rate = Double(AVSpeechUtteranceDefaultSpeechRate)
    @AppStorage(RecordingPrefs.autoTranscribe) private var autoTranscribe = true
    private let voices = SpeechReader.voices()

    var body: some View {
        Section {
            Picker("Voice", selection: $voice) {
                Text("System default").tag("")
                ForEach(voices, id: \.identifier) { v in
                    Text("\(v.name) (\(SpeechReader.languageName(v.language)))").tag(v.identifier)
                }
            }
            LabeledContent("Rate") {
                HStack(spacing: 8) {
                    Text("Slow").font(.system(size: 11)).foregroundStyle(Color.faint)
                    Slider(value: $rate,
                           in: Double(AVSpeechUtteranceMinimumSpeechRate)...Double(AVSpeechUtteranceMaximumSpeechRate))
                    Text("Fast").font(.system(size: 11)).foregroundStyle(Color.faint)
                }
            }
            Text("Read Aloud in the command palette or the Note menu speaks the selection, or the whole note. It uses the Mac’s voices and works offline.")
                .font(.system(size: 11)).foregroundStyle(Color.faint)
            Toggle("Transcribe recordings automatically", isOn: $autoTranscribe)
            Text("Record Audio saves an .m4a to the attachments folder, embeds it at the cursor, and adds an on-device transcript below it.")
                .font(.system(size: 11)).foregroundStyle(Color.faint)
        } header: { settingsHeader("Speech") }
    }
}

struct GraphSettingsPage: View {
    @Bindable var ws: Workspace

    var body: some View {
        Form {
            Section {
                if ws.root != nil {
                    Toggle("Open the atlas on startup", isOn: Binding(get: { ws.atlasOnStartup }, set: { ws.atlasOnStartup = $0 }))
                    Text(ws.obsidianHomeIsGraph ? "On by default here: this vault's Obsidian Homepage opens the graph." : "The graph opens over your notes at launch; click a note to start.")
                        .font(.system(size: 11)).foregroundStyle(Color.faint)
                } else {
                    Text("Open a vault to choose whether the atlas opens at launch.")
                        .font(.system(size: 11)).foregroundStyle(Color.faint)
                }
            } header: { settingsHeader("Startup (this vault)") }
        }
        .settingsPage()
    }
}

struct SyncSettingsPage: View {
    @Bindable var ws: Workspace
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                if let g = ws.git {
                    Text(g.help).font(.system(size: 11)).foregroundStyle(Color.faint)
                } else {
                    Text("This vault isn’t a git repository, so Onyx isn’t auto-committing.")
                        .font(.system(size: 11)).foregroundStyle(Color.faint)
                }
                ShowSyncLogButton(ws: ws, dismiss: dismiss)
            } header: { settingsHeader("Git") }
            ObsidianSyncSettings(ws: ws, onShowLog: { SettingsSyncLog.show(ws, dismiss: dismiss) })
        }
        .settingsPage()
    }
}

/// Opens the Sync Log on the main window and closes Settings so the panel is visible.
struct ShowSyncLogButton: View {
    var ws: Workspace
    var dismiss: DismissAction
    var body: some View {
        AppKitPushButton(title: "Show Log", id: SettingsSyncLog.buttonID) {
            SettingsSyncLog.show(ws, dismiss: dismiss)
        }
    }
}

/// A real NSButton so UI tests can `performClick` it. SwiftUI `Button` in a Settings
/// `Form` often lives in the out-of-process render tree (`TUINSWindow`) with no NSButton.
struct AppKitPushButton: NSViewRepresentable {
    var title: String
    var id: String
    var action: () -> Void

    final class Button: NSButton {
        var onPress: (() -> Void)?
        @objc func tapped(_ sender: Any?) { onPress?() }
    }

    func makeNSView(context: Context) -> Button {
        let b = Button(title: title, target: nil, action: nil)
        b.bezelStyle = .rounded
        b.setButtonType(.momentaryPushIn)
        b.controlSize = .regular
        b.target = b
        b.action = #selector(Button.tapped(_:))
        b.onPress = action
        b.identifier = NSUserInterfaceItemIdentifier(id)
        b.setAccessibilityIdentifier(id)
        b.setAccessibilityTitle(title)
        b.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        b.setContentHuggingPriority(.required, for: .vertical)
        return b
    }

    func updateNSView(_ b: Button, context: Context) {
        b.title = title
        b.onPress = action
        b.identifier = NSUserInterfaceItemIdentifier(id)
        b.setAccessibilityIdentifier(id)
    }
}

enum SettingsSyncLog {
    static let buttonID = "settings-show-sync-log"

    @MainActor static func show(_ ws: Workspace, dismiss: DismissAction? = nil) {
        ws.show(.syncLog)
        dismiss?()
        closeSettingsWindows()
        DispatchQueue.main.async { closeSettingsWindows() }
    }

    @MainActor static func closeSettingsWindows() {
        for w in NSApp.windows where w !== MainWindow.current && !(w is NSPanel) {
            guard isSettings(w) else { continue }
            w.performClose(nil)
            if w.isVisible { w.close() }
            if w.isVisible { w.orderOut(nil) }
        }
    }

    static func isSettings(_ w: NSWindow) -> Bool {
        if w.identifier?.rawValue == "onyx-settings" { return true }
        let t = w.title
        if t == "Settings" || t.hasSuffix(" Settings") || t.hasPrefix("Settings") { return true }
        return SettingsTab.allCases.contains { $0.title == t }
    }

    @MainActor static func clickShowLogButton() -> Bool {
        for w in NSApp.windows {
            if press(findView(w.contentView, id: buttonID)) { return true }
            if press(findLabeled(w.contentView, "Show Log")) { return true }
        }
        let dump = NSApp.windows.map { w in
            "\(w.title)[\(type(of: w)) id=\(w.identifier?.rawValue ?? "-")]"
        }.joined(separator: "; ")
        print("[clicksynclog] windows=\(dump.isEmpty ? "(none)" : dump)")
        fflush(stdout)
        return false
    }

    @MainActor private static func press(_ v: NSView?) -> Bool {
        guard let v else { return false }
        if let b = v as? NSButton { b.performClick(nil); return true }
        if let c = v as? NSControl { c.performClick(nil); return true }
        if v.accessibilityPerformPress() { return true }
        if v.responds(to: #selector(NSControl.performClick(_:))) {
            v.perform(#selector(NSControl.performClick(_:)), with: nil)
            return true
        }
        return false
    }

    private static func findView(_ v: NSView?, id: String) -> NSView? {
        guard let v else { return nil }
        if v.accessibilityIdentifier() == id || v.identifier?.rawValue == id { return v }
        for s in v.subviews { if let r = findView(s, id: id) { return r } }
        return nil
    }

    private static func findLabeled(_ v: NSView?, _ title: String) -> NSView? {
        guard let v else { return nil }
        if let b = v as? NSButton, b.title == title { return b }
        if v.accessibilityLabel() == title || v.accessibilityTitle() == title { return v }
        for s in v.subviews { if let r = findLabeled(s, title) { return r } }
        return nil
    }
}

struct UpdatesSettingsPage: View {
    @AppStorage(UpdatePrefs.automatic) private var autoUpdates = true

    var body: some View {
        Form {
            Section {
                Toggle("Automatically check for updates", isOn: $autoUpdates)
                Text("Onyx looks for a new GitHub release on launch and every six hours. You can also check from the Onyx menu.")
                    .font(.system(size: 11)).foregroundStyle(Color.faint)
            } header: { settingsHeader("Updates") }
        }
        .settingsPage()
    }
}

/// Fits the Settings window to the current tab. Under `ONYX_SHOT_QUIET`, never
/// persist the frame (the shot app shares defaults with the installed Onyx) and
/// park the window off screen. When `ONYX_OPEN_SETTINGS` is set, the window-id
/// file is updated to this window so screenshots capture Settings.
private struct SettingsWindowHook: NSViewRepresentable {
    var tab: SettingsTab

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async { Self.apply(v.window, first: true) }
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { Self.apply(v.window, first: false) }
    }

    static func apply(_ w: NSWindow?, first: Bool) {
        guard let w, w !== MainWindow.current else { return }
        let quiet = ProcessInfo.processInfo.environment["ONYX_SHOT_QUIET"] == "1"
        if quiet {
            w.setFrameAutosaveName("")
            w.isRestorable = false
            w.ignoresMouseEvents = true
        }
        let fitting = w.contentView?.fittingSize ?? .zero
        if fitting.width > 0, fitting.height > 0 {
            let content = NSSize(width: max(fitting.width, SettingsPage.width), height: fitting.height)
            let target = w.frameRect(forContentRect: NSRect(origin: .zero, size: content)).size
            if abs(w.frame.width - target.width) > 1 || abs(w.frame.height - target.height) > 1 {
                var f = w.frame
                f.origin.y += f.height - target.height
                f.size = target
                if quiet { f.origin = NSPoint(x: -f.width - 3000, y: 0) }
                w.setFrame(f, display: true, animate: !quiet && !first)
            } else if quiet, w.frame.origin.x > -1000 {
                w.setFrameOrigin(NSPoint(x: -w.frame.width - 3000, y: 0))
            }
        } else if quiet, w.frame.origin.x > -1000 {
            w.setFrameOrigin(NSPoint(x: -w.frame.width - 3000, y: 0))
        }
        w.identifier = NSUserInterfaceItemIdentifier("onyx-settings")
        if ProcessInfo.processInfo.environment["ONYX_OPEN_SETTINGS"] != nil, let file = WindowConfigurator.idFile {
            try? String(w.windowNumber).write(toFile: file, atomically: true, encoding: .utf8)
        }
    }
}
