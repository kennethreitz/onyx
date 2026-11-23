import AppKit
import CryptoKit
import Observation
import OnyxCore
import OnyxSync
import SwiftUI

/// The Obsidian account Onyx is signed in to. The auth token lives in the Keychain under Onyx's own service
/// ("md.onyx.sync"); Onyx never reads Obsidian's or obsidian-headless's stored credentials.
@MainActor @Observable
final class SyncAccount {
    static let shared = SyncAccount()
    @ObservationIgnored let store: SecretStore = KeychainStore()
    @ObservationIgnored let api = ObsidianAPI()
    private(set) var email = UserDefaults.standard.string(forKey: "onyx.sync.email") ?? ""
    private(set) var signedIn = false
    var vaults: [ObsidianAPI.RemoteVault] = []

    /// Signed-in state comes from a non-secret marker, so launching Onyx or opening Settings never touches
    /// the Keychain (each `make app` re-signs the binary, and a Keychain read would prompt). The token is read
    /// only when a connected vault actually syncs, or on an explicit account action, then kept for the session.
    static let signedInKey = "onyx.sync.signedIn"
    init() {
        let d = UserDefaults.standard
        if d.object(forKey: Self.signedInKey) == nil { d.set(!(d.string(forKey: "onyx.sync.email") ?? "").isEmpty, forKey: Self.signedInKey) }  // pre-marker installs
        signedIn = d.bool(forKey: Self.signedInKey)
    }
    @ObservationIgnored private var cachedToken: String?
    var token: String? {
        if let t = cachedToken { return t }
        cachedToken = store.token
        if cachedToken == nil && signedIn { signedIn = false; UserDefaults.standard.set(false, forKey: Self.signedInKey) }
        return cachedToken
    }

    enum SignInResult { case ok, needsCode }

    /// Like `ob login`: first without a code; if the account has 2FA the caller asks for it and calls again.
    func signIn(email: String, password: String, code: String?) async throws -> SignInResult {
        do {
            let r = try await api.signIn(email: email, password: password, mfa: code ?? "")
            guard let t = r.token else { throw ObsidianAPI.APIError(message: "No token in the sign-in response") }
            try store.set("token", Data(t.utf8))
            cachedToken = t
            UserDefaults.standard.set(true, forKey: Self.signedInKey)
            self.email = r.email ?? email
            UserDefaults.standard.set(self.email, forKey: "onyx.sync.email")
            signedIn = true
            return .ok
        } catch where code == nil && ObsidianAPI.needsMFA(error) {
            return .needsCode
        }
    }

    func signOut() async {
        if let t = token { try? await api.signOut(token: t) }
        store.remove("token"); cachedToken = nil; signedIn = false; vaults = []
        UserDefaults.standard.set(false, forKey: Self.signedInKey)
    }

    func refreshVaults() async throws {
        guard let t = token else { return }
        let l = try await api.listVaults(token: t)
        vaults = l.vaults + (l.shared ?? [])
    }
}

/// Obsidian Sync for one local vault folder. Exists only after the user connected this folder in Settings ▸ Sync
/// (a state file under ~/Library/Application Support/Onyx/Sync); Onyx never turns sync on by itself.
@MainActor @Observable
final class VaultSync {
    let root: URL
    private(set) var binding: SyncBinding
    private(set) var status = SyncStatus(phase: .connecting, lastSynced: nil, initialMerge: true)
    @ObservationIgnored private var engine: SyncEngine?
    @ObservationIgnored var onLog: (SyncLogEvent, String) -> Void = { _, _ in }

