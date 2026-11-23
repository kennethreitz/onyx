import AppKit
import SwiftUI
import OnyxCore

/// Obsidian Bases view: a quiet table, list or card grid over the current vault
/// snapshot, with a view switcher, sortable columns, and light YAML editing.
/// Writes go through `BaseDoc` (comments and unknown keys stay put) and
/// `Workspace.write` (atomic). ⌘Z undoes the last edit when this pane is live.
struct BasesView: View {
    @Bindable var ws: Workspace
    /// Set for an unfocused split pane — display only; never write stale text back.
    var source: (path: String?, text: String)? = nil
    @Environment(\.undoManager) private var undoManager
    @State private var viewIndex = 0
    @State private var renaming: String = ""
    @State private var showRename = ProcessInfo.processInfo.environment["ONYX_BASES_EDIT"]?.lowercased() == "rename" || ProcessInfo.processInfo.environment["ONYX_BASES_EDIT"]?.lowercased() == "view"
    @State private var showAddColumn = ProcessInfo.processInfo.environment["ONYX_BASES_EDIT"]?.lowercased() == "column" || ProcessInfo.processInfo.environment["ONYX_BASES_EDIT"]?.lowercased() == "columns"
    @State private var showFilter = ProcessInfo.processInfo.environment["ONYX_BASES_EDIT"]?.lowercased() == "filter"
    @State private var columnQuery = ""
    @State private var filterProperty = ""
    @State private var filterOp = "eq"
    @State private var filterValue = ""
    @State private var hookArmed = false

    var path: String? { source == nil ? ws.currentPath : source!.path }
    var text: String { source?.text ?? ws.text }
    var canEdit: Bool { source == nil && path?.isBasePath == true }

