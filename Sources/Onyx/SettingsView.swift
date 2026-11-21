import SwiftUI
import AppKit
import OnyxCore

enum Prefs {
    static let appearance = "onyx.appearance"     // "system" | "light" | "dark"
    static let readerSize = "onyx.readerSize"     // px, reading view body
    static let editorSize = "onyx.editorSize"     // pt, source editor
    static let measure = "onyx.measure"           // rem, the reading measure (editor follows)
    static let startFocus = "onyx.startFocus"
    static let sidenotes = "onyx.sidenotes"

    static var editorPoints: CGFloat { CGFloat(UserDefaults.standard.object(forKey: editorSize) as? Double ?? 14) }
    static var measureRem: CGFloat { CGFloat(UserDefaults.standard.object(forKey: measure) as? Double ?? 41) }
    /// The editor's 760px measure corresponds to the reader's 41rem; keep them in proportion.
    static var editorMeasure: CGFloat { (measureRem / 41 * 760).rounded() }
}

/// Typeset reading (Settings ▸ Typography). Read fresh at every render, so a toggle applies at once.
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

struct SettingsView: View {
    @Bindable var ws: Workspace
    @AppStorage(Prefs.appearance) private var appearance = "system"
    @AppStorage(Prefs.readerSize) private var readerSize = 19.0
    @AppStorage(Prefs.editorSize) private var editorSize = 14.0
    @AppStorage(Prefs.measure) private var measure = 41.0
    @AppStorage(Prefs.startFocus) private var startFocus = false
    @AppStorage(Prefs.sidenotes) private var sidenotes = true
    @AppStorage(Typeset.on) private var typeset = true
    @AppStorage(Typeset.oldstyle) private var oldstyle = true
    @AppStorage(Typeset.hyphens) private var hyphens = true
    @AppStorage(Typeset.smallCaps) private var smallCaps = true
    @AppStorage(Typeset.face) private var face = "lm"
    @AppStorage(Typeset.opening) private var opening = "smallcaps"
    @AppStorage(UpdatePrefs.automatic) private var autoUpdates = true
    @AppStorage(Typeset.justify) private var justify = false

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
            } header: { header("Appearance") }

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
            } header: { header("Vault") }

            Section {
                LabeledContent("Reading size") {
                    HStack { Slider(value: $readerSize, in: 15...26, step: 1); Text("\(Int(readerSize)) px").monospacedDigit().frame(width: 44, alignment: .trailing) }
                }
                LabeledContent("Editing size") {
                    HStack { Slider(value: $editorSize, in: 11...22, step: 1); Text("\(Int(editorSize)) pt").monospacedDigit().frame(width: 44, alignment: .trailing) }
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
            } header: { header("Typography") }

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
            } header: { header("Typesetting") }

            Section {
                Toggle("Open in focus mode (just the text)", isOn: $startFocus)
                Text("⌃⌘F toggles focus mode any time; Esc leaves it.").font(.system(size: 11)).foregroundStyle(Color.faint)
            } header: { header("Focus") }

            Section {
                Toggle("Automatically check for updates", isOn: $autoUpdates)
                Text("Onyx looks for a new GitHub release on launch and every six hours. You can also check from the Onyx menu.")
                    .font(.system(size: 11)).foregroundStyle(Color.faint)
            } header: { header("Updates") }

            if ws.root != nil {
                Section {
                    Toggle("Open the atlas on startup", isOn: Binding(get: { ws.atlasOnStartup }, set: { ws.atlasOnStartup = $0 }))
                    Text(ws.obsidianHomeIsGraph ? "On by default here: this vault's Obsidian Homepage opens the graph." : "The graph opens over your notes at launch; click a note to start.")
                        .font(.system(size: 11)).foregroundStyle(Color.faint)
                } header: { header("Startup (this vault)") }
            }

            ObsidianSyncSettings(ws: ws)
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: appearance) { OnyxApp.applyAppearance(appearance) }
        .onChange(of: sidenotes) { ws.sidenotes = sidenotes }
    }

    func header(_ s: String) -> some View {
        Text(s).font(Theme.serif(14, bold: true)).foregroundStyle(Color.ink).textCase(nil)
    }

    func chooseVault() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.prompt = "Open Vault"
        p.directoryURL = ws.root
        if p.runModal() == .OK, let u = p.url { OnyxApp.remember(u); ws.open(vault: u) }
    }
}
