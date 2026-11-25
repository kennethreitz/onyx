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
    /// When set (version-history overlay), the reader renders a rich insert/delete diff instead of `text` alone.
    var richDiff: [NoteDiff.RichBlock]? = nil
    @Environment(\.colorScheme) var scheme
    // Observed so a Settings ▸ Typesetting change re-renders at once (values are read in Typeset).
    @AppStorage(Typeset.on) private var tsOn = true
    @AppStorage(Typeset.oldstyle) private var tsOldstyle = true
    @AppStorage(Typeset.hyphens) private var tsHyphens = true
    @AppStorage(Typeset.smallCaps) private var tsSmallCaps = true
    @AppStorage(Typeset.face) private var tsFace = "lm"
    @AppStorage(Typeset.opening) private var tsOpening = "smallcaps"
    @AppStorage(Typeset.justify) private var tsJustify = false
    @AppStorage(EditorPrefs.foldHeadings) private var foldHeadings = true

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
        if c.renderedToken != ws.renderToken || c.renderedPath != path || c.dark != dark || c.sidenotes != ws.sidenotes || c.renderedText != text || c.typeset != typeset || c.foldable != foldHeadings || c.renderedDiff != richDiff {
            let sameNote = c.renderedPath == path && c.renderedDiff == richDiff
            c.renderedToken = ws.renderToken; c.renderedPath = path; c.dark = dark; c.sidenotes = ws.sidenotes; c.renderedText = text; c.typeset = typeset; c.foldable = foldHeadings; c.renderedDiff = richDiff
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
        var foldable = true
        var renderedDiff: [NoteDiff.RichBlock]?

        /// Source lines of this note's folded headings (shared with the editor via FoldStore).
        func foldedLines(_ text: String, path: String) -> [Int] {
            guard foldable, !preview, let stored = ws.foldStore?.anchors(for: path), !stored.isEmpty else { return [] }
            return MarkdownFolds.regions(in: text).filter { $0.kind == .heading && stored.contains($0.anchor) }.map(\.line)
        }

        func pushFolds(for path: String) {
            guard renderedPath == path, let text = renderedText else { return }
            eval("Onyx.setFolds(\(foldedLines(text, path: path)))")
        }

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
            let payload = ReaderPayload.build(text: renderedText ?? "", path: path, snap: snap, dark: dark, sidenotes: sidenotes && !preview, keepScroll: keepScroll, line: keepScroll ? 0 : startLine, preview: preview, kanbanEditable: paneID == nil && !preview,
                                               typeset: Typeset.options(preview: preview),
                                               folds: foldedLines(renderedText ?? "", path: path), foldable: foldable && !preview, diff: renderedDiff)
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
                if let p = body["path"] as? String, !p.isEmpty, ws.snapshot?.notes[p] != nil || ws.snapshot?.attachments[p] != nil {
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
                    let items = snap.unlinkedMentions(of: p).map { [
                        "path": $0.source,
                        "name": snap.notes[$0.source]?.name ?? $0.source,
                        "text": ReaderPayload.snippet($0.context),
                        "line": $0.line,
                        "loc": $0.range.location,
                        "len": $0.range.length,
                        "matched": $0.matched,
                    ] as [String: Any] }
                    if let d = try? JSONSerialization.data(withJSONObject: items) { eval("Onyx.setUnlinked(\(String(decoding: d, as: UTF8.self)))") }
                }
            case "linkMention":
                if let source = body["path"] as? String, let loc = body["loc"] as? Int, let len = body["len"] as? Int, let target = renderedPath {
                    let matched = (body["matched"] as? String) ?? ""
                    let title = ws.snapshot?.notes[target]?.name ?? ((target as NSString).lastPathComponent as NSString).deletingPathExtension
                    ws.linkUnlinkedMention(UnlinkedMention(source: source, line: 0, context: "", range: NSRange(location: loc, length: len), matched: matched, needle: title), title: title)
                }
            case "url": if let s = body["url"] as? String, let u = URL(string: s) { NSWorkspace.shared.open(u) }
            case "tag":
                if let t = body["tag"] as? String { ws.revealTag(t) }
            case "task": if let i = body["index"] as? Int { ws.toggleTask(index: i) }
            case "dvtask":
                if !preview, let p = body["path"] as? String, let i = body["index"] as? Int {
                    ws.toggleDataviewTask(path: p, index: i)
                }
            case "folds":
                if let p = renderedPath, let text = renderedText, let lines = body["lines"] as? [Int] { ws.setReaderFolds(path: p, text: text, lines: lines) }
            case "imageSize":   // drag-to-resize: only the focused pane, and only the text it rendered
                guard paneID == nil, !preview, renderedPath == ws.currentPath, renderedText == ws.text,
                      let line = body["line"] as? Int, let kind = body["kind"] as? String, let target = body["target"] as? String else { return }
                ws.resizeEmbed(line: line, lines: body["lines"] as? Int ?? 1, kind: kind, target: target,
                               occurrence: body["occurrence"] as? Int ?? 0, width: (body["width"] as? NSNumber)?.intValue)
            case "edit": ws.toggleMode()
            case "top": if let l = body["line"] as? Double { ws.reportTop(paneID, l) }
            default: break
            }
        }
    }
}
