import CoreGraphics

/// Line-pet orbit speed. Derived from a desired LAP TIME rather than a
/// constant pt/s, so the orbit feels equally lively at any window size — a
/// constant pt/s would crawl on a big window and sprint on a small one.
public enum PetOrbit {
    /// Shortest lap the config accepts (`pet-lap-seconds` floors here too).
    public static let minLapSeconds: CGFloat = 0.5

    /// pt/s that circles `rect`'s perimeter once per `lapSeconds`.
    public static func speed(around rect: CGRect, lapSeconds: CGFloat) -> CGFloat {
        let perimeter = 2 * (rect.width + rect.height)
        return perimeter / max(minLapSeconds, lapSeconds)
    }
}