    static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Onyx/Sync")
    }
    static func stateURL(for root: URL) -> URL {
        let id = Hex.encode(Array(SHA256.hash(data: Data(root.standardizedFileURL.path.utf8))).prefix(8))
        return supportDir.appendingPathComponent("\(id).json")
    }
    static func isConnected(_ root: URL) -> Bool { FileManager.default.fileExists(atPath: stateURL(for: root).path) }

    /// Resume sync for a folder that was connected before; nil if it never was (or secrets are missing).
    static func resume(for root: URL, onLog: @escaping (SyncLogEvent, String) -> Void = { _, _ in }) -> VaultSync? {
        guard ProcessInfo.processInfo.environment["ONYX_NO_SYNC"] == nil,
              let state = try? SyncState.load(stateURL(for: root)) else { return nil }
        let v = VaultSync(root: root, binding: state.binding)
        v.onLog = onLog
        v.start(state: state)
        return v
    }

    /// First connect, after the user confirmed the plan.
    static func connect(root: URL, binding: SyncBinding, key: [UInt8],
                        onLog: @escaping (SyncLogEvent, String) -> Void = { _, _ in }) throws -> VaultSync {
        try SyncAccount.shared.store.set("key." + binding.vaultID, Data(key))
        let state = SyncState(binding: binding)
        try state.save(stateURL(for: root))
        let v = VaultSync(root: root, binding: binding)
        v.onLog = onLog
        v.start(state: state)
        return v
    }

    private init(root: URL, binding: SyncBinding) { self.root = root; self.binding = binding }

    private func start(state: SyncState) {
        let account = SyncAccount.shared
        guard let token = account.token else {
            let msg = "Signed out of Obsidian — sign in under Settings ▸ Sync"
            status.phase = .error(msg); record(.error, msg); return
        }
        guard let key = account.store.vaultKey(binding.vaultID),
              let crypto = try? ObsidianCrypto.provider(version: binding.encryptionVersion, key: key, salt: binding.salt) else {
            let msg = "Missing the vault key — reconnect under Settings ▸ Sync"
            status.phase = .error(msg); record(.error, msg); return
        }
        var o = SyncEngine.Options()
        o.backupDir = Self.supportDir.appendingPathComponent("Backups").appendingPathComponent(Self.stateURL(for: root).deletingPathExtension().lastPathComponent)
        let e = SyncEngine(root: root, state: state, crypto: crypto, token: token, stateURL: Self.stateURL(for: root), options: o,
                           onStatus: { [weak self] s in Task { @MainActor in self?.status = s } },
                           onLog: { [weak self] msg, path in
                               if let ev = SyncLogStore.fromObsidian(message: msg, path: path) {
                                   Task { @MainActor in self?.record(ev.event, ev.detail) }
                               }
                           })
        engine = e
        Task { await e.start() }
    }

    func edited() { if let e = engine { Task { await e.requestSync() } } }
    func syncNow() { if let e = engine { Task { await e.requestSync() } } }
    func setPaused(_ p: Bool) { if let e = engine { Task { await e.setPaused(p) } } }
    func confirmPendingAction() { if let e = engine { Task { await e.confirmPendingAction() } } }
    func stop() { if let e = engine { Task { await e.stop() } }; engine = nil }

    /// Stop syncing this folder and forget the binding. Deletes nothing in the folder or on the server.
    func disconnect() {
        stop()
        try? FileManager.default.removeItem(at: Self.stateURL(for: root))
        SyncAccount.shared.store.remove("key." + binding.vaultID)
    }

    func record(_ event: SyncLogEvent, _ detail: String) { onLog(event, detail) }

    var isPaused: Bool { if case .paused = status.phase { return true }; return false }

    var help: String {
        let when = status.lastSynced.map { " · last synced \($0.formatted(.relative(presentation: .named)))" } ?? ""
        switch status.phase {
        case .connecting: return "Obsidian Sync: connecting to \(binding.vaultName)"
        case .syncing(let s): return "Obsidian Sync: \(s)"
        case .synced: return "Obsidian Sync: \(binding.vaultName) is up to date\(when)" + (status.initialMerge ? " (first sync)" : "")
        case .paused: return "Obsidian Sync: paused\(when)"
        case .offline(let s): return "Obsidian Sync: offline — \(s)\(when)"
        case .error(let s): return "Obsidian Sync: \(s)"
        case .needsAttention(let s): return "Obsidian Sync needs you: \(s)"
        }
    }
}

