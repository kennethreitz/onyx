import Foundation
import SwiftUI
import OnyxCore

/// Cached link index and atlas layouts, rebuilt off the main thread when the vault changes.
@MainActor
final class MobileGraphStore: ObservableObject {
    @Published var index: GraphIndex?
    @Published var atlas: Atlas?
    private var builtGen = -1
    private var atlasKey = ""
    private var building = false

    func ensureIndex(_ snap: VaultSnapshot, gen: Int) async {
        guard builtGen != gen, !building else { return }
        building = true
        let g = await Task.detached(priority: .userInitiated) { GraphIndex.build(snap) }.value
        index = g
        builtGen = gen
        atlasKey = ""
        building = false
    }

    func ensureAtlas(grouping: Atlas.Grouping, filterKey: String, include: @escaping @Sendable (Int) -> Bool) async {
        guard let g = index else { return }
        let key = "\(builtGen)|\(grouping.rawValue)|\(filterKey)"
        guard key != atlasKey else { return }
        atlasKey = key
        let a = await Task.detached(priority: .userInitiated) {
            Atlas.build(g, grouping: grouping, include: include, includeOrphans: false)
        }.value
        if atlasKey == key { atlas = a }
    }

    func invalidate() {
        index = nil
        atlas = nil
        builtGen = -1
        atlasKey = ""
        building = false
    }
}

extension MobileVault {
    /// Open the focus graph (the current note at the center) or the whole-vault atlas
    /// in the detail column, and select the Graph sidebar tab.
    func openGraph(atlas: Bool) {
        guard root != nil, snapshot != nil else { return }
        graphAtlas = atlas
        showGraph = true
        libraryTab = .graph
        prefersDetail = true
        showCommandPalette = false
    }

    /// Leave the graph and return to the open note (or the sidebar if none is selected).
    func closeGraph() {
        showGraph = false
        if libraryTab == .graph { libraryTab = .notes }
        prefersDetail = selectedPath != nil
    }
}
