import AppKit
import SafariServices

/// Native side of the "Clip to Onyx" Safari Web Extension. background.js sends
/// `browser.runtime.sendNativeMessage({url, title, selection, …})`; this turns it into an
/// `onyx://clip` URL and opens it, so Onyx clips without Safari's "open this app?" prompt.
@objc(SafariWebExtensionHandler)
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = (item?.userInfo?[SFExtensionMessageKey] as? [String: Any]) ?? [:]
        var ok = false
        if let url = ClipURL.make(message) {
            ok = NSWorkspace.shared.open(url)
        }
        let reply = NSExtensionItem()
        reply.userInfo = [SFExtensionMessageKey: ["ok": ok]]
        context.completeRequest(returningItems: [reply], completionHandler: nil)
    }
}
