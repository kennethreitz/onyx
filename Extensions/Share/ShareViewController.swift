import AppKit
import UniformTypeIdentifiers

/// "Onyx" in the macOS Share menu (Safari's Share button, Finder, Notes, any app that shares a
/// URL or text). It forwards what was shared to Onyx as `onyx://clip` and closes at once.
@objc(ShareViewController)
final class ShareViewController: NSViewController {
    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let context = extensionContext else { return }
        let items = context.inputItems.compactMap { $0 as? NSExtensionItem }
        let title = items.lazy.compactMap { $0.attributedTitle?.string ?? $0.attributedContentText?.string }.first
        let providers = items.flatMap { $0.attachments ?? [] }

        func finish(_ fields: [String: Any]) {
            DispatchQueue.main.async {
                if let url = ClipURL.make(fields) { NSWorkspace.shared.open(url) }
                context.completeRequest(returningItems: nil, completionHandler: nil)
            }
        }

        if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            p.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { value, _ in
                var link: URL? = value as? URL
                if link == nil, let d = value as? Data { link = URL(dataRepresentation: d, relativeTo: nil) }
                if let link, link.isFileURL == false {
                    finish(["url": link.absoluteString, "title": title ?? ""])
                } else {
                    finish(["text": title ?? ""])
                }
            }
        } else if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            p.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { value, _ in
                let text = (value as? String) ?? (value as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let u = URL(string: trimmed), ["http", "https"].contains(u.scheme?.lowercased() ?? ""), !trimmed.contains(" ") {
                    finish(["url": trimmed, "title": title ?? ""])
                } else {
                    finish(["text": text, "title": title ?? ""])
                }
            }
        } else {
            finish(title.map { ["text": $0] } ?? [:])
        }
    }
}
