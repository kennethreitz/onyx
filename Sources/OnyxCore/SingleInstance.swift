import Foundation

/// Launch policy: a packaged Onyx asks any other copy with the same bundle
/// identifier to quit before it opens a vault or restores session state.
///
/// The other copy quits through the normal `terminate()` path, which fires
/// `willTerminate` and flushes unsaved notes, the split layout, and git.
/// This process waits for it to exit so those writes land first. It never
/// force-kills the other copy: if the wait times out (it may still be
/// saving, or finishing a git quit that can take up to 8 seconds), both
/// may briefly run.
///
/// Test, screenshot, and harness launches must not quit a running Onyx
/// someone is using. Set `ONYX_ALLOW_MULTIPLE=1`, the hidden default
/// `onyx.allowMultipleInstances`, or any of the usual test hooks.
public enum SingleInstance {
    public static let allowMultipleEnvironmentKey = "ONYX_ALLOW_MULTIPLE"
    public static let allowMultipleDefaultsKey = "onyx.allowMultipleInstances"

    /// Environment keys that mean this launch is a test, screenshot, or
    /// harness run. If any is set, do not ask another Onyx to quit.
    public static let testHookKeys: [String] = [
        "ONYX_NO_DEFAULT_VAULT",
        "ONYX_SHOT_QUIET",
        "ONYX_TYPE_TEST",
        "ONYX_KEY_SELFTEST",
        "ONYX_SCROLL_TEST",
        "ONYX_OPEN_SETTINGS",
        "ONYX_DUMP_MENUS",
        "ONYX_BASES_EDIT",
    ]

    /// How long the new process waits after `terminate()`. `GitSync.finishForQuit`
    /// can block up to 8 seconds (commit plus a short push), so a 3-second
    /// wait would often race with those writes.
    public static let quitTimeout: TimeInterval = 10

    /// If the other process is still alive after `quitTimeout`, leave it.
    /// Never `forceTerminate`: unsaved notes may still be flushing.
    public static let forceTerminateIfStillAlive = false

    /// `true` when this launch should leave other Onyx processes alone.
    public static func allowsMultiple(environment: [String: String],
                                      defaultsAllowMultiple: Bool = false) -> Bool {
        if defaultsAllowMultiple { return true }
        if isEnabledFlag(environment[allowMultipleEnvironmentKey]) { return true }
        for key in testHookKeys where environment[key] != nil { return true }
        return false
    }

    /// `true` when this launch should ask other copies with the same bundle
    /// identifier to quit. A process with no bundle identifier (an unpackaged
    /// `swift run` or `.build/debug/Onyx` binary) never takes over: it must
    /// not go looking for `org.kennethreitz.onyx` and quit the installed app.
    public static func shouldTakeOver(environment: [String: String],
                                      defaultsAllowMultiple: Bool = false,
                                      bundleIdentifier: String?) -> Bool {
        guard bundleIdentifierForTakeover(bundleIdentifier) != nil else { return false }
        return !allowsMultiple(environment: environment, defaultsAllowMultiple: defaultsAllowMultiple)
    }

    /// The identifier used to find other running copies. Nil when this
    /// process has none (unpackaged binaries).
    public static func bundleIdentifierForTakeover(_ bundleIdentifier: String?) -> String? {
        guard let id = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            return nil
        }
        return id
    }

    /// Treat a set environment value as on, unless it is a clear "no".
    public static func isEnabledFlag(_ raw: String?) -> Bool {
        guard let raw else { return false }
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if v.isEmpty { return false }
        switch v {
        case "0", "false", "no", "off": return false
        default: return true
        }
    }
}
