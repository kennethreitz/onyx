import AppKit
import SwiftUI
import OnyxCore

/// Read-only Obsidian Bases view: a quiet table, list or card grid over the current vault
/// snapshot, with a view switcher and sortable columns. Clicking a note name opens it.
struct BasesView: View {
    @Bindable var ws: Workspace
    /// Set for an unfocused split pane.
    var source: (path: String?, text: String)? = nil
    @State private var viewIndex = 0
    @State private var clickSort: (key: String, ascending: Bool)? = nil

    var path: String? { source == nil ? ws.currentPath : source!.path }
    var text: String { source?.text ?? ws.text }

    var body: some View {
        let file = Bases.parse(text)
        let idx = min(max(viewIndex, 0), max(file.views.count - 1, 0))
        let raw = file.views.isEmpty ? emptyResult(file) : Bases.run(file, view: idx, in: ws.snapshot ?? VaultSnapshot(root: ws.root ?? URL(fileURLWithPath: "/tmp")), from: path)
        let result = applyClickSort(raw)
        VStack(spacing: 0) {
            header(file: file, result: result)
            if !result.warnings.isEmpty { warning(result.warnings) }
            if result.rows.isEmpty {
                Spacer()
                Text("No notes match this view.").font(Theme.serif(16, italic: true)).foregroundStyle(Color.muted)
                Spacer()
            } else {
                switch result.view.type {
                case "cards": cards(result)
                case "list": list(result)
                default: table(result)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper)
        .onChange(of: path) { viewIndex = 0; clickSort = nil }
    }

    func emptyResult(_ file: BaseFile) -> BaseResult {
        let v = BaseView(type: "table", name: "Table", filters: .always, order: ["file.name"], sort: [], limit: nil, groupBy: nil, cardSize: nil, coverProperty: nil, indentProperties: false)
        return BaseResult(view: v, columns: [BaseColumn(key: "file.name", displayName: "Name")], rows: [], groups: nil, warnings: file.warnings, total: 0)
    }

    func applyClickSort(_ r: BaseResult) -> BaseResult {
        guard let s = clickSort else { return r }
        var out = r
        out.rows = Bases.sort(r.rows, by: s.key, ascending: s.ascending)
        if let groups = r.groups {
            out.groups = groups.map { BaseGroup(title: $0.title, rows: Bases.sort($0.rows, by: s.key, ascending: s.ascending)) }
        }
        return out
    }

    func header(file: BaseFile, result: BaseResult) -> some View {
        HStack(spacing: 14) {
            if file.views.count > 1 {
                ForEach(Array(file.views.enumerated()), id: \.offset) { i, v in
                    Button {
                        viewIndex = i
                        clickSort = nil
                    } label: {
                        VStack(spacing: 3) {
                            Text(v.name)
                                .font(.system(size: 12, weight: i == viewIndex ? .medium : .regular))
                                .foregroundStyle(i == viewIndex ? Color.ink : Color.muted)
                            Rectangle().fill(i == viewIndex ? Color.ink.opacity(0.7) : Color.clear).frame(height: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text(file.name ?? result.view.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ink)
            }
            Spacer()
            Text(countLabel(result))
                .font(.system(size: 11))
                .foregroundStyle(Color.faint)
        }
        .padding(.horizontal, 22)
        .padding(.top, 36)
        .padding(.bottom, 10)
    }

    func countLabel(_ r: BaseResult) -> String {
        let n = r.rows.count
        let noun = n == 1 ? "item" : "items"
        if r.total > n { return "\(n) of \(r.total) \(noun)" }
        return "\(n) \(noun)"
    }

    func warning(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(warnings, id: \.self) { w in
                Text(w).font(.system(size: 11)).foregroundStyle(Color.muted)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.paperAlt)
    }

    // MARK: Table

    func table(_ r: BaseResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerRow(r.columns)
                if let groups = r.groups {
                    ForEach(groups) { g in
                        Text(g.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.muted)
                            .padding(.horizontal, 22)
                            .padding(.top, 14)
                            .padding(.bottom, 4)
                        ForEach(Array(g.rows.enumerated()), id: \.element.id) { i, row in
                            tableRow(row, columns: r.columns, alt: i % 2 == 1)
                        }
                    }
                } else {
                    ForEach(Array(r.rows.enumerated()), id: \.element.id) { i, row in
                        tableRow(row, columns: r.columns, alt: i % 2 == 1)
                    }
                }
            }
            .padding(.bottom, 40)
        }
    }

    func headerRow(_ columns: [BaseColumn]) -> some View {
        HStack(spacing: 0) {
            ForEach(columns) { c in
                Button {
                    if clickSort?.key == c.key { clickSort = (c.key, !(clickSort?.ascending ?? true)) }
                    else { clickSort = (c.key, true) }
                } label: {
                    HStack(spacing: 4) {
                        Text(c.displayName)
                        if clickSort?.key == c.key {
                            Image(systemName: clickSort?.ascending == true ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                        }
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.hairline).frame(height: 1) }
    }

    func tableRow(_ row: BaseRowView, columns: [BaseColumn], alt: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(columns) { c in
                cell(row, key: c.key, first: c.key == columns.first?.key)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 14)
        .background(alt ? Color.paperAlt.opacity(0.6) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { open(row) }
    }

    @ViewBuilder func cell(_ row: BaseRowView, key: String, first: Bool) -> some View {
        let v = row.cells[key] ?? .null
        let isName = first || key == "file.name" || key == "note.name" || key == "file.link"
        if isName && row.isNote {
            Text(v.text.isEmpty ? row.name : v.text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.ink)
                .underline(true, pattern: .dot, color: Color.faint)
        } else {
            Text(v.text.isEmpty ? "—" : v.text)
                .font(.system(size: 12.5))
                .foregroundStyle(v.text.isEmpty ? Color.faint : Color.ink)
                .lineLimit(3)
        }
    }

    // MARK: List

    func list(_ r: BaseResult) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(r.rows) { row in
                    Button { open(row) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(row.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.ink)
                            Spacer(minLength: 8)
                            let extras = r.columns.filter { $0.key != "file.name" && $0.key != "note.name" }
                            ForEach(extras.prefix(4)) { c in
                                let t = row.cells[c.key]?.text ?? ""
                                if !t.isEmpty {
                                    Text(t)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Color.muted)
                                }
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(Color.hairline).frame(height: 1).padding(.horizontal, 22)
                }
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: Cards

    func cards(_ r: BaseResult) -> some View {
        let size = CGFloat(r.view.cardSize ?? 200)
        let cols = [GridItem(.adaptive(minimum: max(160, size - 20), maximum: size + 40), spacing: 16)]
        return ScrollView {
            LazyVGrid(columns: cols, spacing: 16) {
                ForEach(r.rows) { row in
                    Button { open(row) } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            cover(row, height: size * 0.62)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.ink)
                                    .lineLimit(2)
                                let extras = r.columns.filter { $0.key != "file.name" && $0.key != "note.name" }
                                ForEach(extras.prefix(4)) { c in
                                    let t = row.cells[c.key]?.text ?? ""
                                    if !t.isEmpty {
                                        Text(t)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color.muted)
                                            .lineLimit(2)
                                    }
                                }
                            }
                            .padding(10)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: size, alignment: .topLeading)
                        .background(Color.paperAlt)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.hairline, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
        }
    }

    @ViewBuilder func cover(_ row: BaseRowView, height: CGFloat) -> some View {
        if let p = row.coverPath, let root = ws.root,
           let img = NSImage(contentsOf: root.appendingPathComponent(p)) {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                .clipped()
        } else {
            Rectangle()
                .fill(Color.secondaryPaper)
                .frame(maxWidth: .infinity, minHeight: height * 0.45, maxHeight: height * 0.45)
        }
    }

    func open(_ row: BaseRowView) {
        if row.isNote || row.path.isCanvasPath || row.path.isBasePath {
            ws.openNote(row.path)
        } else if let root = ws.root {
            NSWorkspace.shared.open(root.appendingPathComponent(row.path))
        }
    }
}
