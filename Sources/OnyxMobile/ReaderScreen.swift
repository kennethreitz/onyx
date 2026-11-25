import SwiftUI
import WebKit
import UniformTypeIdentifiers
import OnyxCore

/// Serves bundled reader assets at `onyx://app/…` and vault files at `onyx://vault/…`.
final class MobileSchemeHandler: NSObject, WKURLSchemeHandler {
    var vaultRoot: URL?
    var resourcesRoot: URL

    init(resourcesRoot: URL, vaultRoot: URL? = nil) {
        self.resourcesRoot = resourcesRoot
        self.vaultRoot = vaultRoot
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let host = url.host else {
            return task.didFailWithError(URLError(.badURL))
        }
        let rel = url.path.removingPercentEncoding ?? url.path
        let base: URL?
        switch host {
        case "app": base = resourcesRoot
        case "vault": base = vaultRoot
        default: base = nil
        }
        guard let base else { return task.didFailWithError(URLError(.fileDoesNotExist)) }
        let file = base.appendingPathComponent(String(rel.drop(while: { $0 == "/" }))).standardizedFileURL
        guard file.path.hasPrefix(base.standardizedFileURL.path), let data = try? Data(contentsOf: file) else {
            return task.didFailWithError(URLError(.fileDoesNotExist))
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
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
        let encoding = (mime.hasPrefix("text") || mime.contains("javascript") || mime.contains("css")) ? "utf-8" : nil
        task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: encoding))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

enum MobileResources {
    /// Folder that contains `web/reader.html` and `fonts/`.
    static var root: URL {
        if let r = Bundle.main.resourceURL {
            if FileManager.default.fileExists(atPath: r.appendingPathComponent("web/reader.html").path) { return r }
            let nested = r.appendingPathComponent("OnyxResources")
            if FileManager.default.fileExists(atPath: nested.appendingPathComponent("web/reader.html").path) { return nested }
        }
        return Bundle.main.bundleURL
    }
}

/// Typeset reading view: the same `Resources/web` page as macOS, fed by `ReaderPayload`.
struct ReaderScreen: UIViewRepresentable {
    var note: NoteRecord
    var snapshot: VaultSnapshot
    var vaultRoot: URL
    var dark: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let handler = MobileSchemeHandler(resourcesRoot: MobileResources.root, vaultRoot: vaultRoot)
        cfg.setURLSchemeHandler(handler, forURLScheme: "onyx")
        cfg.userContentController.add(context.coordinator, name: "onyx")
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear
        wv.navigationDelegate = context.coordinator
        context.coordinator.webView = wv
        context.coordinator.handler = handler
        wv.load(URLRequest(url: URL(string: "onyx://app/web/reader.html")!))
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        let c = context.coordinator
        c.handler?.vaultRoot = vaultRoot
        c.snapshot = snapshot
        if c.ready, (c.path != note.path || c.text != note.content || c.dark != dark) {
            c.render(note: note, snapshot: snapshot, dark: dark)
        } else {
            c.pendingNote = note
            c.pendingDark = dark
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        var handler: MobileSchemeHandler?
        var snapshot: VaultSnapshot?
        var ready = false
        var path: String?
        var text: String?
        var dark = false
        var pendingNote: NoteRecord?
        var pendingDark = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            if let note = pendingNote {
                render(note: note, snapshot: snapshot, dark: pendingDark)
                pendingNote = nil
            }
        }

        func render(note: NoteRecord, snapshot: VaultSnapshot?, dark: Bool) {
            guard let snapshot else { return }
            path = note.path
            text = note.content
            self.dark = dark
            let typeset: [String: Any] = [
                "on": true, "onum": true, "hyphens": true, "smallCaps": true,
                "justify": false, "face": "lm", "opening": "smallcaps"
            ]
            let payload = ReaderPayload.build(
                text: note.content, path: note.path, snap: snapshot,
                dark: dark, sidenotes: true, keepScroll: false,
                typeset: typeset, backlinks: true
            )
            webView?.evaluateJavaScript("Onyx.setType(19, 36); Onyx.render(\(payload))", completionHandler: nil)
        }

        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "open":
                if let p = body["path"] as? String, !p.isEmpty, snapshot?.notes[p] != nil {
                    NotificationCenter.default.post(name: .onyxOpenNote, object: p)
                } else if let t = body["target"] as? String, let resolved = snapshot?.resolve(t, from: path), snapshot?.notes[resolved] != nil {
                    NotificationCenter.default.post(name: .onyxOpenNote, object: resolved)
                }
            case "url":
                if let s = body["url"] as? String, let u = URL(string: s) {
                    UIApplication.shared.open(u)
                }
            case "tag":
                if let t = body["tag"] as? String {
                    NotificationCenter.default.post(name: .onyxSearch, object: "tag:" + t)
                }
            default:
                break // read-only: ignore edit, task, kanban, folds, imageSize
            }
        }

    }
}

extension Notification.Name {
    static let onyxOpenNote = Notification.Name("onyx.ios.openNote")
    static let onyxSearch = Notification.Name("onyx.ios.search")
}
