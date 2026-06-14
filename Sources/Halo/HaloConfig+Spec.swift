// HaloConfig+Spec — the ONE declarative description of halo's
// `config.toml` surface. sill's `ConfigSchema.Spec` turns this single
// source into BOTH:
//
//   • the decode (`HaloConfig.load` → `configSpec.decode`)
//   • the JSON Schema (`halo --emit-schema`) taplo uses for editor
//     completion + validation
//
// so a key can never be in the parser but missing from the schema (or
// vice-versa). The `apply` closures reproduce the old hand-written reads
// EXACTLY (same lowercase/validate/clamp/transform), so the resolved
// config is byte-identical — proven by the parity harness during the
// config-schema slice.
//
// Enum DOMAINS come from the single sources of truth: sill's
// `canonicalEffectNames` / `canonicalLinePetNames` (re-exported through
// `Effects`). Numeric `min`/`max` mirror the clamps in `load` (advisory
// in the editor; the app still clamps at runtime so a typo can't break
// the ring). The `color` key has NO enum — `parseColorToken` accepts a
// runtime-open grammar (named colors + `#rgb`/`#rrggbb`/`#rrggbbaa`), so
// an enum would false-flag valid values.

import AppKit
import ConfigSchema
import Effects
import Toml

extension HaloConfig {

    /// The single declarative spec. Drives `load`'s decode and
    /// `--emit-schema`. Sections mirror the `[blocks]` in `config.toml`.
    /// Computed (not a stored `let`) so it needn't be `Sendable` — the
    /// `apply` closures capture keypaths; rebuilding ~20 small fields on
    /// the rare config (re)load is free.
    static var configSpec: ConfigSchema.Spec<HaloConfig> {
        ConfigSchema.Spec<HaloConfig>(
        title: "halo config.toml",
        sections: [
            .init("border", doc: "Active-window ring: effect palette + base color, glow, width, cycle, breath.", fields: [
                // Lowercased + validated against the canonical set AT decode
                // (unknown / mistyped names keep the default) — so the apply
                // mirrors `load`'s `if canonicalEffectNames.contains(...)`.
                .effect("effect", \.effect, doc: "Effect palette layered on the ring; unknown keeps default."),
                .bool("glow", \.glow, default: true, doc: "Soft outward glow under the stroke."),
                .cgDbl("width", \.width, min: 0, default: 3, doc: "Ring line width (points)."),
                // `color-cycle-ms` is an integer-ms knob the editor sees, but
                // `load` stores it as seconds (`max(100, v)/1000`); the apply
                // reproduces that transform + floor exactly.
                .cycleMs("color-cycle-ms", \.cycleSeconds, default: 6000,
                         doc: "Animation period (ms): rainbow hue rotation / cycle-colors / width breath."),
                .bool("cycle-colors", \.cycleColors, default: false,
                      doc: "Loop a non-rainbow effect through its own flash palette."),
                .cgDblOpt("min-width", \.minWidth, doc: "Width-breathing floor (set with max-width, max > min)."),
                .cgDblOpt("max-width", \.maxWidth, doc: "Width-breathing ceil."),
                // No enum: `parseColorToken` accepts named colors + hex
                // (`#rgb`/`#rrggbb`/`#rrggbbaa`) — a runtime-open grammar.
                .color("color", \.color, doc: "Resting color when effect = off (name or #RRGGBB)."),
                .cgDbl("corner-radius", \.cornerRadius, min: 0, default: 10,
                       doc: "Ring corner radius (points)."),
                .cgDbl("pad", \.pad, min: 0, default: 4,
                       doc: "Gap between the window edge and the ring (points)."),
                .cgDbl("min-size", \.minSize, min: 0, default: 80,
                       doc: "Ignore windows smaller than this (drops tiny popups)."),
            ]),

            .init("exclude", doc: "Bundle IDs that never get a ring.", fields: [
                .strArray("apps", \.excludedApps,
                          doc: "Bundle-id globs (`*` / `?`), e.g. \"com.apple.finder\", \"*chrome*\"; `[]` = none."),
            ]),

            .init("shake", doc: "Focus-shake: a quick horizontal jiggle of the focused window (needs Accessibility).", fields: [
                .bool("shake", \.shake, default: true, doc: "Jiggle the focused window on focus change."),
                .cgDbl("shake-amplitude", \.shakeAmplitude, min: 0, default: 10,
                       doc: "Peak horizontal swing (points)."),
                // duration floors at 1 ms in `load`.
                .dblFloor("shake-duration-ms", \.shakeDurationMs, floor: 1, default: 250,
                          doc: "Total shake duration (ms)."),
            ]),

            .init("sound", doc: "Focus-sound: play a short audio cue on focus change (no permission).", fields: [
                .str("sound", \.sound, default: "",
                     doc: "Audio file path; empty = off. e.g. \"~/.local/share/sounds/window_focused.wav\"."),
                // volume clamps to [0, 1] in `load`.
                .dblClamp("sound-volume", \.soundVolume, min: 0, max: 1, default: 0.3,
                          doc: "Playback volume, 0.0 … 1.0."),
            ]),

            .init("pets", doc: "Line-pets: arcade sprites that orbit the ring (opt-in, no permission).", fields: [
                // Tokens lowercased, unknown dropped + logged against the
                // canonical pet set — mirrors `load`'s clamp-and-log.
                .pets("line-pets", \.linePets, item: canonicalLinePetNames,
                      doc: "Pets orbiting the ring; `[]` = off. e.g. [\"chomp\", \"ghost\"]."),
                .cgDblFloor("pet-scale", \.petScale, floor: 0.1, default: 1.5,
                            doc: "Pet size multiplier."),
                .cgDblFloor("pet-lap-seconds", \.petLapSeconds, floor: 0.5, default: 8,
                            doc: "Seconds for a pet to circle the window once."),
            ]),
        ]
        )
    }

