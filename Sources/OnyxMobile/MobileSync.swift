import Foundation
import OnyxCore
import OnyxSync
import SwiftUI
import UIKit

/// The Obsidian account on iOS. The token is kept in the Keychain under Onyx's own service ("md.onyx.sync");
/// Onyx never reads Obsidian's credentials. Same flow as the Mac: try without a code, then ask for 2FA.
@MainActor
final class MobileSyncAccount: ObservableObject {
    static let shared = MobileSyncAccount()
    /// Keychain, or a protected file when this build has no Keychain access (unsigned simulator builds).
    let store: any SecretStore = ResilientSecretStore(onFallback: SyncSignIn.defaultLog)
    let api = ObsidianAPI()
    static let signedInKey = "onyx.sync.signedIn"
    static let emailKey = "onyx.sync.email"

    @Published private(set) var email = UserDefaults.standard.string(forKey: MobileSyncAccount.emailKey) ?? ""
    @Published private(set) var signedIn = UserDefaults.standard.bool(forKey: MobileSyncAccount.signedInKey)
    @Published var vaults: [ObsidianAPI.RemoteVault] = []
    private var cachedToken: String?

    var token: String? {
        if let t = cachedToken { return t }
        cachedToken = store.token
        if cachedToken == nil && signedIn { signedIn = false; UserDefaults.standard.set(false, forKey: Self.signedInKey) }
        return cachedToken
    }

    enum SignInResult { case ok, needsCode }

