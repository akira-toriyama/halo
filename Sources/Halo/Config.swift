import AppKit

// halo configuration. Sensible defaults; optionally overridden by
// ~/.config/halo/config.toml. Flat `key = value` lines (no sections) —
// unknown / malformed keys are ignored and keep the default, so a typo
// can never break the ring (facet's clamp-to-default philosophy). Read
// once at launch.
struct HaloConfig {
    var color: NSColor       = NSColor(hex: "#39C5C8") ?? .systemTeal   // resting ring
    var width: CGFloat       = 3
    var cornerRadius: CGFloat = 10
    var pad: CGFloat         = 4                                        // gap window→ring
    var glow: Bool           = true
    var flashColor: NSColor  = NSColor(hex: "#FF5CA8") ?? .systemPink   // focus-change pulse
    var flashWidth: CGFloat  = 5                                        // extra width at flash peak
    var flashMs: Int         = 400                                      // 0 disables the flash
    var minSize: CGFloat     = 80                                       // ignore tiny popups
    var excludedApps: [String] = []                                    // owner names to skip

    static func load() -> HaloConfig {
        var c = HaloConfig()
        let path = ("~/.config/halo/config.toml" as NSString).expandingTildeInPath
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return c }

        for rawLine in text.split(separator: "\n") {
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first.map(String.init) ?? ""
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            switch key {
            case "color":         if let v = NSColor(hex: value) { c.color = v }
            case "flash_color":   if let v = NSColor(hex: value) { c.flashColor = v }
            case "width":         if let v = Double(value) { c.width = CGFloat(v) }
            case "flash_width":   if let v = Double(value) { c.flashWidth = CGFloat(v) }
            case "corner_radius": if let v = Double(value) { c.cornerRadius = CGFloat(v) }
            case "pad":           if let v = Double(value) { c.pad = CGFloat(v) }
            case "min_size":      if let v = Double(value) { c.minSize = CGFloat(v) }
            case "flash_ms":      if let v = Int(value) { c.flashMs = max(0, v) }
            case "glow":          c.glow = (value == "true")
            case "exclude":       c.excludedApps = value.split(separator: ",")
                                      .map { $0.trimmingCharacters(in: .whitespaces) }
                                      .filter { !$0.isEmpty }
            default: break
            }
        }
        return c
    }
}

extension NSColor {
    /// `#RRGGBB` (or `RRGGBB`) → sRGB color; nil on malformed input.
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green:   CGFloat((v >> 8) & 0xFF) / 255,
                  blue:    CGFloat(v & 0xFF) / 255,
                  alpha:   1)
    }
}
