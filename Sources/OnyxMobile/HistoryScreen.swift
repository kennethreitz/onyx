import SwiftUI
import OnyxCore

/// Git version history lives on the Mac. The iOS app does not ship git, and we don't fake it.
struct HistoryScreen: View {
    var noteName: String?

    var body: some View {
        ContentUnavailableView {
            Label("Not available on iPhone", systemImage: "clock.arrow.circlepath")
        } description: {
            Text(message)
        }
        .navigationTitle("Version History")
    }

    var message: String {
        let name = noteName.map { "“\($0)”" } ?? "This note"
        return "\(name)’s version history uses git, which isn’t included in the iOS app. Open the vault in Onyx on a Mac (or another git client) to browse or restore earlier versions."
    }
}