/// Footer badge beside git's.
/// ONYX_OPEN_SETTINGS=1 opens Settings at launch (screenshots / UI checks).
/// ONYX_SETTINGS_TAB=<name> selects a tab (general, editor, reading, graph, sync, updates).
struct SettingsOpener: View {
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Color.clear.frame(width: 0, height: 0).onAppear {
            guard ProcessInfo.processInfo.environment["ONYX_OPEN_SETTINGS"] != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { openSettings() }
        }
    }
}

struct SyncBadge: View {
    var sync: VaultSync
    var action: () -> Void
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        let (symbol, color): (String, Color) = switch sync.status.phase {
            case .synced: ("checkmark.icloud", Color.faint)
            case .connecting, .syncing: ("arrow.triangle.2.circlepath.icloud", Color.faint)
            case .paused: ("pause.circle", Color.faint)
            case .offline: ("icloud.slash", Color.faint)
            case .error, .needsAttention: ("exclamationmark.icloud", Color.warn)
        }
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10.5)).foregroundStyle(color).frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(sync.help + "\nClick for the sync log")
        .accessibilityLabel(sync.help)
        .contextMenu {
            Button("Show Sync Log") { action() }
            Button("Sync Settings…") { openSettings() }
        }
    }
}

// MARK: - Settings ▸ Sync

struct ObsidianSyncSettings: View {
    @Bindable var ws: Workspace
    var onShowLog: (() -> Void)? = nil
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
    @State private var proposal: Proposal?

    struct Proposal: Identifiable {
        let id = UUID()
        let binding: SyncBinding
        let key: [UInt8]
        let plan: InitialPlan
    }

