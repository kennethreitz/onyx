import SwiftUI
import OnyxCore

/// Notes that link to the current note, plus unlinked mentions of its title or aliases.
struct BacklinksScreen: View {
    @EnvironmentObject private var vault: MobileVault
    @State private var toast: String?

    var body: some View {
        Group {
            if let note = vault.selectedNote, let snap = vault.snapshot {
                List {
                    let links = snap.backlinks(to: note.path)
                    Section("Linked mentions · \(links.count)") {
                        if links.isEmpty {
                            Text("Nothing links here yet. Write [[\(note.name)]] in another note.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(links, id: \.self) { b in
                                MentionRow(path: b.source, detail: b.context, name: snap.notes[b.source]?.name) {
                                    vault.openNote(b.source, line: b.line)
                                }
                            }
                        }
                    }
                    let unlinked = snap.unlinkedMentions(of: note.path)
                    Section {
                        if unlinked.isEmpty {
                            Text("No unlinked mentions of this note’s title or aliases, outside code and links.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(unlinked, id: \.self) { m in
                                MentionRow(path: m.source, detail: m.context, name: snap.notes[m.source]?.name, linkTitle: vault.canWrite ? "Link" : nil) {
                                    vault.openNote(m.source, line: m.line)
                                } onLink: {
                                    link(m, title: note.name)
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("Unlinked mentions · \(unlinked.count)")
                            Spacer()
                            if vault.canWrite && !unlinked.isEmpty {
                                Button("Link all") { linkAll(of: note.path, mentions: unlinked) }
                                    .font(.caption.weight(.semibold))
                                    .textCase(nil)
                            }
                        }
                    } footer: {
                        if !vault.canWrite {
                            Text("Link needs write access to the vault folder.")
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                ContentUnavailableView("No note selected", systemImage: "arrow.uturn.backward",
                                       description: Text("Open a note to see what links to it."))
            }
        }
        .navigationTitle("Backlinks")
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.footnote)
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .padding()
            }
        }
    }

    func link(_ m: UnlinkedMention, title: String) {
        if vault.linkMention(m, title: title) {
            flash("Linked “\(m.matched)”")
        }
    }

    func linkAll(of path: String, mentions: [UnlinkedMention]) {
        let r = vault.linkAllMentions(of: path, mentions: mentions)
        if r.count == 0 { flash("Nothing to link") }
        else { flash("Linked \(r.count) mention\(r.count == 1 ? "" : "s") in \(r.files) note\(r.files == 1 ? "" : "s")") }
    }

    func flash(_ s: String) {
        toast = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if toast == s { toast = nil } }
    }
}

struct MentionRow: View {
    var path: String
    var detail: String
    var name: String?
    var linkTitle: String? = nil
    var onOpen: () -> Void
    var onLink: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !detail.isEmpty {
                        Text(NoteParser.stripInline(detail))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            if let linkTitle, let onLink {
                Button(linkTitle, action: onLink)
                    .font(.caption.weight(.semibold))
            }
        }
    }
}