    // MARK: - JSON Schema (taplo) — emitted from the SAME `configSpec`

    /// The `config.toml` JSON Schema (Draft-07). Drives `halo
    /// --emit-schema` and the sidecar install — generated from the one
    /// `configSpec`, so it can never drift from the decode.
    static var jsonSchema: String { configSpec.jsonSchema() }

    /// Where the schema sidecar lives — next to the user config, so a
    /// `#:schema ./config.schema.json` directive resolves on the user's
    /// machine (taplo reads it relative to the .toml's own directory).
    static var schemaPath: String {
        (configFilePath as NSString).deletingLastPathComponent
            + "/config.schema.json"
    }

    /// Write the schema next to the user config. IDEMPOTENT (writes only
    /// when the content differs) so it never churns the file or trips the
    /// watcher (which polls `config.toml`'s mtime, not this sibling).
    /// Creates `~/.config/halo/` if absent. Best-effort: a failure is
    /// non-fatal (completion just won't resolve), so the app never fails
    /// to start over it. Returns true if it actually wrote.
    @discardableResult
    static func installSchema() -> Bool {
        let path = schemaPath
        let dir = (path as NSString).deletingLastPathComponent
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let want = jsonSchema
        if let current = try? String(contentsOfFile: path, encoding: .utf8),
           current == want {
            return false
        }
        return (try? want.write(toFile: path, atomically: true, encoding: .utf8)) != nil
    }
}

// MARK: - Field builders (keypath + Toml accessor → declarative field)

