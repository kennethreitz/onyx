import AppKit
import SwiftUI
import WebKit
import UniformTypeIdentifiers
import OnyxCore

/// Serves bundled web assets at onyx://app/… and vault files at onyx://vault/…
final class OnyxSchemeHandler: NSObject, WKURLSchemeHandler {
    var vaultRoot: URL?
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let host = url.host else { return task.didFailWithError(URLError(.badURL)) }
        let rel = url.path.removingPercentEncoding ?? url.path
        let base: URL?
        switch host {
        case "app": base = AppResources.root
        case "vault": base = vaultRoot
        default: base = nil
        }
        guard let base else { return task.didFailWithError(URLError(.fileDoesNotExist)) }
        let file = base.appendingPathComponent(String(rel.drop(while: { $0 == "/" }))).standardizedFileURL
        guard file.path.hasPrefix(base.standardizedFileURL.path), let data = try? Data(contentsOf: file) else {
            return task.didFailWithError(URLError(.fileDoesNotExist))
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        // Audio and video need byte ranges (WebKit's media loader asks for them before it will play or seek).
        if mime.hasPrefix("audio/") || mime.hasPrefix("video/") {
            let range = AudioNote.byteRange(task.request.value(forHTTPHeaderField: "Range"), length: data.count)
            let body = range.map { data.subdata(in: $0) } ?? data
            var headers = ["Content-Type": mime, "Content-Length": "\(body.count)", "Accept-Ranges": "bytes"]
            if let r = range { headers["Content-Range"] = "bytes \(r.lowerBound)-\(r.upperBound - 1)/\(data.count)" }
            if let resp = HTTPURLResponse(url: url, statusCode: range == nil ? 200 : 206, httpVersion: "HTTP/1.1", headerFields: headers) {
                task.didReceive(resp)
                task.didReceive(body)
                task.didFinish()
                return
            }
        }
        task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: mime.hasPrefix("text") || mime.contains("javascript") ? "utf-8" : nil))
        task.didReceive(data)
        task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// Reading view: the note typeset like a LaTeX article (Reitz LaTeX), with
/// wikilinks, embeds, callouts, highlights, footnotes as Tufte sidenotes,
/// Mermaid as TikZ-ish figures, dataview-lite tables, embedded Bases, and kanban boards.
struct ReaderView: NSViewRepresentable {
    @Bindable var ws: Workspace
    var fontSize: Double = 19
    var measure: Double = 41
    /// Set for an unfocused split pane: render this note instead of the focused one.
    var source: (path: String?, text: String)? = nil
    /// The split pane this view belongs to when unfocused (nil = the focused pane).
    var paneID: UUID? = nil
    /// A hover preview: compact, no backlinks, no nested previews, never edits.
    var preview = false
    @Environment(\.colorScheme) var scheme
    // Observed so a Settings ▸ Typesetting change re-renders at once (values are read in Typeset).
    @AppStorage(Typeset.on) private var tsOn = true
    @AppStorage(Typeset.oldstyle) private var tsOldstyle = true
    @AppStorage(Typeset.hyphens) private var tsHyphens = true
    @AppStorage(Typeset.smallCaps) private var tsSmallCaps = true
    @AppStorage(Typeset.face) private var tsFace = "lm"
    @AppStorage(Typeset.opening) private var tsOpening = "smallcaps"
    @AppStorage(Typeset.justify) private var tsJustify = false

    var path: String? { source == nil ? ws.currentPath : source!.path }
    var text: String { source?.text ?? ws.text }

