import AppKit
import SwiftUI
import WebKit
import OnyxCore

/// Obsidian Canvas (.canvas, JSON Canvas 1.0). The page (Resources/web/canvas.js) owns the
/// board: pan, zoom, selection and editing. Swift resolves everything on disk (notes in file
/// cards, images, links in text cards) and writes the file back in Obsidian's own layout, so
/// unknown fields, ids and formatting survive and Obsidian reads it unchanged.
struct CanvasView: NSViewRepresentable {
    @Bindable var ws: Workspace
    /// Set for an unfocused split pane: show this canvas read-only.
    var source: (path: String?, text: String)? = nil
    @Environment(\.colorScheme) var scheme

    var path: String? { source == nil ? ws.currentPath : source!.path }
    var text: String { source?.text ?? ws.text }

    func makeCoordinator() -> Coordinator { Coordinator(ws: ws) }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let handler = OnyxSchemeHandler()
        handler.vaultRoot = ws.root
        cfg.setURLSchemeHandler(handler, forURLScheme: "onyx")
        cfg.userContentController.add(context.coordinator, name: "onyx")
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.setValue(false, forKey: "drawsBackground")
        wv.navigationDelegate = context.coordinator
        wv.allowsMagnification = false       // pinch zooms the board, not the page
        wv.allowsBackForwardNavigationGestures = false
        context.coordinator.webView = wv
        context.coordinator.handler = handler
        wv.load(URLRequest(url: URL(string: "onyx://app/web/canvas.html")!))
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        let c = context.coordinator
        c.ws = ws
        c.handler?.vaultRoot = ws.root
        c.editable = source == nil
        let dark = scheme == .dark
        if c.path != path || c.dark != dark || (c.text != text && c.posted != text) {
            let samePath = c.path == path
            c.path = path; c.dark = dark; c.text = text
            c.load(keepView: samePath)
        } else if c.snapshotGen != ws.snapshotGen {
            c.refreshFiles()
        }
        if c.sentEditable != c.editable { c.sentEditable = c.editable; c.eval("Onyx.canvasSetEditable(\(c.editable))") }
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var ws: Workspace
        weak var webView: WKWebView?
        var handler: OnyxSchemeHandler?
        var ready = false
        var pending: [String] = []
        var path: String?
        var text: String?
        var posted: String?          // the last text this page saved (so it isn't sent back)
        var dark = false
        var editable = true
        var sentEditable: Bool?
        var snapshotGen = -1

        init(ws: Workspace) { self.ws = ws }

        func eval(_ js: String) {
            guard ready else {
                if js.hasPrefix("Onyx.canvasLoad(") { pending.removeAll { $0.hasPrefix("Onyx.canvasLoad(") } }
                pending.append(js); return
            }
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        func load(keepView: Bool) {
            guard let snap = ws.snapshot, let path else { return }
            snapshotGen = ws.snapshotGen
            posted = nil
            let payload = CanvasPayload.build(text: text ?? "", path: path, snap: snap, dark: dark, editable: editable, keepView: keepView)
            eval("Onyx.canvasLoad(\(payload))")
        }

        /// The vault changed (a note shown in a card was edited): refresh the cards only.
        func refreshFiles() {
            guard let snap = ws.snapshot, let path else { return }
            snapshotGen = ws.snapshotGen
            eval("Onyx.canvasRefresh(\(CanvasPayload.json(CanvasPayload.resolved(text: text ?? "", path: path, snap: snap, dark: dark))))")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            for p in pending { webView.evaluateJavaScript(p, completionHandler: nil) }
            pending = []
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let u = action.request.url, action.navigationType == .linkActivated {
                if ["http", "https", "mailto", "obsidian"].contains(u.scheme ?? "") { NSWorkspace.shared.open(u) }
                return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        }

        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "save":
                // Only the focused pane's canvas is live; JS sends JSON.stringify(doc).
                guard editable, let json = body["json"] as? String, let p = path, p == ws.currentPath,
                      let formatted = try? CanvasFile.normalize(json) else { return }
                posted = formatted; text = formatted
                if ws.text != formatted { ws.text = formatted }
            case "openFile":
                guard let p = body["path"] as? String, !p.isEmpty else { return }
                if ws.snapshot?.notes[p] != nil || ws.snapshot?.canvases[p] != nil { ws.openNote(p) }
                else if let r = ws.root, FileManager.default.fileExists(atPath: r.appendingPathComponent(p).path) { NSWorkspace.shared.open(r.appendingPathComponent(p)) }
            case "open":
                if let p = body["path"] as? String, !p.isEmpty, ws.snapshot?.notes[p] != nil { ws.openNote(p, heading: body["heading"] as? String) }
                else if let t = body["target"] as? String, !t.isEmpty { ws.openLink(t, from: path) }
            case "preview":
                if let p = body["path"] as? String, !p.isEmpty, let webView,
                   let x = body["x"] as? Double, let y = body["y"] as? Double,
                   let w = body["width"] as? Double, let h = body["height"] as? Double {
                    let rect = CGRect(x: x, y: webView.isFlipped ? y : webView.bounds.height - y - h, width: w, height: h)
                    GraphPreviewController.shared.schedule(ws: ws, path: p, rect: rect, in: webView)
                }
            case "previewEnd": GraphPreviewController.shared.leaveLink()
            case "url": if let s = body["url"] as? String, let u = URL(string: s), ["http", "https", "mailto", "obsidian"].contains(u.scheme ?? "") { NSWorkspace.shared.open(u) }
            case "tag":
                if let t = body["tag"] as? String { ws.searchQuery = "tag:" + t; ws.sidebarTab = .search; if !ws.sidebarVisible { ws.toggleSidebar() } }
            case "search":   // the "Add note…" picker, through the ⌘O matcher
                let q = body["q"] as? String ?? "", id = body["id"] as? Int ?? 0
                var rows: [[String: String]] = []
                if q.trimmingCharacters(in: .whitespaces).isEmpty {
                    rows = ws.recent.filter { $0 != path && ws.snapshot?.notes[$0] != nil }.prefix(20).map(CanvasPayload.row)
                } else {
                    rows = ws.quickIndex.search(q, recent: ws.recent, limit: 40).map(\.entry.path).filter { $0 != path }.prefix(20).map(CanvasPayload.row)
                }
                eval("Onyx.canvasPickResults(\(id), \(CanvasPayload.json(rows)))")
            case "needFiles":
                guard let snap = ws.snapshot, let p = path, let refs = body["files"] as? [[String: String]] else { return }
                let files = CanvasPayload.files(for: refs.compactMap { r in r["file"].map { ($0, r["subpath"] ?? "") } }, canvas: p, snap: snap)
                eval("Onyx.canvasFiles(\(CanvasPayload.json(files)))")
            case "toast": if let t = body["text"] as? String { ws.toast = t }
            default: break
            }
        }
    }
}

