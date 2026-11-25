import AppKit
import OnyxCore
import OnyxSync
import SwiftUI

/// Sync-only vaults on the Mac: an Obsidian Sync vault kept as a local copy under
/// ~/Library/Application Support/Onyx/Vaults/<name>, instead of a folder you picked.
@MainActor
enum SyncOnlyVaultsMac {
    static var vaults: SyncOnlyVaults { SyncOnlyVaults(store: SyncAccount.shared.store) }

    static func open(_ v: ManagedVault, in ws: Workspace) {
        let url = vaults.folder(v)
        OnyxApp.remember(url)
        ws.open(vault: url)
    }

    static func reveal(_ v: ManagedVault) {
        let url = vaults.folder(v)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func revealLibrary() {
        let root = vaults.library.root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }

    /// Confirm, then delete this Mac's copy (closing it first if it's open). The remote vault is untouched.
    static func confirmRemove(_ v: ManagedVault, in ws: Workspace) {
        let s = vaults
        let url = s.folder(v)
        let count = (FileManager.default.enumerator(atPath: url.path)?.allObjects.count) ?? 0
        let isOpen = ws.root.map { SyncVaultLibrary.canonicalPath($0) == SyncVaultLibrary.canonicalPath(url) } ?? false
        var unsynced = false
        if isOpen, let sync = ws.obsidianSync, sync.status.phase != .synced { unsynced = true }
        let a = NSAlert()
        a.alertStyle = .critical
        a.messageText = "Delete the local copy of “\(v.name)”?"
        a.informativeText = "This deletes \(url.lastPathComponent) (\(count) item\(count == 1 ? "" : "s")) from this Mac and stops syncing it. "
            + "The vault in Obsidian Sync and your other devices keep everything."
            + (unsynced ? "\n\nThis vault isn’t fully synced right now, so changes made here since the last sync could be lost." : "")
        a.addButton(withTitle: "Delete Local Copy")
        a.addButton(withTitle: "Cancel")
        a.buttons.first?.hasDestructiveAction = true
        guard a.runModal() == .alertFirstButtonReturn else { return }
        if isOpen { ws.closeVault() }
        do { try s.removeLocalCopy(v) } catch {
            let e = NSAlert(); e.messageText = "Couldn’t delete the local copy"; e.informativeText = SyncErrorText.describe(error); e.runModal()
        }
    }
}

extension SyncVaultLibrary {
    static func canonicalPath(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }
}

/// The sync-only vaults on this Mac, with Open / Reveal / Remove. Shown on the welcome screen and in Settings.
struct SyncOnlyVaultList: View {
    @Bindable var ws: Workspace
    var compact = false
    @State private var revision = 0

    var body: some View {
        let s = SyncOnlyVaultsMac.vaults
        let all = s.library.load()
        let _ = revision
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(all) { v in
                    let isOpen = ws.root.map { SyncVaultLibrary.canonicalPath($0) == SyncVaultLibrary.canonicalPath(s.folder(v)) } ?? false
                    HStack(spacing: 8) {
                        Image(systemName: s.isConnected(v) ? "icloud" : "icloud.slash").foregroundStyle(Color.faint).frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(v.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color.ink)
                            Text(s.isConnected(v) ? (isOpen ? "Open · syncing with Obsidian Sync" : "Syncs while open") : "Not syncing (disconnected)")
                                .font(.system(size: 10.5)).foregroundStyle(Color.faint)
                        }
                        Spacer()
                        if !isOpen { Button("Open") { SyncOnlyVaultsMac.open(v, in: ws) } }
                        Menu {
                            Button("Reveal in Finder") { SyncOnlyVaultsMac.reveal(v) }
                            Divider()
                            Button("Delete Local Copy…", role: .destructive) { SyncOnlyVaultsMac.confirmRemove(v, in: ws); revision += 1 }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    }
                }
            }
            .frame(maxWidth: compact ? 360 : .infinity)
        }
    }
}

