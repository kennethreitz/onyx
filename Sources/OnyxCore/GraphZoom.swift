import Foundation

/// Shared zoom limits for the focus graph and atlas.
///
/// The floor is half the current fitted zoom, so the whole graph stays on screen
/// with a comfortable margin instead of shrinking to a speck. The ceiling is the
/// existing 12× cap. Callers should clamp values, not allow overshoot and snap back.
public enum GraphZoom {
    public static let max: Double = 12
    /// How far past a fitted view you may zoom out (0.5 = half the fitted size).
    public static let minFitFraction: Double = 0.5

    public static func minimum(fit: Double) -> Double {
        let f = (fit.isFinite && fit > 0) ? fit : 1
        return f * minFitFraction
    }

    public static func clamp(_ zoom: Double, fit: Double) -> Double {
        let lo = minimum(fit: fit)
        if !zoom.isFinite { return zoom > 0 ? max : lo }   // +∞ → max, NaN/−∞ → floor
        return min(max, Swift.max(lo, zoom))
    }
}