    func makeCoordinator() -> Coordinator {
        let c = Coordinator(ws: ws)
        c.paneID = paneID
        c.preview = preview
        c.startLine = preview ? 0 : ws.initialTop(paneID)   // open where this pane was (⌘↩ or a fresh split)
        c.scrollHandled = ws.scrollRequest?.id
        return c
    }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let handler = OnyxSchemeHandler()
        handler.vaultRoot = ws.root
        cfg.setURLSchemeHandler(handler, forURLScheme: "onyx")
        cfg.userContentController.add(context.coordinator, name: "onyx")
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.setValue(false, forKey: "drawsBackground")
        wv.navigationDelegate = context.coordinator
        wv.allowsMagnification = true
        context.coordinator.webView = wv
        context.coordinator.handler = handler
        wv.load(URLRequest(url: URL(string: "onyx://app/web/reader.html")!))
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        let c = context.coordinator
        c.ws = ws
        c.paneID = paneID
        c.handler?.vaultRoot = ws.root
        if source == nil && !preview { ws.liveReader = c }
        let dark = scheme == .dark
        let typeset = Typeset.signature
        if c.renderedToken != ws.renderToken || c.renderedPath != path || c.dark != dark || c.sidenotes != ws.sidenotes || c.renderedText != text || c.typeset != typeset {
            let sameNote = c.renderedPath == path
            c.renderedToken = ws.renderToken; c.renderedPath = path; c.dark = dark; c.sidenotes = ws.sidenotes; c.renderedText = text; c.typeset = typeset
            c.render(keepScroll: sameNote)
        }
        if c.typeKey != "\(fontSize)/\(measure)" {
            c.typeKey = "\(fontSize)/\(measure)"
            c.eval("Onyx.setType(\(fontSize), \(measure))")
        }
        if source == nil, let r = ws.scrollRequest, r.id != c.scrollHandled {
            c.scrollHandled = r.id
            c.eval("Onyx.scrollToLine(\(r.line))")
        }
        if source == nil, let j = ws.readerJump {
            c.eval("Onyx.scrollToHeading(\(j))")
            DispatchQueue.main.async { ws.readerJump = nil }
        }
        // A pane that first appears at 0×0 (a fresh split) may have flushed Onyx.render
        // before the web view had a size; without a second render the page stays blank.
        if c.ready, wv.bounds.width > 10, abs(c.lastLayoutWidth - wv.bounds.width) > 1 {
            let first = c.lastLayoutWidth < 10
            c.lastLayoutWidth = wv.bounds.width
            if first {
                c.eval("var p=document.getElementById('page'); if(p){p.classList.add('shown');p.classList.remove('instant');}")
                c.eval("Onyx.setType(\(fontSize), \(measure))")
            } else {
                c.eval("window.dispatchEvent(new Event('resize'))")
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var ws: Workspace
        weak var webView: WKWebView?
        var handler: OnyxSchemeHandler?
        var ready = false
        var pending: [String] = []
        var renderedToken = -1
        var renderedPath: String?
        var renderedText: String?
        var dark = false
        var sidenotes = true
        var typeKey = ""
        var typeset = ""
        var paneID: UUID?
        var preview = false
        var startLine: Double = 0
        var scrollHandled: Int?
        var lastLayoutWidth: CGFloat = 0

        init(ws: Workspace) { self.ws = ws }

        func eval(_ js: String) {
            guard ready else {
                if js.hasPrefix("Onyx.render(") { pending.removeAll { $0.hasPrefix("Onyx.render(") } }
                pending.append(js); return
            }
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        func evalResult(_ js: String, _ done: @escaping (Any?) -> Void) {
            guard ready, let webView else { done(nil); return }
            webView.evaluateJavaScript(js) { v, _ in done(v) }
        }

        /// The current reader selection, or "" if there isn't one (or the view isn't ready).
        func selectedText(_ done: @escaping (String) -> Void) {
            evalResult("(window.getSelection && window.getSelection().toString()) || ''") { v in
                done((v as? String) ?? "")
            }
        }

        func render(keepScroll: Bool) {
            guard let snap = ws.snapshot, let path = renderedPath else { return }
            let payload = ReaderPayload.build(text: renderedText ?? "", path: path, snap: snap, dark: dark, sidenotes: sidenotes && !preview, keepScroll: keepScroll, line: keepScroll ? 0 : startLine, preview: preview, kanbanEditable: paneID == nil && !preview)
            startLine = 0   // only the first render of this view restores
            eval("Onyx.render(\(payload))")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            for p in pending { webView.evaluateJavaScript(p, completionHandler: nil) }
            pending = []
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let u = action.request.url, action.navigationType == .linkActivated {
                if u.scheme == "http" || u.scheme == "https" || u.scheme == "mailto" || u.scheme == "obsidian" { NSWorkspace.shared.open(u) }
                return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        }

        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            if preview, !["open", "url", "tag"].contains(type) { return }   // a preview only navigates
            switch type {
            case "open":
                if let p = body["path"] as? String, !p.isEmpty, ws.snapshot?.notes[p] != nil || ws.snapshot?.canvases[p] != nil {
                    GraphPreviewController.shared.close()
                    if let line = body["line"] as? Int { ws.openNote(p, line: line) }
                    else { ws.openNote(p, heading: body["heading"] as? String) }
                } else if let t = body["target"] as? String { ws.openLink(t) }
            case "preview":
                if let p = body["path"] as? String, !p.isEmpty, let webView,
                   let x = body["x"] as? Double, let y = body["y"] as? Double,
                   let w = body["width"] as? Double, let h = body["height"] as? Double {
                    let rect = CGRect(x: x, y: webView.isFlipped ? y : webView.bounds.height - y - h, width: w, height: h)
                    let h = (body["heading"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    GraphPreviewController.shared.schedule(ws: ws, path: p, rect: rect, in: webView, mode: nil, heading: h)
                }
            case "previewEnd": GraphPreviewController.shared.leaveLink()
            case "kanban":   // only the focused pane's board edits (it owns ws.text)
                if paneID == nil, !preview { ws.kanbanEdit(body) }
            case "findCount":   // a re-render re-applied the find marks
                if ws.liveReader === self, ws.finder.visible { ws.finder.count = body["count"] as? Int ?? 0; ws.finder.index = body["index"] as? Int ?? 0 }
            case "unlinked":
                if let snap = ws.snapshot, let p = renderedPath {
                    let items = snap.unlinkedMentions(of: p).map { ["path": $0.source, "name": snap.notes[$0.source]?.name ?? $0.source, "text": ReaderPayload.snippet($0.context)] }
                    if let d = try? JSONSerialization.data(withJSONObject: items) { eval("Onyx.setUnlinked(\(String(decoding: d, as: UTF8.self)))") }
                }
            case "url": if let s = body["url"] as? String, let u = URL(string: s) { NSWorkspace.shared.open(u) }
            case "tag":
                if let t = body["tag"] as? String { ws.searchQuery = "tag:" + t; ws.sidebarTab = .search; if !ws.sidebarVisible { ws.toggleSidebar() } }
            case "task": if let i = body["index"] as? Int { ws.toggleTask(index: i) }
            case "dvtask":
                if !preview, let p = body["path"] as? String, let i = body["index"] as? Int {
                    ws.toggleDataviewTask(path: p, index: i)
                }
            case "edit": ws.toggleMode()
            case "top": if let l = body["line"] as? Double { ws.reportTop(paneID, l) }
            default: break
            }
        }
    }
}

/// Everything the page needs, resolved Swift-side so JS never touches the disk.
enum ReaderPayload {
    static let fence = try! NSRegularExpression(pattern: #"(?m)^```(dataviewjs|dataview|base)[^\n]*\n([\s\S]*?)\n```[ \t]*$"#)

    static func build(text: String, path: String, snap: VaultSnapshot, dark: Bool, sidenotes: Bool, keepScroll: Bool, line: Double = 0, preview: Bool = false, kanbanEditable: Bool = false, typeset: [String: Any]? = nil, backlinks: Bool = true) -> String {
        let fm = Frontmatter.parse(text)
        var body = fieldsHTML(text, path: path, snap: snap)
        // Dataview blocks become placeholders, computed here.
        var dv: [String] = []
        let ns = body as NSString
        var out = ""
        var last = 0
        for m in fence.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            // Same number of lines as the fence it replaces, so source-line anchors stay true.
            let fenceLines = ns.substring(with: m.range).filter { $0 == "\n" }.count
            out += "<div class=\"onyx-dataview\" data-i=\"\(dv.count)\"></div>" + String(repeating: "\n", count: fenceLines)
            let lang = ns.substring(with: m.range(at: 1))
            let query = ns.substring(with: m.range(at: 2))
            if lang == "dataviewjs" {
                switch DataviewJS.run(query, in: snap, from: path) {
                case .html(let h): dv.append(h)
                case .error(let e): dv.append("<div class=\"dataview-error\"><span>dataviewjs</span> \(esc(e))<pre>\(esc(query))</pre></div>")
                }
            } else {
                dv.append(lang == "base" ? baseHTML(query, snap: snap, path: path) : dataviewHTML(query, snap: snap, path: path))
            }
            last = NSMaxRange(m.range)
        }
        out += ns.substring(from: last)
        body = out
        let inline = Dataview.rewriteInlineQueries(body, in: snap, from: path)
        body = inline.text
        let dvinline = inline.html

        var links: [String: [String: String]] = [:]
        var embeds: [String: [String: String]] = [:]
        func resolveAll(_ s: String, from: String, depth: Int) {
            for l in NoteParser.parseWikiLinks(s) {
                let key = l.target.lowercased()
                let resolved = snap.resolve(l.target, from: from)
                links[key] = ["path": resolved ?? "", "name": l.target]
                if l.isEmbed, embeds[key] == nil, let r = resolved {
                    if let note = snap.notes[r] {
                        var md = (note.content as NSString).substring(from: note.summary.frontmatter.bodyOffset)
                        if let h = l.heading { md = section(md, heading: h) }
                        let pretty = l.heading == nil ? fieldsHTML(note.content, path: r, snap: snap) : fieldsHTML(md, path: r, snap: snap)
                        embeds[key] = ["type": "note", "path": r, "markdown": pretty, "name": note.name]
                        if depth < 1 { resolveAll(md, from: r, depth: depth + 1) }
                    } else {
                        let ext = (r as NSString).pathExtension.lowercased()
                        let kind = ["png", "jpg", "jpeg", "gif", "webp", "svg", "avif", "heic", "bmp"].contains(ext) ? "image" : (ext == "pdf" ? "pdf" : (["mp3", "m4a", "wav", "ogg", "flac"].contains(ext) ? "audio" : (["mp4", "mov", "webm"].contains(ext) ? "video" : "file")))
                        embeds[key] = ["type": kind, "path": r, "url": "onyx://vault/" + (r.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? r)]
                    }
                }
            }
        }
        resolveAll(body, from: path, depth: 0)

        let fields = InlineFields.parse(text)
        let props = fm.properties.map { p -> [String: String] in
            let fs = fields.filter { $0.isFrontmatter && $0.key == p.key }
            let html = fs.isEmpty ? "" : fs.map { fieldValueHTML($0, path: path, snap: snap) }.joined(separator: " ")
            return ["key": InlineField.kind(p.key) == "partof" ? "Part of" : p.key, "value": p.value.display, "html": html]
        }
        var kanban: Any = NSNull()
        if KanbanBoard.isBoard(fm) {
            let d = KanbanDoc(text)   // the same indices the edit operations use
            let folded = d.collapsed
            kanban = d.lanes.enumerated().map { i, l in ["title": l.title, "collapsed": folded[i], "cards": l.cards.map { ["text": d.cardText($0), "done": $0.done] }] as [String: Any] }
        }
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let folder = (path as NSString).deletingLastPathComponent
        // Backlinks under the note, like Obsidian's backlinkInDocument (unlinked load on demand).
        let mentions: [[String: Any]] = preview || !backlinks ? [] : snap.linkedMentions(to: path).map { m in
            ["path": m.source, "name": snap.notes[m.source]?.name ?? ((m.source as NSString).lastPathComponent as NSString).deletingPathExtension, "folder": (m.source as NSString).deletingLastPathComponent,
             "lines": m.lines.map { ["line": $0.line, "text": snippet($0.context)] as [String: Any] }]
        }
        let obj: [String: Any] = [
            "backlinks": mentions,
            "markdown": body, "path": path, "name": name, "folder": folder,
            "links": links, "embeds": embeds, "dataview": dv, "dvinline": dvinline, "props": props, "kanban": kanban,
            "dark": dark, "sidenotes": sidenotes, "keepScroll": keepScroll, "preview": preview, "kanbanEditable": kanbanEditable,
            "typeset": typeset ?? Typeset.options(preview: preview),
            "lineBase": fm.bodyOffset > 0 ? fm.lineCount : 0, "line": line,
            "base": "onyx://vault/" + (folder.isEmpty ? "" : (folder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? folder) + "/"),
        ]
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// All markup here is generated and escaped; note values never become executable HTML.
    static func fieldLinkHTML(_ l: WikiLink, path: String, snap: VaultSnapshot) -> String {
        let resolved = snap.resolve(l.target, from: path) ?? ""
        let label = l.alias ?? ((l.target as NSString).lastPathComponent as NSString).deletingPathExtension
        return "<a class=\"internal-link field-chip\(resolved.isEmpty ? " is-unresolved" : "")\" data-path=\"\(esc(resolved))\" data-target=\"\(esc(l.target))\" data-heading=\"\(esc(l.heading ?? ""))\">\(esc(label))</a>"
    }
    static func fieldValueHTML(_ f: InlineField, path: String, snap: VaultSnapshot) -> String {
        if InlineField.isRelation(f.key) { return f.links.map { fieldLinkHTML($0, path: path, snap: snap) }.joined(separator: " ") }
        let ns = f.value as NSString
        var last = 0, html = ""
        for l in f.links.sorted(by: { $0.range.location < $1.range.location }) {
            let start = l.range.location - f.valueRange.location
            guard start >= last, start + l.range.length <= ns.length else { continue }
            html += esc(ns.substring(with: NSRange(location: last, length: start - last)))
            html += fieldLinkHTML(l, path: path, snap: snap)
            last = start + l.range.length
        }
        return html + esc(ns.substring(from: last))
    }
    static func fieldsHTML(_ text: String, path: String, snap: VaultSnapshot) -> String {
        let fm = Frontmatter.parse(text)
        var ns = text as NSString
        for f in InlineFields.parse(text).filter({ !$0.isFrontmatter }).reversed() {
            let atLine = f.range.location == 0 || ns.character(at: f.range.location - 1) == 10
            let html = "<span class=\"inline-field\(atLine ? " is-line" : "") field-\(esc(f.kind))\"><span class=\"field-key\">\(esc(f.label))</span> \(fieldValueHTML(f, path: path, snap: snap))</span>"
            ns = ns.replacingCharacters(in: f.range, with: html) as NSString
        }
        return ns.substring(from: fm.bodyOffset)
    }

    /// One line of context: inline markup stripped, long lines cut to a readable length.
    static func snippet(_ line: String) -> String {
        // [[path|Alias]] reads as "Alias", [[Folder/Note]] as "Note", before the usual inline stripping
        var t = line.trimmingCharacters(in: .whitespaces)
        t = t.replacingOccurrences(of: #"!?\[\[[^\]|]*\|([^\]]+)\]\]"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"!?\[\[(?:[^\]#]*/)?([^\]/#]+?)(?:#[^\]]*)?\]\]"#, with: "$1", options: .regularExpression)
        t = NoteParser.stripInline(t)
        if t.hasPrefix("|") { t = t.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " · ") }   // table rows
        t = t.replacingOccurrences(of: #"^([-*+]|\d+[.)]|#+|>)\s+"#, with: "", options: .regularExpression)
        return t.count > 240 ? String(t.prefix(239)) + "…" : t
    }

    static func section(_ md: String, heading: String) -> String {
        let lines = md.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { l in l.hasPrefix("#") && NoteParser.stripInline(l.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)).lowercased() == heading.lowercased() }) else { return md }
        let level = lines[start].prefix { $0 == "#" }.count
        var end = lines.count
        for i in (start + 1)..<lines.count where lines[i].hasPrefix("#") {
            let lv = lines[i].prefix { $0 == "#" }.count
            if lv <= level && lines[i].dropFirst(lv).hasPrefix(" ") { end = i; break }
        }
        return lines[start..<end].joined(separator: "\n")
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func cell(_ v: DVValue) -> String {
        switch v {
        case .link(let p, let n): return "<a class=\"internal-link\" data-path=\"\(esc(p))\">\(esc(n))</a>"
        case .list(let l): return l.map(cell).joined(separator: ", ")
        case .task(let t): return esc(t.text)
        case .string(let s):
            if s.hasPrefix("[["), s.hasSuffix("]]") { return "<span class=\"onyx-inline-md\">\(esc(s))</span>" }
            return "<span class=\"onyx-inline-md\">\(esc(s))</span>"
        default: return esc(v.text)
        }
    }

    static func taskItem(_ t: DVTask) -> String {
        let checked = t.completed ? " checked" : ""
        return "<li class=\"task-list-item\(t.completed ? " is-checked" : "")\"><input type=\"checkbox\" data-dv-task data-path=\"\(esc(t.path))\" data-index=\"\(t.indexInFile)\"\(checked)>\(esc(t.text))</li>"
    }

    static func taskHTML(_ r: DVResult) -> String {
        if r.taskGroups.allSatisfy({ $0.tasks.isEmpty }) { return "<p class=\"dataview-empty\">No tasks.</p>" }
        let groups = r.taskGroups.filter { !$0.tasks.isEmpty }.map { g -> String in
            let title = "<div class=\"dataview-task-title\">\(cell(g.heading))</div>"
            return "<div class=\"dataview-task-group\">\(title)<ul class=\"dataview-list dataview-tasks\">" + g.tasks.map(taskItem).joined() + "</ul></div>"
        }.joined()
        return "<div class=\"dataview-task-list\">\(groups)</div>"
    }

    static func calendarHTML(_ r: DVResult) -> String {
        if r.calendar.isEmpty { return "<p class=\"dataview-empty\">No results.</p>" }
        let cal = Calendar.current
        let symbols = cal.veryShortWeekdaySymbols
        let first = cal.firstWeekday  // 1 = Sunday
        let weekdays = (0..<7).map { symbols[($0 + first - 1) % 7] }
        let months = r.calendar.map { mon -> String in
            var comps = DateComponents(); comps.year = mon.year; comps.month = mon.month; comps.day = 1
            let start = cal.date(from: comps) ?? Date()
            let fmt = DateFormatter(); fmt.calendar = cal; fmt.locale = .current; fmt.setLocalizedDateFormatFromTemplate("MMMM yyyy")
            let caption = fmt.string(from: start)
            let weekdayRow = weekdays.map { "<span>\(esc($0))</span>" }.joined()
            let pad = ((cal.component(.weekday, from: start) - first) + 7) % 7
            let dim = cal.range(of: .day, in: .month, for: start)?.count ?? 30
            var cells = Array(repeating: "<span class=\"dv-cal-day is-pad\"></span>", count: pad)
            for d in 1...dim {
                let notes = mon.days[d] ?? []
                if notes.isEmpty {
                    cells.append("<span class=\"dv-cal-day\">\(d)</span>")
                } else {
                    let dots = notes.map { v -> String in
                        if case .link(let p, let n) = v {
                            return "<a class=\"internal-link dv-cal-dot\" data-path=\"\(esc(p))\" title=\"\(esc(n))\">•</a>"
                        }
                        return "<span class=\"dv-cal-dot\" title=\"\(esc(v.text))\">•</span>"
                    }.joined()
                    cells.append("<span class=\"dv-cal-day has-notes\">\(d)<span class=\"dv-cal-dots\">\(dots)</span></span>")
                }
            }
            return "<div class=\"dv-cal-month\"><div class=\"dv-cal-caption\">\(esc(caption))</div><div class=\"dv-cal-weekdays\">\(weekdayRow)</div><div class=\"dv-cal-grid\">\(cells.joined())</div></div>"
        }.joined()
        return "<div class=\"dataview-calendar\">\(months)</div>"
    }

    static func dataviewHTML(_ query: String, snap: VaultSnapshot, path: String) -> String {
        do {
            return Dataview.html(try Dataview.run(query, in: snap, from: path))
        } catch {
            return "<div class=\"dataview-error\"><span>dataview</span> \(esc(String(describing: error)))<pre>\(esc(query))</pre></div>"
        }
    }

    static func baseHTML(_ yaml: String, snap: VaultSnapshot, path: String) -> String {
        let file = Bases.parse(yaml)
        let r = file.views.isEmpty ? nil : Bases.run(file, view: 0, in: snap, from: path)
        var html = ""
        let warnings = file.warnings + (r?.warnings ?? [])
        if !warnings.isEmpty {
            html += "<div class=\"dataview-error\"><span>base</span> \(esc(warnings.joined(separator: " ")))</div>"
        }
        guard let r else { return html + "<p class=\"dataview-empty\">This base has no views.</p>" }
        if file.views.count > 1 {
            html += "<p class=\"dataview-empty\">\(esc(r.view.name)) · \(file.views.count) views</p>"
        }
        if r.rows.isEmpty { return html + "<p class=\"dataview-empty\">No results.</p>" }
        if r.view.type == "cards" {
            let cards = r.rows.map { row -> String in
                let title = "<a class=\"internal-link\" data-path=\"\(esc(row.path))\">\(esc(row.name))</a>"
                let props = r.columns.filter { $0.key != "file.name" && $0.key != "note.name" }.compactMap { c -> String? in
                    let t = row.cells[c.key]?.text ?? ""
                    return t.isEmpty ? nil : "<div>\(esc(t))</div>"
                }.joined()
                var cover = ""
                if let p = row.coverPath {
                    let url = "onyx://vault/" + (p.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? p)
                    cover = "<img src=\"\(url)\" alt=\"\">"
                }
                return "<div class=\"base-card\">\(cover)<div>\(title)\(props)</div></div>"
            }.joined()
            return html + "<div class=\"base-cards\">\(cards)</div>"
        }
        if r.view.type == "list" {
            let items = r.rows.map { "<li><a class=\"internal-link\" data-path=\"\(esc($0.path))\">\(esc($0.name))</a></li>" }.joined()
            return html + "<ul class=\"dataview-list\">\(items)</ul>"
        }
        let head = "<thead><tr>" + r.columns.map { "<th>\(esc($0.displayName))</th>" }.joined() + "</tr></thead>"
        let rows = r.rows.map { row in
            "<tr>" + r.columns.map { c in
                let v = row.cells[c.key] ?? .null
                let label = v.text.isEmpty ? row.name : v.text
                if c.key == "file.name" || c.key == "note.name" || c.key == r.columns.first?.key {
                    return "<td><a class=\"internal-link\" data-path=\"\(esc(row.path))\">\(esc(label))</a></td>"
                }
                return "<td>\(esc(v.text))</td>"
            }.joined() + "</tr>"
        }.joined()
        return html + "<div class=\"table-wrap\"><table class=\"dataview\">\(head)<tbody>\(rows)</tbody></table></div>"
    }
}
