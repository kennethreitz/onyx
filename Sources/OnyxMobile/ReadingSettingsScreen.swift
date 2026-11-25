import SwiftUI
import OnyxCore

/// Typeface and typeset options for the iOS reader. Same UserDefaults keys as Mac Settings ▸ Reading.
struct ReadingSettingsScreen: View {
    @AppStorage(TypesetSettings.Key.on) private var typeset = true
    @AppStorage(TypesetSettings.Key.oldstyle) private var oldstyle = true
    @AppStorage(TypesetSettings.Key.hyphens) private var hyphens = true
    @AppStorage(TypesetSettings.Key.smallCaps) private var smallCaps = true
    @AppStorage(TypesetSettings.Key.face) private var face = "lm"
    @AppStorage(TypesetSettings.Key.opening) private var opening = "smallcaps"
    @AppStorage(TypesetSettings.Key.justify) private var justify = false
    var onChange: () -> Void = {}

    var body: some View {
        Form {
            Section {
                Toggle("Typeset reading", isOn: $typeset)
                Picker("Typeface", selection: $face) {
                    ForEach(TypesetSettings.faces, id: \.id) { item in
                        Text(item.title).tag(item.id)
                    }
                }
                .disabled(!typeset)
                if typeset && face == "od" {
                    Text("A typeset page in OpenDyslexic: a slightly smaller apparent size, a shorter measure, no small caps or old-style figures, ragged left, and no hyphenation. Code stays monospace.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Picker(face == "od" ? "Opening paragraph" : "Opening paragraph", selection: $opening) {
                    Text(face == "od" ? "Bold lead-in" : "Small-caps lead-in").tag("smallcaps")
                    if face != "od" { Text("Drop cap").tag("dropcap") }
                    Text("Plain").tag("none")
                }
                .disabled(!typeset)
                Toggle("Old-style figures", isOn: $oldstyle)
                    .disabled(!typeset || face == "od")
                Toggle("Hyphenation", isOn: $hyphens)
                    .disabled(!typeset || face == "od")
                Toggle("Small caps for acronyms", isOn: $smallCaps)
                    .disabled(!typeset || face == "od")
                Toggle("Justify paragraphs", isOn: $justify)
                    .disabled(!typeset || face == "od")
            } header: {
                Text("Reading")
            } footer: {
                Text("Latin Modern, ET Book, and OpenDyslexic are bundled and apply only in this app’s reader — they aren’t written to the vault.")
            }
        }
        .navigationTitle("Reading")
        .onAppear { TypesetSettings.migrateOpenDyslexic() }
        .onChange(of: typeset) { bump() }
        .onChange(of: face) { if face == "od", opening == "dropcap" { opening = "smallcaps" }; bump() }
        .onChange(of: opening) { bump() }
        .onChange(of: oldstyle) { bump() }
        .onChange(of: hyphens) { bump() }
        .onChange(of: smallCaps) { bump() }
        .onChange(of: justify) { bump() }
    }

    func bump() { onChange() }
}
