import AppKit
import OnyxCore

/// Keeps Option-hold alternates ("Open in Obsidian", "Copy Onyx URL") off menus unless
/// Option is held. In NSMenus a target becomes a hidden alternate of the preceding sibling
/// (Reveal in Finder / Open in Default App, or Copy File Path / Copy Wikilink), so the two
/// swap while the menu is open. With no such sibling, the item is hidden and shown from
/// flagsChanged / menu open. The command palette is left alone.
enum ObsidianOptionMenu {
    private static var installed = false
    private static var observers: [NSObjectProtocol] = []
    private static var flagsMonitor: Any?

    static func install() {
        guard !installed else { return }
        installed = true
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSMenu.didAddItemNotification, object: nil, queue: .main) { n in
            guard let menu = n.object as? NSMenu else { return }
            patch(menu, recursive: false)
        })
        observers.append(nc.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { n in
            guard let menu = n.object as? NSMenu else { return }
            patch(menu, recursive: true)
        })
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { e in
            refreshOptionOnly(optionDown: e.modifierFlags.contains(.option))
            return e
        }
        if let menu = NSApp.mainMenu { patch(menu, recursive: true) }
    }

    static func patch(_ menu: NSMenu, recursive: Bool) {
        let items = menu.items
        for (i, item) in items.enumerated() {
            if recursive, let sub = item.submenu { patch(sub, recursive: true) }
            guard let rule = OptionAlternate.rule(for: item.title) else { continue }
            let previous = i > 0 ? items[i - 1].title : nil
            switch rule.treatment(previousTitle: previous) {
            case .alternate:
                // Same keyEquivalent as the sibling would collide with Reveal in
                // Finder's ⌥⇧⌘R; an empty equivalent with an Option mask is enough
                // for AppKit to swap the items while ⌥ is held.
                item.isAlternate = true
                item.keyEquivalent = ""
                item.keyEquivalentModifierMask = .option
                item.isHidden = false
            case .optionOnly:
                item.isAlternate = false
                item.isHidden = !NSEvent.modifierFlags.contains(.option)
            }
        }
    }

    /// Update hidden, non-alternate copies when Option is pressed or released
    /// while a menu is already open.
    static func refreshOptionOnly(optionDown: Bool) {
        func walk(_ menu: NSMenu?) {
            guard let menu else { return }
            for (i, item) in menu.items.enumerated() {
                walk(item.submenu)
                guard let rule = OptionAlternate.rule(for: item.title) else { continue }
                let previous = i > 0 ? menu.items[i - 1].title : nil
                if rule.treatment(previousTitle: previous) == .optionOnly {
                    item.isHidden = !optionDown
                }
            }
        }
        walk(NSApp.mainMenu)
    }
}
