import AppKit
import Effects

// halo configuration. Mirrors facet's `[border]` config surface (same
// keys / semantics) so the two feel the same: an `effect` palette layered
// on a base color, with glow / width / cycle / breath. Read once at launch
// from ~/.config/halo/config.toml; `[section]` headers are skipped (halo's
// config is flat), unknown / malformed keys keep their default (facet's
// clamp-to-default — a typo can never break the ring).
struct HaloConfig {
    // --- border theme (mirror of facet [border]) ---
    var effect: String       = "neon"     // off | neon | cyber | vapor | kawaii | rainbow | chomp | random
    var glow: Bool           = true
    var width: CGFloat       = 3
    var cycleSeconds: CGFloat = 6          // rainbow / cycle-colors / breath period
    var cycleColors: Bool    = false       // loop a non-rainbow effect through its flash palette
    var minWidth: CGFloat?   = nil         // set both min/max (max>min) → width breathes
    var maxWidth: CGFloat?   = nil
    var color: NSColor       = NSColor(hex: "#39C5C8") ?? .systemTeal   // resting color when effect = off

    // --- halo-specific geometry / scope ---
    var cornerRadius: CGFloat = 10
    var pad: CGFloat         = 4            // gap window edge → ring
    var minSize: CGFloat     = 80          // ignore tiny popups
    var excludedApps: [String] = []

    // --- focus shake (moves the real window — needs Accessibility) ---
    var shake: Bool             = true     // jiggle the focused window on focus change
    var shakeAmplitude: CGFloat = 10       // peak horizontal swing (pt)
    var shakeDurationMs: Double = 250      // total shake duration (ms)

    // --- focus sound (plays an audio cue on focus change — no permission) ---
    var sound: String       = ""           // audio file path; empty = off
    var soundVolume: Double  = 0.3          // 0…1

    // --- line-pets (arcade sprites orbiting the ring; opt-in, no permission) ---
    var linePets: [LinePet]  = []          // e.g. "chomp, ghost"; empty = off
    var petScale: CGFloat    = 1.5         // pet size ×multiplier (halo has no font-size to scale from)
    var petLapSeconds: CGFloat = 8         // seconds to orbit the ring once — window-size-independent
                                            // (constant pt/s would crawl on a big window, sprint on a small one)

    static func load() -> HaloConfig {
        var c = HaloConfig()
        let path = ("~/.config/halo/config.toml" as NSString).expandingTildeInPath
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return c }

        for rawLine in text.split(separator: "\n") {
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            if line.isEmpty || line.hasPrefix("[") { continue }   // skip blanks + [section] headers
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            switch key {
            case "effect":        if canonicalEffectNames.contains(value.lowercased()) { c.effect = value.lowercased() }
            case "glow":          c.glow = (value == "true")
            case "width":         if let v = Double(value) { c.width = CGFloat(v) }
            case "cycle-seconds": if let v = Double(value) { c.cycleSeconds = max(1, CGFloat(v)) }
            case "cycle-colors":  c.cycleColors = (value == "true")
            case "min-width":     if let v = Double(value) { c.minWidth = CGFloat(v) }
            case "max-width":     if let v = Double(value) { c.maxWidth = CGFloat(v) }
            case "color":         if let v = NSColor(hex: value) { c.color = v }
            case "corner-radius": if let v = Double(value) { c.cornerRadius = CGFloat(v) }
            case "pad":           if let v = Double(value) { c.pad = CGFloat(v) }
            case "min-size":      if let v = Double(value) { c.minSize = CGFloat(v) }
            case "exclude":       c.excludedApps = value.split(separator: ",")
                                      .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            case "shake":             c.shake = (value == "true")
            case "shake-amplitude":   if let v = Double(value) { c.shakeAmplitude = CGFloat(v) }
            case "shake-duration-ms": if let v = Double(value) { c.shakeDurationMs = max(1, v) }
            case "sound":             c.sound = value
            case "sound-volume":      if let v = Double(value) { c.soundVolume = max(0, min(1, v)) }
            case "line-pets":         c.linePets = value
                                          .trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                                          .split(separator: ",")
                                          .compactMap { LinePet(rawValue: $0
                                              .trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'"))
                                              .lowercased()) }
            case "pet-scale":         if let v = Double(value) { c.petScale = max(0.1, CGFloat(v)) }
            case "pet-lap-seconds":   if let v = Double(value) { c.petLapSeconds = max(0.5, CGFloat(v)) }
            default: break
            }
        }
        return c
    }
}

extension NSColor {
    /// `#RRGGBB` (or `RRGGBB`) string → sRGB color; nil on malformed input.
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green:   CGFloat((v >> 8) & 0xFF) / 255,
                  blue:    CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