/// What the canvas page needs, resolved Swift-side so JS never touches the disk.
enum CanvasPayload {
    static func json(_ o: Any) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: o)) ?? Data("null".utf8), as: UTF8.self)
    }
    static func row(_ p: String) -> [String: String] {
        ["path": p, "name": ((p as NSString).lastPathComponent as NSString).deletingPathExtension, "folder": (p as NSString).deletingLastPathComponent]
    }

    /// File cards as (file, subpath) pairs.
    static func fileRefs(_ text: String) -> [(String, String)] {
        guard let v = try? CanvasFile.parse(text) else { return [] }
        return (v["nodes"]?.array ?? []).compactMap { n in
            n["type"]?.string == "file" ? n["file"]?.string.map { ($0, n["subpath"]?.string ?? "") } : nil
        }
    }

    static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "avif", "heic", "bmp"]

    /// Keyed by "file" + "subpath" exactly as the canvas stores them.
    static func files(for refs: [(String, String)], canvas: String, snap: VaultSnapshot) -> [String: Any] {
        var out: [String: Any] = [:]
        for (file, sub) in refs {
            let key = file + sub
            guard out[key] == nil else { continue }
            let resolved = snap.notes[file] != nil || snap.attachments[file] != nil ? file : snap.resolve(file, from: canvas)
            guard let r = resolved else { out[key] = ["type": "missing", "path": file, "name": (file as NSString).lastPathComponent]; continue }
            let name = ((r as NSString).lastPathComponent as NSString).deletingPathExtension
            let url = "onyx://vault/" + (r.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? r)
            if let note = snap.notes[r] {
                var text = note.content
                if sub.hasPrefix("#"), !sub.hasPrefix("#^") {
                    let body = (note.content as NSString).substring(from: note.summary.frontmatter.bodyOffset)
                    text = ReaderPayload.section(body, heading: String(sub.dropFirst()))
                }
                let reader = ReaderPayload.build(text: text, path: r, snap: snap, dark: false, sidenotes: false, keepScroll: false)
                let obj = (try? JSONSerialization.jsonObject(with: Data(reader.utf8))) as? [String: Any] ?? [:]
                out[key] = ["type": "note", "path": r, "name": name, "reader": obj]
            } else if r.isCanvasPath {
                let s = snap.canvases[r]
                out[key] = ["type": "canvas", "path": r, "name": name, "detail": "\(s?.nodeCount ?? 0) cards · \(s?.edgeCount ?? 0) connections"]
            } else {
                let ext = (r as NSString).pathExtension.lowercased()
                let kind = imageExts.contains(ext) ? "image" : ext == "pdf" ? "pdf" : ["mp3", "m4a", "wav", "ogg", "flac"].contains(ext) ? "audio" : ["mp4", "mov", "webm"].contains(ext) ? "video" : "file"
                out[key] = ["type": kind, "path": r, "name": (r as NSString).lastPathComponent, "url": url]
            }
        }
        return out
    }

    /// File cards plus the links and embeds written in text cards.
    static func resolved(text: String, path: String, snap: VaultSnapshot, dark: Bool) -> [String: Any] {
        var texts: [String] = []
        if let v = try? CanvasFile.parse(text) {
            for n in v["nodes"]?.array ?? [] where n["type"]?.string == "text" { if let t = n["text"]?.string { texts.append(t) } }
        }
        // links and embeds inside text cards resolve like a note sitting next to the canvas
        let reader = ReaderPayload.build(text: texts.joined(separator: "\n\n"), path: path, snap: snap, dark: dark, sidenotes: false, keepScroll: false)
        let r = (try? JSONSerialization.jsonObject(with: Data(reader.utf8))) as? [String: Any] ?? [:]
        return ["links": r["links"] ?? [:], "embeds": r["embeds"] ?? [:], "base": r["base"] ?? "",
                "files": files(for: fileRefs(text), canvas: path, snap: snap)]
    }

    static func build(text: String, path: String, snap: VaultSnapshot, dark: Bool, editable: Bool, keepView: Bool) -> String {
        var obj = resolved(text: text, path: path, snap: snap, dark: dark)
        obj["json"] = text; obj["path"] = path; obj["name"] = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        obj["dark"] = dark; obj["editable"] = editable; obj["keepView"] = keepView
        return json(obj)
    }
}