    func signIn(email: String, password: String, code: String?) async throws -> SignInResult {
        // Idempotent (SyncSignIn): reuses a token that still works, retries "Already logged in" once, and keeps
        // the token for this session even if it can't be stored.
        switch try await SyncSignIn(api: api, store: store).signIn(email: email, password: password, code: code, heldToken: cachedToken) {
        case .needsCode:
            return .needsCode
        case .signedIn(let t, let e, _):
            cachedToken = t
            self.email = e
            UserDefaults.standard.set(e, forKey: Self.emailKey)
            UserDefaults.standard.set(true, forKey: Self.signedInKey)
            signedIn = true
            return .ok
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

    var syncOnly: SyncOnlyVaults { SyncOnlyVaults(store: store) }
}

extension SyncStatus {
    var symbol: String {
        switch phase {
        case .synced: "checkmark.icloud"
        case .connecting, .syncing: "arrow.triangle.2.circlepath.icloud"
        case .paused: "pause.circle"
        case .offline: "icloud.slash"
        case .error, .needsAttention: "exclamationmark.icloud"
        }
    }
    var isProblem: Bool { if case .error = phase { return true }; if case .needsAttention = phase { return true }; return false }
    var text: String {
        let when = lastSynced.map { " · \($0.formatted(.relative(presentation: .named)))" } ?? ""
        switch phase {
        case .connecting: return "Connecting…"
        case .syncing(let s): return s.isEmpty ? "Syncing…" : s
        case .synced: return (initialMerge ? "First sync done" : "Up to date") + when
        case .paused: return "Paused" + when
        case .offline(let s): return "Offline — \(s)"
        case .error(let s): return s
        case .needsAttention(let s): return "Needs you: \(s)"
        }
    }
}

// MARK: - Sync for the open sync-only vault

extension MobileVault {
    /// Engine messages that mean files in the vault changed, so the note list should be rescanned.
    static let localChangeMessages = ["Downloading file", "Deleting", "Renaming conflicted file", "Kept remote version",
                                      "Merge successful", "Conflicted copy stored", "Creating local folder"]

    var isSyncOnly: Bool { managed != nil }

    /// Open a sync-only vault (a local copy in Application Support/Onyx/Vaults) and start syncing it.
    func openManaged(_ v: ManagedVault) {
        let lib = SyncVaultLibrary.default
        guard let folder = try? lib.checkedFolder(v) else { error = "That vault’s folder is missing."; return }
        stopSync()
        stopAccessForManaged()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        managed = v
        root = folder
        error = nil
        UserDefaults.standard.set(v.id, forKey: Self.managedKey)
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        selectedPath = nil
        loadTreeExpanded()
        scan()
        if let today = dailyPath, snapshot?.notes[today] != nil { selectedPath = today }
        if let p = selectedPath { revealInTree(p) }
        startSync()
        applyPendingURI()
    }

    func startSync() {
        guard let v = managed, syncEngine == nil else { return }
        let account = MobileSyncAccount.shared
        guard account.syncOnly.isConnected(v) else {   // disconnected: the copy stays, nothing syncs
            syncStatus = SyncStatus(phase: .paused, lastSynced: nil, initialMerge: false)
            return
        }
        guard let token = account.token else {
            syncStatus = SyncStatus(phase: .error("Signed out of Obsidian — sign in to resume syncing"), lastSynced: nil, initialMerge: false)
            return
        }
        do {
            guard let e = try account.syncOnly.engine(for: v, token: token,
                onStatus: { [weak self] s in Task { @MainActor in self?.syncStatusChanged(s) } },
                onLog: { [weak self] msg, _ in
                    guard MobileVault.localChangeMessages.contains(where: { msg.hasPrefix($0) }) else { return }
                    Task { @MainActor in self?.syncChangedFiles() }
                }) else {
                syncStatus = SyncStatus(phase: .error("Not connected — reconnect it from Manage Sync"), lastSynced: nil, initialMerge: false)
                return
            }
            syncEngine = e
            syncStatus = SyncStatus(phase: .connecting, lastSynced: nil, initialMerge: true)
            Task { await e.start() }
        } catch {
            syncStatus = SyncStatus(phase: .error(SyncErrorText.describe(error)), lastSynced: nil, initialMerge: false)
        }
    }

    func stopSync() {
        if let e = syncEngine { Task { await e.stop() } }
        syncEngine = nil
        syncStatus = nil
        pendingSyncRescan = false
    }

    func syncNow() {
        if syncEngine == nil { startSync() }
        if let e = syncEngine { Task { await e.requestSync() } }
    }
    func syncEdited() { if let e = syncEngine { Task { await e.requestSync() } } }
    func setSyncPaused(_ p: Bool) { if let e = syncEngine { Task { await e.setPaused(p) } } }
    func confirmSyncAction() { if let e = syncEngine { Task { await e.confirmPendingAction() } } }

    var syncPaused: Bool { if case .paused = syncStatus?.phase { return true }; return false }

    private func syncStatusChanged(_ s: SyncStatus) {
        syncStatus = s
        if case .synced = s.phase, pendingSyncRescan { pendingSyncRescan = false; scan() }
    }

    /// Rescan when sync changed files: at most every few seconds while a big pull is running, and once at the end.
    private func syncChangedFiles() {
        pendingSyncRescan = true
        if Date().timeIntervalSince(lastSyncRescan) > 3 {
            lastSyncRescan = Date()
            pendingSyncRescan = false
            scan()
            if selectedPath == nil, !(UIDevice.current.userInterfaceIdiom == .phone) { selectedPath = snapshot?.sortedNotePaths.first }
        }
    }

    /// Going to the background: ask for a little time to finish the current sync.
    func syncBeforeSuspend() {
        guard let e = syncEngine else { return }
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "Obsidian Sync") {
            UIApplication.shared.endBackgroundTask(task); task = .invalid
        }
        Task { @MainActor in
            await e.requestSync()
            for _ in 0..<100 {           // up to ~25 s
                try? await Task.sleep(nanoseconds: 250_000_000)
                if case .synced = await e.currentPhase { break }
                if task == .invalid { break }
            }
            if task != .invalid { UIApplication.shared.endBackgroundTask(task); task = .invalid }
        }
    }

    /// Stop syncing but keep the local copy (it stays listed, ready to reconnect).
    func disconnectSync() {
        guard let v = managed else { return }
        stopSync()
        MobileSyncAccount.shared.syncOnly.disconnect(v)
        syncStatus = SyncStatus(phase: .paused, lastSynced: nil, initialMerge: false)
        objectWillChange.send()
    }

    /// Delete this device's copy of a sync-only vault (closing it first if it's open). The remote vault is untouched.
    func removeLocalCopy(_ v: ManagedVault) {
        if managed?.id == v.id { forgetVault() }
        do { try MobileSyncAccount.shared.syncOnly.removeLocalCopy(v) } catch { self.error = SyncErrorText.describe(error) }
        objectWillChange.send()
    }

    var managedVaults: [ManagedVault] { SyncVaultLibrary.default.load() }
    func isConnected(_ v: ManagedVault) -> Bool { MobileSyncAccount.shared.syncOnly.isConnected(v) }
}
