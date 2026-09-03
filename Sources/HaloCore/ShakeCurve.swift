import CoreGraphics

/// The focus-shake's horizontal displacement over wall-clock progress:
///
///   x(p) = origin.x + amplitude · sin(2π·cycles·p) · (1 − p),  p ∈ [0,1]
///
/// The `(1 − p)` envelope decays the swing to zero AND guarantees
/// `offset(progress: 1) == 0`, so the final AX write lands on the exact
/// origin — neighbours are never disturbed and a co-running facet just
/// sees the window return to its base frame.
public enum ShakeCurve {
    /// Oscillations across the whole duration.
    public static let cycles: CGFloat = 3.5

    /// Displacement from the origin at `progress` (clamped to 0…1).
    public static func offset(progress: Double, amplitude: CGFloat) -> CGFloat {
        let p = CGFloat(min(1, max(0, progress)))
        return amplitude * sin(2 * .pi * cycles * p) * (1 - p)
    }
}
