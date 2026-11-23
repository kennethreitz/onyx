import Foundation

/// Policy for the Mac app's window lifecycle: closing the last vault window
/// leaves the process running, like a normal Mac app. Dock click and
/// File ▸ New Window restore that window with the previous session.
public enum WindowLifecycle: Sendable {
    /// Value for `applicationShouldTerminateAfterLastWindowClosed`. ⌘Q and
    /// a second packaged Onyx's `terminate()` still quit through the usual path.
    public static let terminateAfterLastWindowClosed = false

    /// Identifier stamped on the vault window (and the SwiftUI `Window` id).
    public static let mainWindowIdentifier = "main"
    public static let settingsWindowIdentifier = "onyx-settings"
    public static let updateWindowTitle = "Onyx Update"

    /// Posted when the vault window is closing, so audio and video players stop.
    public static let stopPlaybackNotification = Notification.Name("onyx.stopPlayback")

    public enum Kind: Equatable, Sendable {
        case vault, settings, update, panel, other
    }

    public static func kind(isPanel: Bool, identifier: String?, title: String) -> Kind {
        if isPanel { return .panel }
        if identifier == settingsWindowIdentifier { return .settings }
        if isSettingsTitle(title) { return .settings }
        if title == updateWindowTitle { return .update }
        if identifier == mainWindowIdentifier { return .vault }
        return .other
    }

    public static func isSettingsTitle(_ title: String) -> Bool {
        title == "Settings" || title.hasSuffix(" Settings") || title.hasPrefix("Settings")
    }

    /// Work to do when a window closes, or when the app is quitting.
    public struct ClosePlan: Equatable, Sendable {
        public var flushUnsavedNotes: Bool
        public var persistSplitLayout: Bool
        public var stopSpeech: Bool
        public var stopAudioPlayback: Bool
        public var finishRecording: Bool
        public var stopObsidianSync: Bool
        public var finishGitForQuit: Bool

        public static let none = ClosePlan(
            flushUnsavedNotes: false, persistSplitLayout: false,
            stopSpeech: false, stopAudioPlayback: false, finishRecording: false,
            stopObsidianSync: false, finishGitForQuit: false
        )
        /// Closing the vault window: save session state, stop playback, keep sync running.
        public static let window = ClosePlan(
            flushUnsavedNotes: true, persistSplitLayout: true,
            stopSpeech: true, stopAudioPlayback: true, finishRecording: true,
            stopObsidianSync: false, finishGitForQuit: false
        )
        /// ⌘Q or a single-instance handoff: the existing willTerminate work.
        public static let quit = ClosePlan(
            flushUnsavedNotes: true, persistSplitLayout: true,
            stopSpeech: true, stopAudioPlayback: true, finishRecording: true,
            stopObsidianSync: true, finishGitForQuit: true
        )
    }

    public static func closePlan(kind: Kind, isQuit: Bool) -> ClosePlan {
        if isQuit { return .quit }
        if kind == .vault { return .window }
        return .none
    }

    public enum ReopenPlan: Equatable, Sendable {
        /// A vault window already exists (maybe miniaturized): order it front.
        case focusExisting
        /// No vault window: create one, restoring the previous session.
        case openNew
    }

    public static func reopenPlan(hasVaultWindow: Bool) -> ReopenPlan {
        hasVaultWindow ? .focusExisting : .openNew
    }
}
