import AppKit
import ConfigSchema
import Effects
import Toml

// halo configuration. Mirrors facet's `[border]` config surface (same
// keys / semantics) so the two feel the same: an `effect` palette layered
// on a base color, with glow / width / cycle / breath. Read once at launch
// from ~/.config/halo/config.toml; unknown / malformed keys keep their
// default (facet's clamp-to-default — a typo can never break the ring).
//
// Decode is driven by ONE declarative `configSpec` (see
// `HaloConfig+Spec.swift`), which ALSO emits the `config.toml` JSON Schema
// (`halo --emit-schema`) — so the parser and the editor-completion schema
// can never drift. The per-field `apply` closures reproduce the old
// hand-written lowercase/validate/clamp/transform exactly (proven
// byte-identical by the config-schema parity harness).
struct HaloConfig {
    // --- border theme (mirror of facet [border]) ---
    var effect: String       = "neon"     // off | neon | cyber | vapor | kawaii | rainbow | chomp | random
    var glow: Bool           = true
    var width: CGFloat       = 3
    var cycleSeconds: CGFloat = 6          // rainbow / cycle-colors / breath period
                                            // (config key is `color-cycle-ms`; stored in
                                            //  seconds because the 30 Hz tick divides by it)
    var cycleColors: Bool    = false       // loop a non-rainbow effect through its flash palette
    var minWidth: CGFloat?   = nil         // set both min/max (max>min) → width breathes
    var maxWidth: CGFloat?   = nil
    var color: NSColor       = NSColor(HexColor(0x39C5C8))   // resting color when effect = off

    // --- halo-specific geometry / scope ---
    var cornerRadius: CGFloat = 10
    var pad: CGFloat         = 4            // gap window edge → ring
    var minSize: CGFloat     = 80          // ignore tiny popups
    /// `[exclude].apps` — bundle-id globs (family-shared shape; wand's
    /// grammar: `*` / `?`, e.g. "com.apple.finder", "*chrome*").
    var excludedApps: [String] = []

    /// True when `pid`'s app matches an `[exclude].apps` glob. Resolves
    /// the bundle id lazily — only when an exclusion is configured.
    func isExcluded(pid: Int32) -> Bool {
        guard !excludedApps.isEmpty else { return false }
        let bid = NSRunningApplication(processIdentifier: pid)?
            .bundleIdentifier ?? ""
        return excludedApps.contains { globMatch($0, bid) }
    }

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

    /// The user config path (`~/.config/halo/config.toml`, tilde
    /// expanded). The schema sidecar (`HaloConfig.schemaPath`) is written
    /// next to it.
    static var configFilePath: String {
        ("~/.config/halo/config.toml" as NSString).expandingTildeInPath
    }

    /// Read + decode `~/.config/halo/config.toml`. Missing / unreadable →
    /// all defaults. The uniform `[block]` keys are driven by the single
    /// declarative `configSpec` (which ALSO emits the JSON Schema — see
    /// `HaloConfig+Spec.swift`), so the parse and the editor-completion
    /// schema can never drift. Read-only by design: halo never writes the
    /// user's config (only the schema sidecar, via `installSchema`).
    static func load() -> HaloConfig {
        var c = HaloConfig()
        guard let text = try? String(contentsOfFile: configFilePath, encoding: .utf8)
        else { return c }
        configSpec.decode(Toml.parseFlat(text).tables, into: &c)
        return c
    }
}

// (The `color` key parses via sill's shared grammar — `parseColorToken`
// from Palette, re-exported through Effects, materialized with the 0.6
// `NSColor(_ hex: HexColor)` bridge. The old local 6-digit-only
// `NSColor(hex: String)` extension is retired; the shared grammar is a
// superset: named colors, #rgb, #rrggbb, #rrggbbaa.)

/// Anchored `*` / `?` glob match, case-insensitive — the same grammar
/// wand's `[exclude].apps` documents, so one exclusion list reads the
/// same family-wide.
func globMatch(_ pattern: String, _ s: String) -> Bool {
    var re = "^"
    for ch in pattern.lowercased() {
        switch ch {
        case "*": re += ".*"
        case "?": re += "."
        default:  re += NSRegularExpression.escapedPattern(for: String(ch))
        }
    }
    re += "$"
    return s.lowercased().range(of: re, options: .regularExpression) != nil
}
