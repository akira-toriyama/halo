import ConfigSchema
import Foundation
import Palette
import Toml

// halo configuration. Mirrors facet's `[border]` config surface (same
// keys / semantics) so the two feel the same: an `effect` palette layered
// on a base color, with glow / width / cycle / breath. Read from
// ~/.config/halo/config.toml at launch and hot-reloaded on every mtime
// change (`BorderController.reloadIfConfigChanged`, off the 0.4s
// safety-net poll); unknown / malformed keys keep their default (facet's
// clamp-to-default — a typo can never break the ring).
//
// Pure: colors stay `HexColor` (sill's Palette vocabulary); the app
// materializes `NSColor` at the AppKit seam. Decode is driven by ONE
// declarative `configSpec` (see `HaloConfig+Spec.swift`), which ALSO
// emits the `config.toml` JSON Schema (`halo --emit-schema`) — so the
// parser and the editor-completion schema can never drift.
public struct HaloConfig: Sendable {
    // --- border theme (mirror of facet [border]) ---
    public var effect: String       = "neon"     // off | neon | cyber | vapor | kawaii | rainbow | chomp | random
    public var glow: Bool           = true
    public var width: CGFloat       = 3
    public var cycleSeconds: CGFloat = 6          // rainbow / cycle-colors / breath period
                                                   // (config key is `color-cycle-ms`; stored in
                                                   //  seconds because the 30 Hz tick divides by it)
    public var cycleColors: Bool    = false       // loop a non-rainbow effect through its flash palette
    public var minWidth: CGFloat?   = nil         // set both min/max (max>min) → width breathes
    public var maxWidth: CGFloat?   = nil
    public var color: HexColor      = HexColor(0x39C5C8)   // resting color when effect = off

    // --- halo-specific geometry / scope ---
    public var cornerRadius: CGFloat = 10
    public var pad: CGFloat         = 4            // gap window edge → ring
    public var minSize: CGFloat     = 80          // ignore tiny popups
    /// `[exclude].apps` — bundle-id globs (family-shared shape; wand's
    /// grammar: `*` / `?`, e.g. "com.apple.finder", "*chrome*").
    public var excludedApps: [String] = []

    /// True when `bundleID` matches an `[exclude].apps` glob. The app
    /// resolves pid → bundle id (an `NSRunningApplication` lookup) and
    /// only when an exclusion is configured — see `BorderController`.
    public func isExcluded(bundleID: String) -> Bool {
        excludedApps.contains { globMatch($0, bundleID) }
    }

    // --- focus shake (moves the real window — needs Accessibility) ---
    public var shake: Bool             = true     // jiggle the focused window on focus change
    public var shakeAmplitude: CGFloat = 10       // peak horizontal swing (pt)
    public var shakeDurationMs: Double = 250      // total shake duration (ms)

    // --- focus sound (plays an audio cue on focus change — no permission) ---
    public var sound: String       = ""           // audio file path; empty = off
    public var soundVolume: Double  = 0.3          // 0…1

    // --- line-pets (arcade sprites orbiting the ring; opt-in, no permission) ---
    public var linePets: [LinePet]  = []          // e.g. "chomp, ghost"; empty = off
    public var petScale: CGFloat    = 1.5         // pet size ×multiplier (halo has no font-size to scale from)
    public var petLapSeconds: CGFloat = 8         // seconds to orbit the ring once — window-size-independent
                                                   // (constant pt/s would crawl on a big window, sprint on a small one)

    public init() {}

    /// The user config path (`~/.config/halo/config.toml`, tilde
    /// expanded). The schema sidecar (`HaloConfig.schemaPath`) is written
    /// next to it.
    public static var configFilePath: String {
        ("~/.config/halo/config.toml" as NSString).expandingTildeInPath
    }

    /// Read + decode `~/.config/halo/config.toml`. Missing / unreadable →
    /// all defaults. Every schema violation is logged first
    /// (`warnSchemaViolations`) so a hot-reload that "did nothing" says
    /// why in /tmp/halo.log; the lenient decode then runs regardless.
    /// Read-only by design: halo never writes the user's config (only the
    /// schema sidecar, via `installSchema`).
    public static func load() -> HaloConfig {
        guard let text = try? String(contentsOfFile: configFilePath, encoding: .utf8)
        else { return HaloConfig() }
        warnSchemaViolations(text)
        return parse(text)
    }

    /// Structural validation against the SAME `configSpec` that drives the
    /// decode and `--emit-schema` (sill's `Spec.validate`): the STRICT
    /// counterpart to the lenient `parse`, surfacing the type / enum /
    /// range / unknown-key mismatches the decode clamps or drops. Returns
    /// every violation (empty = valid); throws only when `text` is not
    /// parseable TOML at all.
    public static func validate(_ text: String) throws -> [ValidationError] {
        configSpec.validate(try Toml.parse(text))
    }

    /// Load-path validate (the family shape — facet / wand / perch): each
    /// violation becomes one `config: …` line via `Log.line`; nothing is
    /// rejected. A non-parseable source yields zero warnings (the lenient
    /// decode still continues). Returns the violation count.
    @discardableResult
    public static func warnSchemaViolations(_ text: String) -> Int {
        let errors = (try? validate(text)) ?? []
        for e in errors { Log.line("config: \(e.message)") }
        return errors.count
    }

    /// Decode config.toml SOURCE. The uniform `[block]` keys are driven by
    /// the single declarative `configSpec` (which ALSO emits the JSON
    /// Schema — see `HaloConfig+Spec.swift`), so the parse and the
    /// editor-completion schema can never drift.
    public static func parse(_ text: String) -> HaloConfig {
        var c = HaloConfig()
        configSpec.decode(Toml.parseFlat(text).tables, into: &c)
        return c
    }
}

/// Anchored `*` / `?` glob match, case-insensitive — the same grammar
/// wand's `[exclude].apps` documents, so one exclusion list reads the
/// same family-wide.
public func globMatch(_ pattern: String, _ s: String) -> Bool {
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