private extension ConfigSchema.Field where Root == HaloConfig {
    /// Plain string passthrough.
    static func str(_ key: String, _ kp: WritableKeyPath<HaloConfig, String>,
                    enum domain: [String]? = nil, default def: String? = nil,
                    doc: String? = nil) -> Self {
        .init(key: key, kind: .scalar(.string),
              apply: { c, v in if let s = v.asString { c[keyPath: kp] = s } },
              domain: domain, def: def.map { .string($0) }, doc: doc)
    }
    /// Bool.
    static func bool(_ key: String, _ kp: WritableKeyPath<HaloConfig, Bool>,
                     default def: Bool? = nil, doc: String? = nil) -> Self {
        .init(key: key, kind: .scalar(.boolean),
              apply: { c, v in if let b = v.asBool { c[keyPath: kp] = b } },
              def: def.map { .bool($0) }, doc: doc)
    }
    /// Number in TOML (int OR fractional) → `CGFloat` field, no clamp.
    static func cgDbl(_ key: String, _ kp: WritableKeyPath<HaloConfig, CGFloat>,
                      min lo: Double? = nil, max hi: Double? = nil,
                      default def: Double? = nil, doc: String? = nil) -> Self {
        .init(key: key, kind: .scalar(.number),
              apply: { c, v in if let d = v.asDouble { c[keyPath: kp] = CGFloat(d) } },
              def: def.map { .number($0) }, min: lo, max: hi, doc: doc)
    }
    /// Number → optional `CGFloat?` (the width-breathing bounds).
    static func cgDblOpt(_ key: String, _ kp: WritableKeyPath<HaloConfig, CGFloat?>,
                         min lo: Double? = nil, max hi: Double? = nil,
                         doc: String? = nil) -> Self {
        .init(key: key, kind: .scalar(.number),
              apply: { c, v in if let d = v.asDouble { c[keyPath: kp] = CGFloat(d) } },
              min: lo, max: hi, doc: doc)
    }
    /// Number → `CGFloat` with a lower floor (`max(floor, v)`).
    static func cgDblFloor(_ key: String, _ kp: WritableKeyPath<HaloConfig, CGFloat>,
                           floor lo: Double, default def: Double? = nil,
                           doc: String? = nil) -> Self {
        .init(key: key, kind: .scalar(.number),
              apply: { c, v in if let d = v.asDouble { c[keyPath: kp] = CGFloat(Swift.max(lo, d)) } },
              def: def.map { .number($0) }, min: lo, doc: doc)
    }
    /// Number → `Double` with a lower floor (`max(floor, v)`).
    static func dblFloor(_ key: String, _ kp: WritableKeyPath<HaloConfig, Double>,
                         floor lo: Double, default def: Double? = nil,
                         doc: String? = nil) -> Self {
        .init(key: key, kind: .scalar(.number),
              apply: { c, v in if let d = v.asDouble { c[keyPath: kp] = Swift.max(lo, d) } },
              def: def.map { .number($0) }, min: lo, doc: doc)
    }
    /// Number → `Double` clamped to `[min, max]`.
    static func dblClamp(_ key: String, _ kp: WritableKeyPath<HaloConfig, Double>,
                         min lo: Double, max hi: Double, default def: Double? = nil,
                         doc: String? = nil) -> Self {
        .init(key: key, kind: .scalar(.number),
              apply: { c, v in if let d = v.asDouble { c[keyPath: kp] = Swift.max(lo, Swift.min(hi, d)) } },
              def: def.map { .number($0) }, min: lo, max: hi, doc: doc)
    }
    /// `color-cycle-ms` (integer ms in the editor) → seconds field with
    /// `max(100, v)/1000` — mirrors `load`'s transform + floor. Schema
    /// `min` is the 100 ms floor; default is shown in ms (6000).
    static func cycleMs(_ key: String, _ kp: WritableKeyPath<HaloConfig, CGFloat>,
                        default def: Int, doc: String? = nil) -> Self {
        .init(key: key, kind: .scalar(.integer),
              apply: { c, v in if let d = v.asDouble { c[keyPath: kp] = Swift.max(100, CGFloat(d)) / 1000 } },
              def: .int(def), min: 100, doc: doc)
    }
    /// `[border] effect` — lowercased + validated against
    /// `canonicalEffectNames` at decode; an unknown name keeps the
    /// default. Schema enum = the canonical set.
    static func effect(_ key: String, _ kp: WritableKeyPath<HaloConfig, String>,
                       doc: String? = nil) -> Self {
        .init(key: key, kind: .scalar(.string),
              apply: { c, v in
                  if let s = v.asString {
                      let lower = s.lowercased()
                      if canonicalEffectNames.contains(lower) { c[keyPath: kp] = lower }
                  }
              },
              domain: canonicalEffectNames, def: .string("neon"), doc: doc)
    }
    /// `[border] color` — `parseColorToken` → `NSColor` (no enum; the
    /// grammar is runtime-open).
    static func color(_ key: String, _ kp: WritableKeyPath<HaloConfig, NSColor>,
                      doc: String? = nil) -> Self {
        .init(key: key, kind: .scalar(.string),
              apply: { c, v in
                  if let s = v.asString, let hex = parseColorToken(s) {
                      c[keyPath: kp] = NSColor(hex)
                  }
              },
              def: .string("#39C5C8"), doc: doc)
    }
    /// Plain string array (the `[exclude] apps` glob list).
    static func strArray(_ key: String, _ kp: WritableKeyPath<HaloConfig, [String]>,
                         item: [String]? = nil, doc: String? = nil) -> Self {
        .init(key: key, kind: .stringArray(item: item),
              apply: { c, v in if let a = v.asStringArray { c[keyPath: kp] = a } },
              doc: doc)
    }
    /// `[pets] line-pets` — tokens lowercased, unknown dropped + logged
    /// against `canonicalLinePetNames`, then mapped to `LinePet` (mirrors
    /// `load`'s clamp-and-log).
    static func pets(_ key: String, _ kp: WritableKeyPath<HaloConfig, [LinePet]>,
                     item: [String]? = nil, doc: String? = nil) -> Self {
        .init(key: key, kind: .stringArray(item: item),
              apply: { c, v in
                  guard let raw = v.asStringArray else { return }
                  let tokens = raw
                      .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                      .filter { !$0.isEmpty }
                  let unknown = tokens.filter { !canonicalLinePetNames.contains($0) }
                  if !unknown.isEmpty {
                      Log.line("config: line-pets contains unrecognised "
                               + "entry \(unknown.joined(separator: ", ")) — dropped "
                               + "(valid: \(canonicalLinePetNames.sorted().joined(separator: ", ")))")
                  }
                  c[keyPath: kp] = tokens.compactMap { LinePet(rawValue: $0) }
              },
              doc: doc)
    }
}
