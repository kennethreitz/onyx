import AppKit
import OnyxCore
import SwiftUI

/// A calm, readable panel of recent git and Obsidian Sync activity. Esc or the dimmer closes it.
struct SyncLogView: View {
    var store: SyncLogStore?
    var dismiss: () -> Void
    private var rows: [SyncLogEntry] { store.map { Array($0.entries.reversed()) } ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.hairline)
            if rows.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { e in
                            row(e)
                            Divider().overlay(Color.hairline.opacity(0.7))
                        }
                    }
                }
                .thinScrollers()
                .frame(maxHeight: 440)
            }
        }
        .frame(width: 720)
        .panelChrome()
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Sync Log").font(Theme.serif(20)).foregroundStyle(Color.ink)
                Text("Git and Obsidian Sync").font(.system(size: 11)).foregroundStyle(Color.faint)
            }
            Spacer(minLength: 8)
            if store != nil {
                HeaderButton("Copy", help: "Copy the log") { copy() }
                HeaderButton("Reveal in Finder", help: "Show the log file in Finder") { reveal() }
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.muted).frame(width: 22, height: 22)
            }
            .buttonStyle(.plain).help("Close (Esc)")
        }
        .padding(.leading, 18).padding(.trailing, 12).padding(.vertical, 12)
    }

    var empty: some View {
        VStack(spacing: 6) {
            Text("No sync activity yet.")
                .font(.system(size: 13.5)).foregroundStyle(Color.muted)
            Text("Git and Obsidian Sync will appear here as they happen.")
                .font(.system(size: 11.5)).foregroundStyle(Color.faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }

    func row(_ e: SyncLogEntry) -> some View {
        let alert = e.isAlert
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(Self.timeLabel(e.date))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Color.faint)
                .frame(width: 108, alignment: .leading)
            Text(e.source.label)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.muted)
                .frame(width: 108, alignment: .leading)
                .lineLimit(1)
            Text(e.event.label)
                .font(.system(size: 11.5, weight: alert ? .medium : .regular))
                .foregroundStyle(alert ? Color.orange.opacity(0.9) : Color.ink.opacity(0.82))
                .frame(width: 92, alignment: .leading)
            Text(e.detail.isEmpty ? "—" : e.detail)
                .font(.system(size: 11.5))
                .foregroundStyle(alert ? Color.ink.opacity(0.82) : Color.muted)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.vertical, 7)
        .background(alert ? Color.orange.opacity(0.06) : .clear)
    }

    func copy() {
        guard let store else { return }
        let text = store.renderedText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text.isEmpty ? "No sync activity yet.\n" : text, forType: .string)
    }
    func reveal() {
        guard let store else { return }
        let url = store.fileURL
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func timeLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return d.formatted(date: .omitted, time: .standard) }
        return d.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct HeaderButton: View {
    var title: String
    var help: String
    var action: () -> Void
    init(_ title: String, help: String, action: @escaping () -> Void) {
        self.title = title; self.help = help; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 11.5)).foregroundStyle(Color.muted)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.ink.opacity(0.05)))
        }
        .buttonStyle(.plain).help(help)
    }
}