    var body: some View {
        let file = Bases.parse(text)
        let idx = min(max(viewIndex, 0), max(file.views.count - 1, 0))
        let result = file.views.isEmpty ? emptyResult(file) : Bases.run(file, view: idx, in: ws.snapshot ?? VaultSnapshot(root: ws.root ?? URL(fileURLWithPath: "/tmp")), from: path)
        VStack(spacing: 0) {
            header(file: file, result: result, index: idx)
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
        .onChange(of: path) {
            viewIndex = 0
            if ProcessInfo.processInfo.environment["ONYX_BASES_EDIT"] == nil {
                showAddColumn = false; showFilter = false; showRename = false
            }
            armHook(file: file, index: 0)
        }
        .onAppear { armHook(file: file, index: idx) }
        .popover(isPresented: Binding(get: { !shotQuiet && showAddColumn }, set: { showAddColumn = $0 }), arrowEdge: .top) { addColumnPopover(file: file, index: idx) }
        .popover(isPresented: Binding(get: { !shotQuiet && showFilter }, set: { showFilter = $0 }), arrowEdge: .top) { filterPopover(file: file, index: idx) }
        .popover(isPresented: Binding(get: { !shotQuiet && showRename }, set: { showRename = $0 }), arrowEdge: .top) { renamePopover(file: file, index: idx) }
        // Off-screen screenshot runs can't capture a detached popover window; draw the
        // same panel inside this window when the edit hook is on.
        .overlay(alignment: .topTrailing) {
            if showFilter || showAddColumn || showRename {
                Group {
                    if showFilter { filterPopover(file: file, index: idx) }
                    else if showAddColumn { addColumnPopover(file: file, index: idx) }
                    else { renamePopover(file: file, index: idx) }
                }
                .frame(width: 280)
                .background(Color.paper)
                .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Color.ink.opacity(0.35), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .shadow(color: Color.black.opacity(0.18), radius: 16, y: 6)
                .padding(.top, 72)
                .padding(.trailing, 28)
            }
        }
    }

    var shotQuiet: Bool { ProcessInfo.processInfo.environment["ONYX_SHOT_QUIET"] == "1" }

    func emptyResult(_ file: BaseFile) -> BaseResult {
        let v = BaseView(type: "table", name: "Table", filters: .always, order: ["file.name"], sort: [], limit: nil, groupBy: nil, cardSize: nil, coverProperty: nil, indentProperties: false)
        return BaseResult(view: v, columns: [BaseColumn(key: "file.name", displayName: "Name")], rows: [], groups: nil, warnings: file.warnings, total: 0)
    }

    // MARK: Header

    func header(file: BaseFile, result: BaseResult, index: Int) -> some View {
        HStack(spacing: 10) {
            if file.views.count > 1 || canEdit {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(file.views.enumerated()), id: \.offset) { i, v in
                            Button {
                                viewIndex = i
                            } label: {
                                VStack(spacing: 3) {
                                    Text(v.name)
                                        .font(.system(size: 12, weight: i == index ? .medium : .regular))
                                        .foregroundStyle(i == index ? Color.ink : Color.muted)
                                    Rectangle().fill(i == index ? Color.ink.opacity(0.7) : Color.clear).frame(height: 1)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if canEdit {
                                    Button("Rename View…") { renaming = v.name; showRename = true; viewIndex = i }
                                    Button("Add Table View") { addView(type: "table") }
                                    Button("Add Cards View") { addView(type: "cards") }
                                }
                            }
                            .onTapGesture(count: 2) {
                                guard canEdit else { return }
                                viewIndex = i
                                renaming = v.name
                                showRename = true
                            }
                        }
                    }
                }
            } else {
                Text(file.name ?? result.view.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ink)
            }
            if canEdit {
                Menu {
                    Button("Table") { addView(type: "table") }
                    Button("Cards") { addView(type: "cards") }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.faint)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .frame(width: 18)
                .help("Add view")
                Button {
                    columnQuery = ""
                    showAddColumn = true
                } label: {
                    Text("Column")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.muted)
                }
                .buttonStyle(.plain)
                .help("Add a column")
                Button {
                    loadFilter(index: index)
                    showFilter = true
                } label: {
                    Text(hasSimpleFilter(index: index) ? "Filter" : "Filter…")
                        .font(.system(size: 11))
                        .foregroundStyle(hasSimpleFilter(index: index) ? Color.ink : Color.muted)
                }
                .buttonStyle(.plain)
                .help("Edit a simple filter")
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
                headerRow(r)
                if let groups = r.groups {
                    ForEach(groups) { g in
                        Text(g.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.muted)
                            .padding(.horizontal, 22)
                            .padding(.top, 14)
                            .padding(.bottom, 4)
                        if !g.summaries.isEmpty { summaryRow(g.summaries, columns: r.columns, grouped: true) }
                        ForEach(Array(g.rows.enumerated()), id: \.element.id) { i, row in
                            tableRow(row, columns: r.columns, alt: i % 2 == 1)
                        }
                    }
                    if !r.summaries.isEmpty { summaryRow(r.summaries, columns: r.columns, grouped: false) }
                } else {
                    ForEach(Array(r.rows.enumerated()), id: \.element.id) { i, row in
                        tableRow(row, columns: r.columns, alt: i % 2 == 1)
                    }
                    if !r.summaries.isEmpty { summaryRow(r.summaries, columns: r.columns, grouped: false) }
                }
            }
            .padding(.bottom, 40)
        }
    }

    func headerRow(_ r: BaseResult) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(r.columns.enumerated()), id: \.element.id) { i, c in
                let sorted = r.view.sort.first
                Button {
                    persistSort(key: c.key, current: sorted)
                } label: {
                    HStack(spacing: 4) {
                        Text(c.displayName)
                        if sorted?.property == c.key {
                            Image(systemName: sorted?.ascending == true ? "chevron.up" : "chevron.down")
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
                .contextMenu {
                    Button("Sort Ascending") { applyEdit { $0.setViewSort(index: viewIndex, [BaseSort(property: c.key, ascending: true)]) } }
                    Button("Sort Descending") { applyEdit { $0.setViewSort(index: viewIndex, [BaseSort(property: c.key, ascending: false)]) } }
                    Divider()
                    if canEdit {
                        Button("Add Column…") { columnQuery = ""; showAddColumn = true }
                        if i > 0 { Button("Move Left") { applyEdit { $0.moveColumn(view: viewIndex, from: i, to: i - 1) } } }
                        if i < r.columns.count - 1 { Button("Move Right") { applyEdit { $0.moveColumn(view: viewIndex, from: i, to: i + 1) } } }
                        Button("Remove Column", role: .destructive) { applyEdit { $0.removeColumn(view: viewIndex, key: c.key) } }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.hairline).frame(height: 1) }
    }

    func summaryRow(_ sums: [String: BaseValue], columns: [BaseColumn], grouped: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(columns) { c in
                let v = sums[c.key] ?? .null
                Text(v == .null ? "" : v.text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
            }
        }
        .padding(.horizontal, 14)
        .background(Color.paperAlt)
        .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: 1) }
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
                        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Color.hairline, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
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
        ws.openNote(row.path)   // attachments open in FileView
    }

    // MARK: Editing

    func persistSort(key: String, current: BaseSort?) {
        guard canEdit else { return }
        let ascending = current?.property == key ? !(current?.ascending ?? true) : true
        applyEdit { $0.setViewSort(index: viewIndex, [BaseSort(property: key, ascending: ascending)]) }
    }

    func addView(type: String) {
        let label = type == "cards" ? "Cards" : "Table"
        var name = label
        let existing = Set(Bases.parse(text).views.map(\.name))
        var n = 2
        while existing.contains(name) { name = "\(label) \(n)"; n += 1 }
        applyEdit { $0.addView(type: type, name: name) }
        // Select the new last view after the write.
        DispatchQueue.main.async { viewIndex = max(Bases.parse(ws.text).views.count - 1, 0) }
    }

    func hasSimpleFilter(index: Int) -> Bool {
        BaseDoc(text).simpleFilter(view: index) != nil
    }

    func loadFilter(index: Int) {
        if let f = BaseDoc(text).simpleFilter(view: index) {
            filterProperty = f.property
            filterOp = f.op
            filterValue = f.value
        } else {
            filterProperty = ""
            filterOp = "eq"
            filterValue = ""
        }
    }

    @ViewBuilder func addColumnPopover(file: BaseFile, index: Int) -> some View {
        let keys = BaseColumns.pickerKeys(in: ws.snapshot ?? VaultSnapshot(root: URL(fileURLWithPath: "/tmp")), file: file)
            .filter { q in
                let already = Set((file.views.indices.contains(index) ? file.views[index].order : []))
                if already.contains(q) { return false }
                if columnQuery.isEmpty { return true }
                return q.localizedCaseInsensitiveContains(columnQuery)
            }
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Column").font(.system(size: 12, weight: .medium))
            TextField("Property", text: $columnQuery)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(keys, id: \.self) { k in
                        Button {
                            applyEdit { $0.addColumn(view: index, key: k) }
                            showAddColumn = false
                        } label: {
                            Text(k)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 240)
        }
        .padding(12)
        .frame(width: 268)
    }

    @ViewBuilder func filterPopover(file: BaseFile, index: Int) -> some View {
        let keys = BaseColumns.pickerKeys(in: ws.snapshot ?? VaultSnapshot(root: URL(fileURLWithPath: "/tmp")), file: file)
        let ops: [(String, String)] = [
            ("eq", "is"), ("neq", "is not"),
            ("contains", "contains"), ("startswith", "starts with"), ("endswith", "ends with"),
            ("gt", "greater than"), ("gte", "at least"), ("lt", "less than"), ("lte", "at most"),
            ("isempty", "is empty"), ("isnotempty", "is not empty"),
        ]
        let needsValue = filterOp != "isempty" && filterOp != "isnotempty"
        VStack(alignment: .leading, spacing: 10) {
            Text("Filter").font(.system(size: 12, weight: .medium))
            Picker("Property", selection: $filterProperty) {
                Text("Property").tag("")
                ForEach(keys, id: \.self) { k in Text(k).tag(k) }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            Picker("Operator", selection: $filterOp) {
                ForEach(ops, id: \.0) { o in Text(o.1).tag(o.0) }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            if needsValue {
                TextField("Value", text: $filterValue)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                if hasSimpleFilter(index: index) {
                    Button("Clear") {
                        applyEdit { $0.clearSimpleFilter(view: index) }
                        showFilter = false
                    }
                }
                Spacer()
                Button("Apply") {
                    guard !filterProperty.isEmpty else { return }
                    applyEdit { $0.setSimpleFilter(view: index, property: filterProperty, operator: filterOp, value: needsValue ? filterValue : "") }
                    showFilter = false
                }
                .disabled(filterProperty.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    func renamePopover(file: BaseFile, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rename View").font(.system(size: 12, weight: .medium))
            TextField("Name", text: $renaming)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            HStack {
                Spacer()
                Button("Rename") {
                    let name = renaming.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    applyEdit { $0.setViewName(index: index, name) }
                    showRename = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }

    /// Apply a `BaseDoc` mutation, write it atomically, and register ⌘Z.
    func applyEdit(_ body: (inout BaseDoc) -> Bool) {
        guard canEdit else { return }
        var doc = BaseDoc(text)
        guard body(&doc), doc.text != text else { return }
        let old = ws.text
        let new = doc.text
        ws.text = new
        ws.flushSave()
        undoManager?.registerUndo(withTarget: ws) { target in
            let redo = target.text
            target.text = old
            target.flushSave()
            self.undoManager?.registerUndo(withTarget: target) { t in
                t.text = redo
                t.flushSave()
            }
        }
        undoManager?.setActionName("Edit Base")
    }

    /// Screenshot / test hook: `ONYX_BASES_EDIT=filter|column|rename` opens that popover after launch.
    /// Does not touch window autosave; use with `ONYX_SHOT_QUIET=1`.
    func armHook(file: BaseFile, index: Int) {
        guard !hookArmed, canEdit, let hook = ProcessInfo.processInfo.environment["ONYX_BASES_EDIT"]?.lowercased(), !hook.isEmpty else { return }
        hookArmed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            switch hook {
            case "filter":
                loadFilter(index: index)
                showFilter = true
            case "column", "columns":
                columnQuery = ""
                showAddColumn = true
            case "rename", "view":
                renaming = file.views.indices.contains(index) ? file.views[index].name : "View"
                showRename = true
            default:
                break
            }
        }
    }
}
