import Foundation

/// Policy for a pull-down-past-the-top gesture (like iOS pull-to-search) that
/// opens the command palette from a scrolling note.
public enum PullToCommand: Sendable {
    /// How far past the top, in points, the user must pull before release opens the palette.
    public static let threshold: Double = 72

    /// `offsetY` is a scroll view's `contentOffset.y` (negative when overscrolled at the top).
    public static func shouldOpen(offsetY: Double, threshold: Double = Self.threshold) -> Bool {
        offsetY < -threshold
    }

    /// Opacity of the “Command Palette” hint as the user pulls, 0...1.
    public static func hintOpacity(offsetY: Double, threshold: Double = Self.threshold) -> Double {
        guard offsetY < 0 else { return 0 }
        return min(1, abs(offsetY) / threshold)
    }
}