    var body: some View {
        Section {
            if !account.signedIn { signInForm } else { signedInBody }
            if let busy { HStack(spacing: 6) { ProgressView().controlSize(.small); Text(busy).font(.system(size: 11)).foregroundStyle(Color.faint) } }
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(Color.warn) }
            // When the vault isn't connected, the Sync-now row (which also has Show Log) isn't shown.
            if onShowLog != nil, ws.obsidianSync == nil {
                AppKitPushButton(title: "Show Log", id: SettingsSyncLog.buttonID) { onShowLog?() }
            }
        } header: {
            Text("Obsidian Sync").font(Theme.serif(14, bold: true)).foregroundStyle(Color.ink).textCase(nil)
        }
        .sheet(item: $proposal) { p in confirmSheet(p) }
    }

    @ViewBuilder var signInForm: some View {
        TextField("Email", text: $email, prompt: Text("you@example.com")).textContentType(.username)
        SecureField("Password", text: $password, prompt: Text("Obsidian account password")).textContentType(.password)
        if needsCode { TextField("2FA code", text: $code, prompt: Text("123456")) }
        HStack {
            Text("Sign in with your Obsidian account. Onyx keeps the token in your Keychain.")
                .font(.system(size: 11)).foregroundStyle(Color.faint)
            Spacer()
            Button(needsCode ? "Verify" : "Sign in") { Task { await signIn() } }
                .disabled(email.isEmpty || password.isEmpty || (needsCode && code.isEmpty) || busy != nil)
                .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder var signedInBody: some View {
        LabeledContent("Account") {
            HStack { Text(account.email).foregroundStyle(Color.muted); Button("Sign out") { Task { await account.signOut() } } }
        }
        if let s = ws.obsidianSync {
            LabeledContent("This vault") {
                Text("Synced with “\(s.binding.vaultName)” as \(s.binding.deviceName)").foregroundStyle(Color.muted).lineLimit(1)
            }
            Text(s.help).font(.system(size: 11)).foregroundStyle(Color.faint)
            HStack {
                Button("Sync now") { s.syncNow() }
                Button(s.isPaused ? "Resume" : "Pause") { s.setPaused(!s.isPaused) }
                if case .needsAttention = s.status.phase { Button("Continue anyway") { s.confirmPendingAction() } }
                if let onShowLog { AppKitPushButton(title: "Show Log", id: SettingsSyncLog.buttonID, action: onShowLog) }
                Spacer()
                Button("Disconnect…", role: .destructive) { disconnect(s) }
            }
        } else if ws.root != nil {
            HStack {
                Picker("Remote vault", selection: $selectedVault) {
                    Text("Choose…").tag("")
                    ForEach(account.vaults, id: \.id) { v in Text(v.name + (v.isShared ? " (shared)" : "")).tag(v.id) }
                }
                Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).help("Refresh")
            }
            if let v = chosen, v.password == nil {
                SecureField("Encryption password", text: $vaultPassword, prompt: Text("Vault end-to-end password"))
            }
            TextField("Device name", text: $deviceName)
            HStack {
                Text("Sync stays off for “\(ws.root?.lastPathComponent ?? "")” until you connect it. You’ll see what the first sync will do before anything changes.")
                    .font(.system(size: 11)).foregroundStyle(Color.faint)
                Spacer()
                Button("Preview…") { Task { await preview() } }
                    .disabled(chosen == nil || (chosen?.password == nil && vaultPassword.isEmpty) || busy != nil)
            }
        }
    }

    var chosen: ObsidianAPI.RemoteVault? { account.vaults.first { $0.id == selectedVault } }

    func confirmSheet(_ p: Proposal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect “\(ws.root?.lastPathComponent ?? "")” to “\(p.binding.vaultName)”?").font(Theme.serif(17, bold: true))
            Text(p.plan.summary).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            if !p.plan.keepBoth.isEmpty { list("Kept twice", p.plan.keepBoth) }
            if !p.plan.toDownload.isEmpty { list("Downloads", p.plan.toDownload) }
            if !p.plan.toUpload.isEmpty { list("Uploads", p.plan.toUpload) }
            HStack {
                Spacer()
                Button("Cancel") { proposal = nil }.keyboardShortcut(.cancelAction)
                Button("Connect and Sync") { connect(p) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 460)
    }

    func list(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.muted)
            ForEach(items.prefix(8), id: \.self) { Text($0).font(.system(size: 11)).foregroundStyle(Color.faint).lineLimit(1).truncationMode(.middle) }
            if items.count > 8 { Text("and \(items.count - 8) more").font(.system(size: 11)).foregroundStyle(Color.faint) }
        }
    }

    // MARK: Actions

    func run(_ label: String, _ op: () async throws -> Void) async {
        busy = label; error = nil
        do { try await op() } catch { self.error = "\(error)" }
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

    func preview() async {
        guard let v = chosen, let root = ws.root, let token = account.token else { return }
        await run("Checking the password and comparing files…") {
            let salt = v.salt ?? ""
            let version = v.encryption_version ?? 0
            let pw = v.password ?? vaultPassword
            let key = try await Task.detached { try ObsidianCrypto.deriveVaultKey(password: pw, salt: salt) }.value
            let crypto = try ObsidianCrypto.provider(version: version, key: key, salt: salt)
            try await account.api.access(token: token, vaultID: v.id, keyhash: crypto.keyHash, host: v.host, encryptionVersion: version)
            let binding = SyncBinding(vaultID: v.id, vaultName: v.name, host: v.host, salt: salt, encryptionVersion: version,
                                      deviceName: deviceName, accountEmail: account.email)
            let plan = try await InitialPlan.compute(root: root, filter: SyncFilter(), crypto: crypto, binding: binding, token: token)
            proposal = Proposal(binding: binding, key: key, plan: plan)
            vaultPassword = ""
        }
    }

    func connect(_ p: Proposal) {
        guard let root = ws.root else { return }
        proposal = nil
        do {
            ws.obsidianSync = try VaultSync.connect(root: root, binding: p.binding, key: p.key, onLog: { [weak ws] event, detail in
                ws?.syncLog?.append(source: .obsidian, event: event, detail: detail)
            })
        }
        catch { self.error = "\(error)" }
    }

    func disconnect(_ s: VaultSync) {
        let a = NSAlert()
        a.messageText = "Stop syncing this vault with “\(s.binding.vaultName)”?"
        a.informativeText = "Nothing is deleted here or in Obsidian Sync. You can connect again later."
        a.addButton(withTitle: "Disconnect"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { s.disconnect(); ws.obsidianSync = nil }
    }
}
