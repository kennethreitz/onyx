import SwiftUI
import AppKit
import OnyxCore

extension KeyModifiers {
    init(ns flags: NSEvent.ModifierFlags) {
        var m: KeyModifiers = []
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.control) { m.insert(.control) }
        self = m
    }
}

extension KeyChord {
    var keyEquivalent: KeyEquivalent {
        switch key {
        case "\u{7F}", "\u{08}": return .delete
        case "\r": return .return
        case "\t": return .tab
        case " ": return .space
        case "\u{1b}": return .escape
        default:
            guard let ch = key.first else { return .space }
            return KeyEquivalent(ch)
        }
    }

    var eventModifiers: EventModifiers {
        var m: EventModifiers = []
        if modifiers.contains(.command) { m.insert(.command) }
        if modifiers.contains(.shift) { m.insert(.shift) }
        if modifiers.contains(.option) { m.insert(.option) }
        if modifiers.contains(.control) { m.insert(.control) }
        return m
    }

    init?(event: NSEvent) {
        self.init(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            keyCode: event.keyCode,
            modifiers: KeyModifiers(ns: event.modifierFlags)
        )
    }

    /// True when this event matches one of a command's live bindings.
    static func matches(_ event: NSEvent, command id: String, store: ShortcutStore = .shared) -> Bool {
        guard let chord = KeyChord(event: event) else { return false }
        return store.chords(for: id).contains(chord)
    }
}

extension View {
    @ViewBuilder
    func commandShortcut(_ chord: KeyChord?) -> some View {
        if let chord {
            self.keyboardShortcut(chord.keyEquivalent, modifiers: chord.eventModifiers)
        } else {
            self
        }
    }
}

/// Menu items that show and fire the live binding from `ShortcutStore`.
enum ShortcutMenus {
    @ViewBuilder
    static func button(_ id: String, title: String? = nil, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        let chords = ShortcutStore.shared.chords(for: id)
        let title = title ?? CommandCatalog.title(id)
        // Close Pane keeps ⌘W off the menu item so a single pane still closes the window.
        if id == "closepane", chords.count == 1, chords.first == .command("w") {
            Button("Close Pane  (⌘W)", action: action).disabled(disabled)
        } else {
            Button(title, action: action).commandShortcut(chords.first).disabled(disabled)
            if chords.count > 1 {
                Button(title + " ", action: action).commandShortcut(chords[1]).disabled(disabled)
            }
        }
    }
}

// MARK: Settings ▸ Shortcuts

struct ShortcutsSettingsPage: View {
    @State private var revision = 0
    @State private var recording: String?
    @State private var monitor: Any?
    @State private var pending: Pending?
    @State private var confirmResetAll = false

    private var store: ShortcutStore { ShortcutStore.shared }

    enum Pending: Identifiable {
        case assign(id: String, chord: KeyChord, proposal: ShortcutProposal)
        case reset(id: String, conflicts: [(chord: KeyChord, commandId: String, title: String)])

        var id: String {
            switch self {
            case .assign(let id, let chord, _): return "assign-\(id)-\(chord.display)"
            case .reset(let id, _): return "reset-\(id)"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Text("Click a shortcut to change it. Clear removes it; Reset restores the default. Standard editing keys such as ⌘C stay with the editor.")
                        .font(.system(size: 11)).foregroundStyle(Color.faint)
                }
                ForEach(CommandCatalog.grouped(), id: \.0) { group, items in
                    Section {
                        ForEach(items, id: \.id) { spec in
                            row(spec)
                        }
                    } header: { settingsHeader(group.title) }
                }
                Section {
                    Button("Reset All Shortcuts…") { confirmResetAll = true }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: SettingsPage.width, height: 560)
        .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.didChange)) { _ in revision += 1 }
        .onDisappear { stopRecording() }
        .alert("Reset all shortcuts?", isPresented: $confirmResetAll) {
            Button("Reset All", role: .destructive) { store.resetAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every command returns to its default shortcut.")
        }
        .alert(pendingTitle, isPresented: pendingPresented) {
            if let p = pending {
                switch p {
                case .assign(let id, let chord, let proposal):
                    Button("Cancel", role: .cancel) { pending = nil }
                    Button(proposal.hasConflict ? "Reassign" : "Use Anyway") {
                        store.assign(id, chord, replacing: proposal.conflictId)
                        pending = nil
                    }
                case .reset(let id, let conflicts):
                    Button("Cancel", role: .cancel) { pending = nil }
                    Button("Reassign") {
                        store.reset(id, replacing: conflicts.map(\.commandId))
                        pending = nil
                    }
                }
            }
        } message: {
            Text(pendingMessage)
        }
    }

