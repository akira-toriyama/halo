// Border effect palettes — ported from facet's FacetView/BorderEffect.swift
// + the NSColor(hex:) / blendThrough helpers from FacetView/Palette.swift +
// Theme.swift. halo only needs the BORDER theme (the `effect` axis), not
// facet's full panel palette (text/dim/font/…), so only those parts are
// lifted. Kept in sync by hand (sibling-repo duplication, not a shared lib —
// rule of three).

import AppKit

public extension NSColor {
    /// RGB hex as `0xRRGGBB`. Alpha defaults to 1.
    convenience init(hex: UInt32, _ a: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                  green:   CGFloat((hex >> 8)  & 0xff) / 255,
                  blue:    CGFloat( hex        & 0xff) / 255,
                  alpha:   a)
    }
}

/// One border effect: a resting color + the palette a flash blinks
/// through. `cycles` slowly rotates the steady hue (rainbow).
public struct BorderEffect {
    public let steady: NSColor
    public let flash: [NSColor]
    public let cycles: Bool
    public init(steady: NSColor, flash: [NSColor], cycles: Bool = false) {
        self.steady = steady; self.flash = flash; self.cycles = cycles
    }
}

/// Map a `effect` name to its effect, or `nil` for "off" / unknown
/// (BorderFX then falls back to the plain base color). Names match
/// facet's `[border] effect` set. (halo is single-threaded on the main
/// run loop, so no @MainActor isolation is needed — unlike facet.)
public func borderEffectFor(_ name: String) -> BorderEffect? {
    switch name.lowercased() {
    case "neon":   // Tokyo-Night blue at rest; electric neon flashes.
        return BorderEffect(steady: NSColor(hex: 0x7AA2F7),
            flash: [0x00E5FF, 0xFF00FF, 0x39FF14, 0xFE019A, 0x04D9FF, 0xBC13FE].map { NSColor(hex: $0) })
    case "cyber":  // Teal/aqua matrix.
        return BorderEffect(steady: NSColor(hex: 0x00FFD0),
            flash: [0x00FFD0, 0x00E5FF, 0x39FF14, 0x14FFEC, 0x00FF9C, 0x0AFFFF].map { NSColor(hex: $0) })
    case "vapor":  // Synthwave pink → purple → cyan.
        return BorderEffect(steady: NSColor(hex: 0xFF6AD5),
            flash: [0xFF6AD5, 0xC774E8, 0xAD8CFF, 0x8795E8, 0x94D0FF, 0xFF71CE].map { NSColor(hex: $0) })
    case "kawaii": // Soft pastels.
        return BorderEffect(steady: NSColor(hex: 0xFFB3D9),
            flash: [0xFFB3D9, 0xD9B3FF, 0xB3FFD9, 0xFFE0B3, 0xB3E0FF, 0xFFC6E0].map { NSColor(hex: $0) })
    case "rainbow": // Full spectrum; cycles the resting hue.
        return BorderEffect(steady: NSColor(hex: 0xFF3B30),
            flash: [0xFF0000, 0xFF7F00, 0xFFFF00, 0x00FF00, 0x00FFFF, 0x0000FF, 0x8B00FF].map { NSColor(hex: $0) },
            cycles: true)
    case "random":
        return borderEffectFor(["neon", "cyber", "vapor", "kawaii", "rainbow"].randomElement() ?? "neon")
    default:        // "off" or unknown
        return nil
    }
}

/// Canonical effect names (for typo-tolerant config + docs).
public let canonicalEffects = ["off", "neon", "cyber", "vapor", "kawaii", "rainbow", "random"]

/// Smoothly loop through `colors` by `phase` (0…1), blending neighbours.
public func blendThrough(_ colors: [NSColor], at phase: CGFloat) -> NSColor {
    let n = colors.count
    guard n > 1 else { return colors.first ?? .white }
    let p = phase - floor(phase)
    let scaled = p * CGFloat(n)
    let i = Int(scaled) % n
    let t = scaled - floor(scaled)
    return colors[i].blended(withFraction: t, of: colors[(i + 1) % n]) ?? colors[i]
}
