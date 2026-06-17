// halo's border STYLE holder — thin, timer-less state over sill's pure
// `resolveBorder`. Holds the `[border]` config + the focus-flash cell; the
// ring view samples `color` / `width` each repaint. The redraw CADENCE is
// owned by `BorderController`'s one 30 Hz clock (shared with the line-pets),
// NOT here — so the border and the pets ride a SINGLE wall-clock `now`, and
// there's no longer a timer that exists just to keep redrawing pets (the old
// `petsActive` hack is gone).
//
// The animation MATH — width breathing, the 5-blink flash burst, and the
// rainbow / cycle / steady color resolve — lives in sill's CLOCKLESS
// `Effects.resolveBorder` / `rollFlash`, shared byte-for-byte with facet (the
// formerly-duplicated `BorderFX` animator, reconciled into one pure function).
// halo keeps only the app-side bits: the `NSColor` materialization and the
// configurable `baseColor` "off" fallback (halo has no panel palette, so it
// can't fall back to facet's per-surface `pal.primary`).
//
// Not @MainActor (unlike facet's): halo is single-threaded on the main run
// loop, so the isolation would just propagate friction with no safety gain.

import AppKit
import Effects
import QuartzCore   // CACurrentMediaTime — the shared border + pets clock

final class BorderFX {
    // Config (from the border config).
    private var fx: EffectSpec?
    private var glowOn = false
    private var baseW: Double = 3
    private var cycleSeconds: Double = 6
    private var minW: Double?
    private var maxW: Double?
    private var cycleColors = false
    /// Resting color when no effect is active ("off").
    var baseColor: NSColor = .systemTeal

    /// The focus-flash burst — pre-rolled on a focus change, decayed by
    /// wall-clock. nil = not flashing.
    private var flashState: FlashState?

    init() {}

    func configure(effectName: String, glow: Bool, width: CGFloat,
                   cycleSeconds cs: CGFloat, cycleColors cc: Bool,
                   minWidth: CGFloat?, maxWidth: CGFloat?, baseColor bc: NSColor) {
        fx = borderEffectFor(effectName)
        glowOn = glow
        baseW = Double(width)
        cycleSeconds = max(1, Double(cs))
        cycleColors = cc
        minW = minWidth.map(Double.init)
        maxW = maxWidth.map(Double.init)
        baseColor = bc
    }

    var glowEnabled: Bool { glowOn }

    /// The ring's color + width for wall-clock `now` — sampled ONCE per
    /// `draw(_:)` so the two stay consistent across a flash boundary (and so
    /// the border shares the exact `now` the pets walk on).
    func sample(at now: Double) -> (color: NSColor, width: CGFloat) {
        let fr = resolveBorder(spec: fx, baseWidth: baseW, minWidth: minW, maxWidth: maxW,
                               cycleSeconds: cycleSeconds, cycleColors: cycleColors,
                               now: now, flash: flashState)
        let color: NSColor
        switch fr.color {
        case .off:
            color = baseColor
        case .rgb(let r, let g, let b):
            color = NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
        case .rainbowHue(let h):
            color = NSColor(hue: CGFloat(h), saturation: 0.9, brightness: 1, alpha: 1)
        }
        return (color, CGFloat(fr.width))
    }

    /// Start a focus flash: a 5-blink burst through the effect's palette.
    /// No-op when off / palette-less (then the ring just re-hugs silently).
    func flash() {
        guard let fx, !fx.flash.isEmpty else { return }
        flashState = rollFlash(fx.flash, now: CACurrentMediaTime())
    }

    /// Is the BORDER itself animating right now? (rainbow / cycle-colors /
    /// breathing, or a flash burst mid-flight.) `BorderController`'s redraw
    /// clock ORs this with "has line-pets" to decide whether to keep ticking.
    func animating(at now: Double) -> Bool {
        let cyclingOrBreathing = (fx?.cycles ?? false) || (cycleColors && fx != nil) || breathing
        if fx != nil && cyclingOrBreathing { return true }
        return flashState?.isActive(now: now) ?? false
    }

    private var breathing: Bool {
        guard fx != nil, let lo = minW, let hi = maxW else { return false }
        return hi > lo
    }
}