/// "Connect Obsidian Sync Vault…": sign in, pick a remote vault, unlock it, and make a local copy that syncs.
struct SyncOnlyConnectSheet: View {
    var onDone: (ManagedVault) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var account = SyncAccount.shared
    @State private var email = UserDefaults.standard.string(forKey: "onyx.sync.email") ?? ""
    @State private var password = ""
    @State private var code = ""
    @State private var needsCode = false
    @State private var busy: String?
    @State private var error: String?
    @State private var selectedVault = ""
    @State private var vaultPassword = ""
    @State private var deviceName = (Host.current().localizedName ?? "Mac") + " (Onyx)"

    var chosen: ObsidianAPI.RemoteVault? { account.vaults.first { $0.id == selectedVault } }
    var existing: ManagedVault? { chosen.flatMap { SyncOnlyVaultsMac.vaults.library.vault(remoteID: $0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect an Obsidian Sync vault").font(Theme.serif(17, bold: true))
            Text("Onyx keeps a local copy in ~/Library/Application Support/Onyx/Vaults and keeps it in sync with Obsidian Sync. No other folder on this Mac is touched.")
                .font(.system(size: 11.5)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            Form {
                if !account.signedIn {
                    TextField("Email", text: $email, prompt: Text("you@example.com")).textContentType(.username)
                    SecureField("Password", text: $password, prompt: Text("Obsidian account password")).textContentType(.password)
                    if needsCode { TextField("2FA code", text: $code, prompt: Text("123456")) }
                } else {
                    LabeledContent("Account") {
                        HStack { Text(account.email).foregroundStyle(Color.muted); Button("Sign out") { Task { await account.signOut() } } }
                    }
                    HStack {
                        Picker("Remote vault", selection: $selectedVault) {
                            Text("Choose…").tag("")
                            ForEach(account.vaults, id: \.id) { v in
                                let local = SyncOnlyVaultsMac.vaults.library.vault(remoteID: v.id) != nil
                                Text(v.name + (v.isShared ? " (shared)" : "") + (local ? " — on this Mac" : "")).tag(v.id)
                            }
                        }
                        Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).help("Refresh")
                    }
                    if let v = chosen, v.password == nil {
                        SecureField("Encryption password", text: $vaultPassword, prompt: Text("Vault end-to-end password"))
                    }
                    TextField("Device name", text: $deviceName)
                    if let e = existing {
                        Text("“\(e.name)” already has a local copy (\(e.folder)). Connecting again reuses it; the first sync never deletes anything.")
                            .font(.system(size: 11)).foregroundStyle(Color.faint)
                    }
                }
            }
            .formStyle(.grouped)
            if let busy { HStack(spacing: 6) { ProgressView().controlSize(.small); Text(busy).font(.system(size: 11)).foregroundStyle(Color.faint) } }
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(Color.warn).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if !account.signedIn {
                    Button(needsCode ? "Verify" : "Sign In") { Task { await signIn() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(email.isEmpty || password.isEmpty || (needsCode && code.isEmpty) || busy != nil)
                } else {
                    Button(existing == nil ? "Create Local Copy and Sync" : "Reconnect and Sync") { Task { await connect() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(chosen == nil || (chosen?.password == nil && vaultPassword.isEmpty) || busy != nil)
                }
            }
        }
        .padding(20).frame(width: 500)
        .task { if account.signedIn && account.vaults.isEmpty { await refresh() } }
    }

    func run(_ label: String, _ op: () async throws -> Void) async {
        busy = label; error = nil
        do { try await op() } catch { self.error = SyncErrorText.describe(error) }
        busy = nil
    }

    func signIn() async {
        await run("Signing in…") {
            switch try await account.signIn(email: email, password: password, code: needsCode ? code : nil) {
            case .needsCode: needsCode = true
            case .ok: password = ""; code = ""; needsCode = false; try await account.refreshVaults()
            }
        }
    }

    func refresh() async { await run("Loading vaults…") { try await account.refreshVaults() } }

    func connect() async {
        guard let v = chosen, let token = account.token else { return }
        await run("Checking the password…") {
            let r = try await SyncOnlyVaults.unlock(api: account.api, token: token, vault: v, password: vaultPassword,
                                                    deviceName: deviceName, accountEmail: account.email)
            let mv = try SyncOnlyVaultsMac.vaults.connect(binding: r.binding, key: r.key)
            vaultPassword = ""
            onDone(mv)
            dismiss()
        }
    }
}