    private var pendingPresented: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    private var pendingTitle: String {
        switch pending {
        case .assign(_, let chord, let proposal) where proposal.isReserved && proposal.hasConflict:
            return "\(chord.display) is reserved and already used"
        case .assign(_, let chord, let proposal) where proposal.isReserved:
            return "\(chord.display) is reserved"
        case .assign(_, let chord, _):
            return "\(chord.display) is already used"
        case .reset:
            return "Restore default shortcut?"
        case nil:
            return ""
        }
    }

    private var pendingMessage: String {
        switch pending {
        case .assign(_, let chord, let proposal):
            var parts: [String] = []
            if let reason = proposal.reservedReason {
                parts.append("\(chord.display) is a reserved system shortcut (\(reason)). Using it can hide that system action.")
            }
            if let title = proposal.conflictTitle {
                parts.append("\(chord.display) is already used by \(title). Reassign it to this command?")
            }
            return parts.joined(separator: " ")
        case .reset(let id, let conflicts):
            let names = conflicts.map(\.title).joined(separator: ", ")
            return "The default for \(CommandCatalog.title(id)) is already used by \(names). Reassign it back?"
        case nil:
            return ""
        }
    }

    @ViewBuilder
    private func row(_ spec: CommandSpec) -> some View {
        let _ = revision
        let chords = store.chords(for: spec.id)
        let label = chords.isEmpty ? "None" : store.display(for: spec.id)
        HStack(spacing: 8) {
            Text(spec.title).font(.system(size: 13))
            Spacer(minLength: 8)
            Button {
                recording == spec.id ? stopRecording() : startRecording(spec.id)
            } label: {
                Text(recording == spec.id ? "Type a shortcut" : label)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(recording == spec.id ? Color.cursorBlue : Color.ink)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(recording == spec.id ? Color.cursorBlue.opacity(0.12) : Color.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.control))
            }
            .buttonStyle(.plain)
            .help(recording == spec.id ? "Press a key combination, or Esc to cancel" : "Click to change this shortcut")

            Button("Clear") { stopRecording(); store.clear(spec.id) }
                .disabled(chords.isEmpty)
                .controlSize(.small)
            Button("Reset") { stopRecording(); requestReset(spec.id) }
                .disabled(!store.isOverridden(spec.id))
                .controlSize(.small)
        }
    }

    private func requestReset(_ id: String) {
        let conflicts = store.conflictsOnReset(id)
        if conflicts.isEmpty {
            store.reset(id)
        } else {
            pending = .reset(id: id, conflicts: conflicts)
        }
    }

    private func startRecording(_ id: String) {
        stopRecording()
        recording = id
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            // Ignore bare modifier presses.
            if [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(e.keyCode) { return nil }
            let mods = KeyModifiers(ns: e.modifierFlags)
            if e.keyCode == 53 { // Esc cancels
                DispatchQueue.main.async { stopRecording() }
                return nil
            }
            guard let chord = KeyChord(event: e) else { NSSound.beep(); return nil }
            // A letter or number with only Shift (or nothing) is typing, not a shortcut.
            if !mods.contains(.command) && !mods.contains(.control) && !mods.contains(.option) {
                NSSound.beep(); return nil
            }
            DispatchQueue.main.async { finishRecording(id: id, chord: chord) }
            return nil
        }
    }

    private func finishRecording(id: String, chord: KeyChord) {
        stopRecording()
        let proposal = store.evaluate(chord, for: id)
        if proposal.isClear {
            store.assign(id, chord)
        } else {
            pending = .assign(id: id, chord: chord, proposal: proposal)
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
    }
}
