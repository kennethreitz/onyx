import SwiftUI

@main
struct OnyxMobileApp: App {
    @StateObject private var vault = MobileVault()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vault)
                .task { vault.restore() }
                .onOpenURL { vault.handleURL($0) }
                .onChange(of: scenePhase) { _, phase in
                    // Sync-only vaults sync while Onyx is in front, and get a short grace period when it leaves.
                    switch phase {
                    case .active: vault.syncNow()
                    case .background: vault.syncBeforeSuspend()
                    default: break
                    }
                }
        }
    }
}
