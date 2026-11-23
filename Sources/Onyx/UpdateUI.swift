import SwiftUI
import AppKit
import OnyxCore

/// Auto-update from GitHub Releases: check on launch and every six hours, plus Onyx ▸ Check for Updates….
@MainActor
final class UpdateController {
    static let shared = UpdateController()
    static let interval: TimeInterval = 6 * 60 * 60

    private var timer: Timer?
    private var inProgress = false
    private var window: NSWindow?
    private var updater: Updater?

    /// Background checking. Skips unpackaged builds, screenshot/self-test hooks, and Settings ▸ Updates off.
    func start() {
        if Self.shouldSkipAutomatic { return }
        updater = Updater.live()
        guard updater != nil, UpdatePrefs.automaticEnabled() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.check(interactive: false)
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check(interactive: false) }
        }
    }

    /// `interactive` is the menu item: show a result even when already up to date, and offer a skipped version again.
    func check(interactive: Bool) {
        if updater == nil { updater = Updater.live() }
        guard let updater else {
            if interactive { showMessage("This build can’t be updated in place. Install a release build of Onyx, then try again.") }
            return
        }
        if Self.shouldSkipAutomatic, !interactive { return }
        guard !inProgress else { return }
        inProgress = true
        if interactive { showChecking() }
        Task { @MainActor in
            defer { inProgress = false }
            do {
                let decision = try await updater.evaluate(respectSkip: !interactive)
                switch decision {
                case .upToDate:
                    if interactive { showMessage("Onyx is up to date (\(updater.currentVersion.description)).") }
                case .skipped:
                    break
                case .noAsset:
                    if interactive { showMessage("The latest release has no macOS download yet.") }
                case .available(let rel):
                    if Updater.isTranslocated(updater.appURL) {
                        showMessage(UpdateError.translocated.localizedDescription)
                    } else {
                        showAvailable(rel, updater: updater)
                    }
                }
            } catch {
                if interactive { showMessage(error.localizedDescription) }
                else { print("[update] \(error.localizedDescription)") }
            }
        }
    }

    static var shouldSkipAutomatic: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["ONYX_UPDATE_DISABLE"] != nil { return true }
        if env["ONYX_SHOT_QUIET"] == "1" { return true }
        if env["ONYX_KEY_SELFTEST"] != nil { return true }
        if env["ONYX_DUMP_MENUS"] != nil { return true }
        if env["ONYX_SCROLL_TEST"] != nil { return true }
        if env["ONYX_TYPE_TEST"] != nil { return true }
        return false
    }

    func skip(_ release: GitHubRelease) {
        (updater ?? Updater.live())?.skip(release)
        closeWindow()
    }

    func install(_ release: GitHubRelease, updater: Updater, binding: Binding<UpdateSheet.Phase>) {
        binding.wrappedValue = .working("Downloading…")
        Task { @MainActor in
            do {
                try await updater.install(release) { phase in
                    Task { @MainActor in binding.wrappedValue = .working(phase) }
                }
                try Self.relaunch(at: updater.appURL)
                NSApp.terminate(nil)
            } catch {
                binding.wrappedValue = .failed(error.localizedDescription)
            }
        }
    }

    /// Detached helper: wait until this process is gone, then open the (now replaced) app.
    static func relaunch(at app: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let quoted = shellQuote(app.path)
        let inner = "while /usr/bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /bin/sleep 0.3; /usr/bin/open \(quoted)"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "nohup /bin/sh -c \(shellQuote(inner)) >/dev/null 2>&1 &"]
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 { throw UpdateError.downloadFailed }
    }

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func showChecking() {
        present(UpdateSheet(kind: .checking, onLater: { [weak self] in self?.closeWindow() }), size: CGSize(width: 380, height: 140))
    }

    private func showMessage(_ text: String) {
        present(UpdateSheet(kind: .message(text), onLater: { [weak self] in self?.closeWindow() }), size: CGSize(width: 420, height: 180))
    }

    private func showAvailable(_ release: GitHubRelease, updater: Updater) {
        let current = updater.currentVersion
        present(
            UpdateSheet(
                kind: .available(release, current: current),
                onLater: { [weak self] in self?.closeWindow() },
                onSkip: { [weak self] in self?.skip(release) },
                onInstall: { [weak self] binding in self?.install(release, updater: updater, binding: binding) }
            ),
            size: CGSize(width: 480, height: 420)
        )
    }

    private func present<V: View>(_ view: V, size: CGSize) {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "Onyx Update"
            w.isReleasedWhenClosed = false
            w.level = .normal
            w.isMovableByWindowBackground = true
            window = w
        }
        guard let window else { return }
        window.setContentSize(size)
        window.contentViewController = NSHostingController(rootView: view.frame(width: size.width, height: size.height))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeWindow() {
        window?.orderOut(nil)
        window?.contentViewController = nil
    }
}

