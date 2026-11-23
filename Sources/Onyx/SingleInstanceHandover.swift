import AppKit
import OnyxCore

/// At launch, ask other packaged Onyx processes (same bundle identifier) to
/// quit gracefully, then wait until they have exited so session state is
/// written before this process restores it.
enum SingleInstanceHandover {
    static func takeOverIfNeeded(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        selfPID: pid_t = ProcessInfo.processInfo.processIdentifier,
        running: (String) -> [NSRunningApplication] = { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
    ) {
        let allow = defaults.bool(forKey: SingleInstance.allowMultipleDefaultsKey)
        guard SingleInstance.shouldTakeOver(
            environment: environment,
            defaultsAllowMultiple: allow,
            bundleIdentifier: bundleIdentifier
        ) else { return }
        guard let id = SingleInstance.bundleIdentifierForTakeover(bundleIdentifier) else { return }
        let others = running(id).filter { $0.processIdentifier != selfPID }
        guard !others.isEmpty else { return }
        for app in others {
            // terminate() goes through applicationShouldTerminate and
            // willTerminate. OnyxApp.boot() already flushes unsaved notes,
            // the split layout, and git on willTerminate.
            _ = app.terminate()
        }
        let deadline = Date().addingTimeInterval(SingleInstance.quitTimeout)
        while Date() < deadline {
            if others.allSatisfy(\.isTerminated) { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        // Still alive: leave it. Never forceTerminate — unsaved notes or a
        // finishForQuit git push may still be in flight (SingleInstance.forceTerminateIfStillAlive).
    }
}
