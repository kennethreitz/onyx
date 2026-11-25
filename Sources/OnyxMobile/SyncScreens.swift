import OnyxCore
import OnyxSync
import SwiftUI
import UIKit

/// "Connect Obsidian Sync Vault": sign in, pick a remote vault, unlock it, and keep a local copy in the app.
struct SyncConnectScreen: View {
    @EnvironmentObject private var vault: MobileVault
    @ObservedObject private var account = MobileSyncAccount.shared
    @Environment(\.dismiss) private var dismiss
    @State private var email = UserDefaults.standard.string(forKey: MobileSyncAccount.emailKey) ?? ""
    @State private var password = ""
    @State private var code = ""
    @State private var needsCode = false
    @State private var busy: String?
    @State private var error: String?
    @State private var selectedVault = ""
    @State private var vaultPassword = ""
    @State private var deviceName = UIDevice.current.name + " (Onyx)"

    var chosen: ObsidianAPI.RemoteVault? { account.vaults.first { $0.id == selectedVault } }
    var existing: ManagedVault? { chosen.flatMap { SyncVaultLibrary.default.vault(remoteID: $0.id) } }

    var body: some View {
        Form {
            Section {
                Text("Onyx keeps a copy of the vault inside the app and keeps it in sync with Obsidian Sync while Onyx is open.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !account.signedIn {
                Section("Obsidian account") {
                    TextField("Email", text: $email).textContentType(.username).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password).textContentType(.password)
                    if needsCode {
                        TextField("2FA code", text: $code).textContentType(.oneTimeCode).keyboardType(.numberPad)
                    }
                    Button(needsCode ? "Verify" : "Sign In") { Task { await signIn() } }
                        .disabled(email.isEmpty || password.isEmpty || (needsCode && code.isEmpty) || busy != nil)
                }
            } else {
                Section("Obsidian account") {
                    LabeledContent("Signed in", value: account.email)
                    Button("Sign Out", role: .destructive) { Task { await account.signOut() } }
                }
                Section {
                    Picker("Remote vault", selection: $selectedVault) {
                        Text("Choose…").tag("")
                        ForEach(account.vaults, id: \.id) { v in
                            let local = SyncVaultLibrary.default.vault(remoteID: v.id) != nil
                            Text(v.name + (v.isShared ? " (shared)" : "") + (local ? " — on this device" : "")).tag(v.id)
                        }
                    }
                    if let v = chosen, v.password == nil {
                        SecureField("Encryption password", text: $vaultPassword)
                    }
                    TextField("Device name", text: $deviceName)
                    Button("Refresh Vaults") { Task { await refresh() } }
                } header: { Text("Vault") } footer: {
                    if let e = existing {
                        Text("“\(e.name)” already has a copy on this device. Connecting again reuses it; the first sync never deletes anything.")
                    }
                }
                Section {
                    Button(existing == nil ? "Create Local Copy and Sync" : "Reconnect and Sync") { Task { await connect() } }
                        .disabled(chosen == nil || (chosen?.password == nil && vaultPassword.isEmpty) || busy != nil)
                }
            }
            if let busy { Section { HStack { ProgressView(); Text(busy).foregroundStyle(.secondary) } } }
            if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
        }
        .navigationTitle("Obsidian Sync")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .task { if account.signedIn && account.vaults.isEmpty { await refresh() } }
    }

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

    func connect() async {
        guard let v = chosen, let token = account.token else { return }
        await run("Checking the password…") {
            let r = try await SyncOnlyVaults.unlock(api: account.api, token: token, vault: v, password: vaultPassword,
                                                    deviceName: deviceName, accountEmail: account.email)
            let mv = try account.syncOnly.connect(binding: r.binding, key: r.key)
            vaultPassword = ""
            vault.openManaged(mv)
            dismiss()
        }
    }
}

/// Status and management for sync-only vaults: sync now, pause, disconnect, delete the local copy.
struct ManageSyncScreen: View {
    @EnvironmentObject private var vault: MobileVault
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete: ManagedVault?
    @State private var connecting = false

    var body: some View {
        List {
            if let v = vault.managed {
                Section {
                    LabeledContent("Remote vault", value: v.name)
                    LabeledContent("Account", value: v.accountEmail)
                    if let s = vault.syncStatus {
                        Label(s.text, systemImage: s.symbol).foregroundStyle(s.isProblem ? .orange : .primary)
                    }
                    if vault.isConnected(v) {
                        Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") { vault.syncNow() }
                        Button(vault.syncPaused ? "Resume" : "Pause", systemImage: vault.syncPaused ? "play" : "pause") { vault.setSyncPaused(!vault.syncPaused) }
                        if case .needsAttention = vault.syncStatus?.phase {
                            Button("Continue Anyway", systemImage: "exclamationmark.triangle") { vault.confirmSyncAction() }
                        }
                        Button("Disconnect (Keep Local Copy)", systemImage: "icloud.slash") { vault.disconnectSync() }
                    } else {
                        Button("Reconnect…", systemImage: "icloud") { connecting = true }
                    }
                } header: { Text("This vault") } footer: {
                    Text("Syncs while Onyx is open, and for a short while after you leave it. Disconnecting keeps the files here; nothing is deleted in Obsidian Sync.")
                }
            }
            let all = vault.managedVaults
            if !all.isEmpty {
                Section("Sync-only vaults on this device") {
                    ForEach(all) { v in
                        HStack {
                            Image(systemName: vault.isConnected(v) ? "icloud" : "icloud.slash").foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text(v.name)
                                Text(vault.managed?.id == v.id ? "Open" : (vault.isConnected(v) ? "Syncs while open" : "Not syncing"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if vault.managed?.id != v.id { Button("Open") { vault.openManaged(v); dismiss() }.buttonStyle(.borderless) }
                        }
                        .swipeActions { Button("Delete", role: .destructive) { confirmDelete = v } }
                        .contextMenu { Button("Delete Local Copy…", systemImage: "trash", role: .destructive) { confirmDelete = v } }
                    }
                }
            }
            Section {
                Button("Connect Another Vault…", systemImage: "plus") { connecting = true }
            }
        }
        .navigationTitle("Obsidian Sync")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete the local copy of “\(confirmDelete?.name ?? "")”?", isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("Delete Local Copy", role: .destructive) {
                if let v = confirmDelete { vault.removeLocalCopy(v) }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            let unsynced = confirmDelete?.id == vault.managed?.id && vault.syncStatus.map { if case .synced = $0.phase { return false }; return true } == true
            Text("This removes the vault’s files from this device and stops syncing it. The vault in Obsidian Sync and your other devices keep everything."
                 + (unsynced ? " This vault isn’t fully synced right now, so changes made here since the last sync could be lost." : ""))
        }
        .sheet(isPresented: $connecting) { NavigationStack { SyncConnectScreen().environmentObject(vault) } }
    }
}