struct UpdateSheet: View {
    enum Kind {
        case checking
        case message(String)
        case available(GitHubRelease, current: Semver)
    }
    enum Phase: Equatable {
        case idle
        case working(String)
        case failed(String)
    }

    let kind: Kind
    var onLater: () -> Void = {}
    var onSkip: () -> Void = {}
    var onInstall: (Binding<Phase>) -> Void = { _ in }
    @State private var phase: Phase = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch kind {
            case .checking:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Checking for updates…").font(Theme.serif(16))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            case .message(let text):
                Text("Onyx").font(Theme.serif(20, bold: true)).foregroundStyle(Color.ink)
                Text(text).font(.system(size: 13)).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
                Spacer()
                HStack {
                    Spacer()
                    Button("OK", action: onLater).keyboardShortcut(.defaultAction)
                }
            case .available(let rel, let current):
                Text("Onyx \(rel.version.description) is available")
                    .font(Theme.serif(20, bold: true))
                    .foregroundStyle(Color.ink)
                Text("You have \(current.description).")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.muted)
                notes(rel.body, tag: rel.tag)
                if case .failed(let err) = phase {
                    Text(err).font(.system(size: 12)).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true)
                } else if case .working(let s) = phase {
                    HStack(spacing: 8) { ProgressView(); Text(s).font(.system(size: 12)).foregroundStyle(Color.muted) }
                }
                HStack {
                    Button("Skip This Version", action: onSkip).disabled(isWorking)
                    Spacer()
                    Button("Later", action: onLater).disabled(isWorking)
                    Button("Install and Relaunch") { onInstall($phase) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isWorking)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.paper)
    }

    var isWorking: Bool { if case .working = phase { return true }; return false }

    @ViewBuilder
    func notes(_ body: String, tag: String) -> some View {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        ScrollView {
            Group {
                if text.isEmpty {
                    Text("No release notes.")
                        .font(.system(size: TypeScale.body))
                        .foregroundStyle(Color.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ReleaseNotesView(blocks: ReleaseNotes.blocks(from: text, tag: tag))
                }
            }
            .textSelection(.enabled)
        }
        .padding(10)
        .background(Color.paperAlt)
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Color.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .frame(maxHeight: .infinity)
        .environment(\.openURL, OpenURLAction { url in
            NSWorkspace.shared.open(url)
            return .handled
        })
    }
}

/// Formatted GitHub release notes: section labels, nested lists, and inline Markdown.
struct ReleaseNotesView: View {
    let blocks: [ReleaseNotes.Block]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { i, block in
                blockView(block)
                    .padding(.top, topPad(i))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func topPad(_ i: Int) -> CGFloat {
        if i == 0 { return 0 }
        switch (blocks[i - 1], blocks[i]) {
        case (.listItem, .listItem): return Space.xs
        case (_, .heading): return Space.l
        default: return Space.s
        }
    }

    @ViewBuilder
    func blockView(_ block: ReleaseNotes.Block) -> some View {
        switch block {
        case .heading(_, let text):
            Text(text)
                .font(.system(size: TypeScale.label, weight: .semibold))
                .foregroundStyle(Color.muted)
                .tracking(0.6)
                .textCase(.uppercase)
        case .paragraph(let text):
            inline(text)
        case .listItem(let depth, let ordered, let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(ordered ? "\(marker)." : "•")
                    .font(.system(size: TypeScale.body).monospacedDigit())
                    .foregroundStyle(depth == 0 ? Color.ink : Color.muted)
                    .frame(width: ordered ? 18 : 12, alignment: .trailing)
                inline(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, CGFloat(depth) * 18)
        case .rule:
            Divider().overlay(Color.hairline).padding(.vertical, Space.xs)
        }
    }

    func inline(_ markdown: String) -> some View {
        Text(Self.styled(ReleaseNotes.attributed(markdown)))
            .font(.system(size: TypeScale.body))
            .foregroundStyle(Color.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Ink, slate links, and a quiet wash behind inline code.
    static func styled(_ raw: AttributedString) -> AttributedString {
        var s = raw
        let body = Font.system(size: TypeScale.body)
        let code = Font.system(size: TypeScale.small, design: .monospaced)
        let strong = Font.system(size: TypeScale.body, weight: .semibold)
        let emphasis = Font.system(size: TypeScale.body).italic()
        for run in s.runs {
            let r = run.range
            s[r].foregroundColor = Color.ink
            s[r].font = body
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) {
                s[r].font = code
                s[r].backgroundColor = Color.ink.opacity(0.06)
            } else if intent.contains(.stronglyEmphasized) && intent.contains(.emphasized) {
                s[r].font = Font.system(size: TypeScale.body, weight: .semibold).italic()
            } else if intent.contains(.stronglyEmphasized) {
                s[r].font = strong
            } else if intent.contains(.emphasized) {
                s[r].font = emphasis
            }
            if run.link != nil {
                s[r].foregroundColor = Color.cursorBlue
                s[r].underlineStyle = .single
            }
        }
        return s
    }
}
