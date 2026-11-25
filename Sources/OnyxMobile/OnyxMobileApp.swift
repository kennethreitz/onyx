import SwiftUI

@main
struct OnyxMobileApp: App {
    @StateObject private var vault = MobileVault()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vault)
                .task { vault.restore() }
        }
    }
}
