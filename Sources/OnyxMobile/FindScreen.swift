import SwiftUI
import OnyxCore

/// Vault-wide find, with replace when the security-scoped folder can be written.
struct FindScreen: View {
    @EnvironmentObject private var vault: MobileVault
    @State private var find = ""
    @State private var replacement = ""
    @State private var matchCase = false
    @State private var wholeWord = false
    @State private var regex = false
    @State private var preview = FindReplace.Preview.empty
    @State private var selected: Set<String> = []
    @State private var toast: String?

    var options: FindReplace.Options {
        FindReplace.Options(matchCase: matchCase, wholeWord: wholeWord, regex: regex, includeFrontmatter: true, scope: .vault)
    }

    var checked: [FindReplace.Match] {
        preview.groups.flatMap(\.matches).filter { selected.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            fields
            if let err = preview.error {
                Text(err).font(.footnote).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.bottom, 6)
            } else if !find.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(status)
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.bottom, 6)
            }
            results
        }
        .navigationTitle("Find")
        .onChange(of: find) { schedule() }
        .onChange(of: matchCase) { schedule() }
        .onChange(of: wholeWord) { schedule() }
        .onChange(of: regex) { schedule() }
        .onChange(of: replacement) { schedule() }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast).font(.footnote).padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .padding()
            }
        }
    }

    var fields: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Find in vault", text: $find)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            HStack {
                option("Aa", on: matchCase, help: "Match case") { matchCase.toggle() }
                option("W", on: wholeWord, help: "Whole word") { wholeWord.toggle() }
                option(".*", on: regex, help: "Regular expression") { regex.toggle() }
                Spacer()
            }
            if vault.canWrite {
                TextField("Replace with", text: $replacement)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Button("Replace selected") { apply() }
                    .disabled(checked.isEmpty || preview.error != nil)
            } else {
                Text("Find only — the vault folder isn’t writable, so replace is turned off.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    var status: String {
        let n = preview.matchCount
        let cap = preview.truncated ? "\(n)+" : "\(n)"
        return "\(cap) matches in \(preview.fileCount) note\(preview.fileCount == 1 ? "" : "s") · \(checked.count) selected"
    }

    @ViewBuilder
    var results: some View {
        let q = find.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            ContentUnavailableView("Find across the vault", systemImage: "magnifyingglass",
                                   description: Text("Match case, whole word, or a regular expression. Check the matches to include, then replace if you want."))
        } else if preview.groups.isEmpty && preview.error == nil {
            ContentUnavailableView.search(text: find)
        } else {
            List {
                ForEach(preview.groups, id: \.path) { group in
                    Section {
                        ForEach(group.matches) { m in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: selected.contains(m.id) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(selected.contains(m.id) ? .primary : .secondary)
                                    .onTapGesture { toggle(m.id) }
                                VStack(alignment: .leading, spacing: 2) {
                                    highlighted(m)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture { vault.openNote(m.path, line: max(0, m.line - 1)) }
                            }
                        }
                    } header: {
                        let ids = group.matches.map(\.id)
                        let n = ids.filter { selected.contains($0) }.count
                        HStack {
                            Button {
                                if n == ids.count { ids.forEach { selected.remove($0) } }
                                else { selected.formUnion(ids) }
                            } label: {
                                Image(systemName: n == ids.count && !ids.isEmpty ? "checkmark.square.fill" : "square")
                            }
                            .buttonStyle(.plain)
                            Text(((group.path as NSString).lastPathComponent as NSString).deletingPathExtension)
                            Spacer()
                            Text("\(n)/\(ids.count)").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    func highlighted(_ m: FindReplace.Match) -> some View {
        (Text(m.prefix).foregroundStyle(.secondary)
         + Text(m.text).fontWeight(.semibold).foregroundStyle(.primary)
         + Text(m.suffix).foregroundStyle(.secondary))
        .font(.subheadline)
        .lineLimit(2)
    }

    func option(_ title: String, on: Bool, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(on ? .bold : .regular))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(on ? Color.primary.opacity(0.12) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    func schedule() {
        let q = find
        let opts = options
        let repl = replacement
        guard let snap = vault.snapshot, !q.trimmingCharacters(in: .whitespaces).isEmpty else {
            preview = .empty
            selected = []
            return
        }
        let result = FindReplace.preview(query: q, replacement: repl, in: snap, options: opts)
        preview = result
        selected = Set(result.groups.flatMap(\.matches).map(\.id))
    }

    func apply() {
        let r = vault.applyVaultReplace(query: find, replacement: replacement, options: options, selected: checked)
        if r.replacements == 0 { flash("Nothing to replace") }
        else { flash("Replaced \(r.replacements) match\(r.replacements == 1 ? "" : "es") in \(r.files) note\(r.files == 1 ? "" : "s")") }
        schedule()
    }

    func flash(_ s: String) {
        toast = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if toast == s { toast = nil } }
    }
}
