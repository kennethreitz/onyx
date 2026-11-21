import AppKit
import SwiftUI
import OnyxCore

/// A compact AppKit field so we can select the stem (without the extension) the way Finder does,
/// and distinguish Return (commit), Esc (cancel), and resigning first responder (commit).
struct InlineRenameField: NSViewRepresentable {
    @Binding var text: String
    var wholeName: Bool
    var onCommit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField(string: text)
        f.delegate = context.coordinator
        f.font = .systemFont(ofSize: 12.5)
        f.textColor = Theme.ink
        f.backgroundColor = Theme.paper
        f.drawsBackground = true
        f.isBezeled = true
        f.bezelStyle = .roundedBezel
        f.isBordered = true
        f.focusRingType = .exterior
        f.cell?.isScrollable = true
        f.cell?.wraps = false
        f.cell?.usesSingleLineMode = true
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        f.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return f
    }

    func updateNSView(_ f: NSTextField, context: Context) {
        context.coordinator.parent = self
        if f.stringValue != text, f.currentEditor() == nil { f.stringValue = text }
        if !context.coordinator.focused {
            context.coordinator.focused = true
            DispatchQueue.main.async {
                guard f.window != nil else { return }
                f.window?.makeFirstResponder(f)
                Self.selectStem(f, wholeName: wholeName)
            }
        }
    }

    static func selectStem(_ field: NSTextField, wholeName: Bool) {
        let len = InlineRename.selectionLength(for: field.stringValue, wholeName: wholeName)
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: len)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineRenameField
        var focused = false
        private var cancelled = false
        /// True while we are applying Esc so resigning the field does not also commit.
        private var closing = false

        init(_ parent: InlineRenameField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let f = obj.object as? NSTextField else { return }
            parent.text = f.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onCommit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                cancelled = true
                closing = true
                parent.onCancel()
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            if closing || cancelled { return }
            parent.onCommit()
        }
    }
}
