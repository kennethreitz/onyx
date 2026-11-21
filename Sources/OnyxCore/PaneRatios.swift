import Foundation

/// Relative widths (or heights) of a flat split-pane group. Ratios always sum to 1.
/// Used by the app to keep pane sizes across a window session; pure so it can be tested.
public enum PaneRatios {
    public static let minPane: Double = 240
    public static let thickness: Double = 0.8

    public static func equal(_ count: Int) -> [Double] {
        guard count > 0 else { return [] }
        return Array(repeating: 1.0 / Double(count), count: count)
    }

    public static func normalized(_ ratios: [Double], count: Int) -> [Double] {
        guard count > 0 else { return [] }
        if count == 1 { return [1] }
        let usable = ratios.count == count && ratios.allSatisfy({ $0 > 0 })
        let r = usable ? ratios : equal(count)
        let s = r.reduce(0, +)
        return s > 0 ? r.map { $0 / s } : equal(count)
    }

    /// Point sizes along the split axis. When the window is too tight for `minPane` each,
    /// the floor shrinks so every pane still fits.
    public static func sizes(_ ratios: [Double], count: Int? = nil, total: Double, minPane: Double = minPane, thickness: Double = thickness) -> [Double] {
        let n = count ?? ratios.count
        guard n > 0 else { return [] }
        if n == 1 { return [max(0, total)] }
        let available = max(0, total - thickness * Double(n - 1))
        let floor = min(minPane, available / Double(n))
        var raw = normalized(ratios, count: n).map { $0 * available }
        for i in raw.indices where raw[i] < floor { raw[i] = floor }
        var overflow = raw.reduce(0, +) - available
        for _ in 0..<16 {
            guard overflow > 0.001 else { break }
            let shrinkable = raw.indices.filter { raw[$0] > floor + 0.001 }
            guard !shrinkable.isEmpty else { break }
            let cut = overflow / Double(shrinkable.count)
            overflow = 0
            for i in shrinkable {
                let take = min(cut, raw[i] - floor)
                raw[i] -= take
                overflow += cut - take
            }
        }
        let head = raw.dropLast().reduce(0, +)
        raw[n - 1] = max(floor, available - head)
        return raw
    }

    /// Split the pane at `index` in half and insert the new half immediately after it.
    public static func splitting(_ ratios: [Double], at index: Int) -> [Double] {
        var r = ratios.isEmpty ? [1.0] : normalized(ratios, count: ratios.count)
        let i = min(max(index, 0), r.count - 1)
        let half = r[i] / 2
        r[i] = half
        r.insert(half, at: i + 1)
        return r
    }

    /// Drop the pane at `index` and give its share to the neighbor on the left (or the right, if it was first).
    public static func removing(_ ratios: [Double], at index: Int) -> [Double] {
        var r = ratios
        guard r.indices.contains(index) else { return normalized(r, count: r.count) }
        let share = r.remove(at: index)
        if r.isEmpty { return [] }
        if r.count == 1 { return [1] }
        r[index > 0 ? index - 1 : 0] += share
        return normalized(r, count: r.count)
    }

    /// Drag the divider between pane `divider` and the next one. `delta` is in points,
    /// positive toward the end of the axis (right for a side-by-side split, down when stacked).
    public static func dragging(_ ratios: [Double], divider: Int, delta: Double, total: Double, minPane: Double = minPane, thickness: Double = thickness) -> [Double] {
        var s = sizes(ratios, total: total, minPane: minPane, thickness: thickness)
        guard s.indices.contains(divider), s.indices.contains(divider + 1) else {
            return normalized(ratios, count: ratios.count)
        }
        let pair = s[divider] + s[divider + 1]
        let lo = min(minPane, pair / 2)
        let left = min(max(s[divider] + delta, lo), pair - lo)
        s[divider] = left
        s[divider + 1] = pair - left
        let available = max(0, total - thickness * Double(max(0, s.count - 1)))
        guard available > 0 else { return normalized(ratios, count: s.count) }
        return s.map { $0 / available }
    }
}
